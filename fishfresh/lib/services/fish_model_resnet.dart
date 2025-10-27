// lib/services/fish_model.dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures, unused_local_variable, unused_field, unused_element, unintended_html_in_doc_comment

import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Normalization presets (RGB only in this app)
enum NormProfile { imagenet, zeroToOne, minusOneToOne }

/// FishModel — ResNet-50 ready (RGB + ImageNet mean/std)
///
/// Key changes vs your previous file:
/// • Reads the model's true input size from the interpreter (no hardcoded 260).
/// • Uses torchvision-style eval preprocess by default:
///     Resize(shorter-side = 256) → CenterCrop(side) when side==224,
///   and scales proportionally for other side values (scale = 256/side).
/// • Locks preprocessing to RGB + ImageNet mean/std (float32) or proper quant (int8/uint8).
/// • Keeps your label block logic [fresh__* ... not_fresh__*] and pair prediction.
class FishModelResNet {
  Interpreter? _interpreter;
  bool _initialized = false;

  // === Labels ===
  late List<String> combinedLabels;         // final list used for mapping
  late List<String> _originalLoadedLabels;  // raw json (for debugging)
  final String _freshPrefix = 'fresh__';
  final String _notFreshPrefix = 'not_fresh__';

  // === Config (model/labels) ===
  final String modelAssetPath;
  final String labelsAssetPath;

  // Optional probabilistic ensemble (RGB norms only) when input is float32
  final bool _useEnsemble;

  /// Debug
  final bool debugTopK;
  final int debugTopKCount;

  // ---- Preprocess selection (locked to RGB) ----
  bool _preprocessLocked = true;         // keep locked (we already know the norm)
  final bool _lockedUseRgb = true;       // ALWAYS RGB
  NormProfile _lockedNorm = NormProfile.imagenet;

  // Cached IO tensor meta
  late Tensor _inTensor;
  late Tensor _outTensor;
  late TensorType _inType;
  late TensorType _outType;

  // Determined at runtime from the model
  late int _side;            // H==W (e.g., 224)
  late double _resizeScale;  // e.g., 256/224 for torchvision

  FishModelResNet({
    this.modelAssetPath = 'assets/model/resnet50Oct_24_5-19_am_float32.tflite',     // <- update filename here
    this.labelsAssetPath = 'assets/model/classes_flat.json',
    bool useEnsemble = false, // default: off
    this.debugTopK = false,
    this.debugTopKCount = 12,
  }) : _useEnsemble = useEnsemble;

  // ===== Utilities: shapes, builders, flatteners =====

  List _as4DFloat(Float32List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0.0))));
    int idx = 0;
    for (int ni = 0; ni < n; ni++) {
      for (int yi = 0; yi < h; yi++) {
        for (int xi = 0; xi < w; xi++) {
          for (int ci = 0; ci < c; ci++) {
            out[ni][yi][xi][ci] = flat[idx++];
          }
        }
      }
    }
    return out;
  }

  List _as4DUint8(Uint8List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0))));
    int idx = 0;
    for (int ni = 0; ni < n; ni++) {
      for (int yi = 0; yi < h; yi++) {
        for (int xi = 0; xi < w; xi++) {
          for (int ci = 0; ci < c; ci++) {
            out[ni][yi][xi][ci] = flat[idx++];
          }
        }
      }
    }
    return out;
  }

  List _as4DInt8(Int8List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0))));
    int idx = 0;
    for (int ni = 0; ni < n; ni++) {
      for (int yi = 0; yi < h; yi++) {
        for (int xi = 0; xi < w; xi++) {
          for (int ci = 0; ci < c; ci++) {
            out[ni][yi][xi][ci] = flat[idx++];
          }
        }
      }
    }
    return out;
  }

  Object _zerosLikeShape(List<int> shape, TensorType type) {
    Object build(List<int> dims) {
      if (dims.isEmpty) {
        switch (type) {
          case TensorType.float32:
            return 0.0;
          case TensorType.uint8:
          case TensorType.int8:
          case TensorType.int32:
            return 0;
          default:
            return 0;
        }
      }
      final len = dims.first;
      final tail = dims.sublist(1);
      return List.generate(len, (_) => build(tail));
    }
    return build(shape);
  }

  List<double> _flattenToDoubleList(dynamic obj) {
    final out = <double>[];
    void walk(dynamic x) {
      if (x is List) {
        for (final e in x) walk(e);
      } else if (x is num) {
        out.add(x.toDouble());
      }
    }
    walk(obj);
    return out;
  }

  // ===== Initialization =====

  Future<void> init() async {
    if (_initialized) return;

    // --- Load labels exactly as-is (fresh block then not_fresh block) ---
    final jsonStr = await rootBundle.loadString(labelsAssetPath);
    final parsed = json.decode(jsonStr);

    List<String> loaded;
    if (parsed is List) {
      loaded = List<String>.from(parsed);
    } else if (parsed is Map<String, dynamic>) {
      final species = List<String>.from(parsed['species_classes'] ?? const []);
      final fresh = species.map((s) => 'fresh__${s}').toList();
      final notFresh = species.map((s) => 'not_fresh__${s}').toList();
      loaded = [...fresh, ...notFresh];
    } else {
      throw Exception('Unsupported classes json format in $labelsAssetPath');
    }
    _originalLoadedLabels = List<String>.from(loaded);
    combinedLabels = loaded;

    print('LABELS (index:name):');
    for (var i = 0; i < combinedLabels.length; i++) {
      print('  $i: ${combinedLabels[i]}');
    }

    // --- Load interpreter ---
    _interpreter = await Interpreter.fromAsset(modelAssetPath);

    // --- Cache IO tensor meta ---
    _inTensor = _interpreter!.getInputTensor(0);
    _outTensor = _interpreter!.getOutputTensor(0);
    _inType = _inTensor.type;
    _outType = _outTensor.type;

    final inShape = _inTensor.shape; // expect [1, H, W, 3]
    print('🧪 Input tensor shape: $inShape  dtype: $_inType');
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      throw Exception('Unexpected input shape $inShape. Expected [1, H, W, 3].');
    }

    final int h = inShape[1], w = inShape[2];
    if (h != w) {
      print('⚠️ Non-square input $w×$h. Center-crop will use min(h,w).');
    }
    _side = math.min(h, w); // use the model’s required side

    // torchvision-style: Resize(shorter-side=256) → CenterCrop(side)
    // For non-224 models, scale proportionally: scale = 256/side
    _resizeScale = 256.0 / _side;

    final outShape = _outTensor.shape; // e.g., [1, N]
    final numUnits = outShape.isNotEmpty ? outShape.last : 0;

    print('📦 Loaded TFLite: $modelAssetPath');
    print('   • Output shape: $_outType ${_outTensor.shape}');
    print('   • Labels: ${combinedLabels.length} | Output units: $numUnits');
    if (combinedLabels.length != numUnits) {
      print('🚨 Label count and output units differ. Update classes_flat.json to match the head used during export.');
    }
    print('   • Preprocess: RGB only, ${_lockedNorm.name}, resize(shorter=${(_resizeScale * _side).toStringAsFixed(1)})→center-crop($_side)');

    _initialized = true;
    print('✅ Model initialized');
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // --- Helpers: label parsing ---
  String _freshnessFromCombined(String combined) {
    if (combined.startsWith(_freshPrefix)) return 'Fresh';
    if (combined.startsWith(_notFreshPrefix)) return 'Not Fresh';
    return 'Unknown';
  }

  String _speciesFromCombined(String combined) {
    if (combined.startsWith(_freshPrefix)) {
      return combined.substring(_freshPrefix.length);
    }
    if (combined.startsWith(_notFreshPrefix)) {
      return combined.substring(_notFreshPrefix.length);
    }
    return combined;
  }

  // --- Numerics ---
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  void _logTopK(List<double> probs, {int k = 5}) {
    final pairs = <MapEntry<int, double>>[];
    for (int i = 0; i < probs.length; i++) {
      pairs.add(MapEntry(i, probs[i]));
    }
    pairs.sort((a, b) => b.value.compareTo(a.value));
    final top = pairs.take(k).toList();
    print('🔎 Top-$k:');
    for (final e in top) {
      final idx = e.key;
      final p = e.value;
      final label = (idx < combinedLabels.length) ? combinedLabels[idx] : '??';
      print('   #$idx  ${label.padRight(32)}  p=${(p * 100).toStringAsFixed(2)}%');
    }
  }

  // --- Geometry: Resize(shorter-side = scale*side) → CenterCrop(side) ---
  img.Image _resizeShortSideThenCenterCrop(img.Image im) {
    final int side = _side;
    final double scale = _resizeScale; // e.g., 256/224 for ResNet-50

    final int w = im.width, h = im.height;
    final int targetShort = math.max(1, (side * scale).round());

    final double shortSide = math.min(w, h).toDouble();
    final double scaleFactor = targetShort / shortSide;
    final int newW = math.max(1, (w * scaleFactor).round());
    final int newH = math.max(1, (h * scaleFactor).round());

    final img.Image resized = img.copyResize(im, width: newW, height: newH);

    final int x0 = math.max(0, (resized.width - side) ~/ 2);
    final int y0 = math.max(0, (resized.height - side) ~/ 2);
    final int cropW = math.min(side, resized.width);
    final int cropH = math.min(side, resized.height);

    final img.Image cropped = img.copyCrop(resized, x: x0, y: y0, width: cropW, height: cropH);

    if (cropped.width != side || cropped.height != side) {
      return img.copyResize(cropped, width: side, height: side);
    }
    return cropped;
  }

  // ======== RGB-only builders & runners ========

  Object _buildInputNHWC(img.Image resized) {
    final int n = 1, h = _side, w = _side, c = 3;

    if (_inType == TensorType.uint8) {
      final flat = Uint8List(h * w * c);
      int i = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          flat[i++] = p.r.toInt();
          flat[i++] = p.g.toInt();
          flat[i++] = p.b.toInt();
        }
      }
      return _as4DUint8(flat, n, h, w, c);
    }

    if (_inType == TensorType.int8) {
      final qp = _inTensor.params;
      final double scale = qp.scale;
      final int zeroPoint = qp.zeroPoint;

      final flat = Int8List(h * w * c);
      int i = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          final r0 = p.r.toDouble();
          final g0 = p.g.toDouble();
          final b0 = p.b.toDouble();
          flat[i++] = (((r0 / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
          flat[i++] = (((g0 / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
          flat[i++] = (((b0 / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
        }
      }
      return _as4DInt8(flat, n, h, w, c);
    }

    if (_inType == TensorType.float32) {
      final flat = Float32List(h * w * c);
      int i = 0;

      const meanIM = [0.485, 0.456, 0.406];
      const stdIM = [0.229, 0.224, 0.225];

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

          if (_lockedNorm == NormProfile.imagenet) {
            r = (r - meanIM[0]) / stdIM[0];
            g = (g - meanIM[1]) / stdIM[1];
            b = (b - meanIM[2]) / stdIM[2];
          } else if (_lockedNorm == NormProfile.minusOneToOne) {
            r = r * 2.0 - 1.0;
            g = g * 2.0 - 1.0;
            b = b * 2.0 - 1.0;
          } // zeroToOne = keep 0..1

          flat[i++] = r;
          flat[i++] = g;
          flat[i++] = b;
        }
      }
      return _as4DFloat(flat, n, h, w, c);
    }

    throw Exception('Unsupported input tensor type: $_inType');
  }

  Object _buildOutputBuffer() {
    final outShape = _outTensor.shape;
    return _zerosLikeShape(outShape, _outType);
  }

  List<double> _extractLogits(Object outputBuffer) {
    if (_outType == TensorType.float32) {
      return _flattenToDoubleList(outputBuffer);
    }
    // Quantized output: dequantize using scale/zeroPoint
    try {
      final qp = _outTensor.params;
      final double scale = qp.scale;
      final int zeroPoint = qp.zeroPoint;
      final rawNums = <int>[];
      void walk(dynamic x) {
        if (x is List) {
          for (final e in x) walk(e);
        } else if (x is num) {
          rawNums.add(x.toInt());
        }
      }
      walk(outputBuffer);
      return rawNums.map((v) => scale * (v - zeroPoint)).toList();
    } catch (_) {
      return _flattenToDoubleList(outputBuffer);
    }
  }

  // Build a float32 input for a given normalization and run once (RGB only).
  List<double> _probsForNorm(img.Image pre, {required NormProfile norm}) {
    final saved = _lockedNorm;
    _lockedNorm = norm;

    final inputNHWC = _buildInputNHWC(pre);
    final output = _buildOutputBuffer();
    _interpreter!.run(inputNHWC, output);

    final logits = _extractLogits(output);
    final probs = _softmax(logits);

    _lockedNorm = saved;
    return probs;
  }

  // Average probabilities across RGB-only norms.
  List<double> _probsFromEnsemble(img.Image pre) {
    final variants = <NormProfile>[
      NormProfile.imagenet,
      NormProfile.zeroToOne,
      NormProfile.minusOneToOne,
    ];

    List<double>? sum;
    for (final v in variants) {
      final probs = _probsForNorm(pre, norm: v);
      if (sum == null) {
        sum = List<double>.from(probs);
      } else {
        for (int i = 0; i < sum.length; i++) sum[i] += probs[i];
      }
    }
    for (int i = 0; i < sum!.length; i++) sum[i] /= variants.length;

    if (debugTopK) {
      final pairs = <MapEntry<int, double>>[];
      for (int i = 0; i < sum.length; i++) pairs.add(MapEntry(i, sum[i]));
      pairs.sort((a, b) => b.value.compareTo(a.value));
      final top = pairs.take(3).toList();
      print('🧮 Ensemble (RGB-only) consensus top:');
      for (final e in top) {
        final lbl = (e.key < combinedLabels.length) ? combinedLabels[e.key] : 'unknown';
        print('   ${lbl.padRight(32)} ${(e.value * 100).toStringAsFixed(1)}%');
      }
    }

    return sum;
  }

  // ======= Public prediction APIs =======

  Future<Map<String, dynamic>> predict(String imagePath) async {
    if (!_initialized) throw StateError('Call init() first');

    try {
      // 1) Load & preprocess (EXIF orientation, resize→center-crop to _side×_side)
      final bytes = await File(imagePath).readAsBytes();
      final decoded0 = img.decodeImage(bytes);
      if (decoded0 == null) throw Exception('Cannot decode image: $imagePath');
      final decoded = img.bakeOrientation(decoded0);
      final preprocessed = _resizeShortSideThenCenterCrop(decoded);

      // 2) Build input / run model
      List<double> probs;
      if (_inType == TensorType.float32 && _useEnsemble) {
        probs = _probsFromEnsemble(preprocessed);
      } else {
        final inputNHWC = _buildInputNHWC(preprocessed);
        final outputBuffer = _buildOutputBuffer();
        _interpreter!.run(inputNHWC, outputBuffer);
        final logits = _extractLogits(outputBuffer);
        probs = _softmax(logits);
      }

      if (probs.length != combinedLabels.length) {
        print('⚠️ Mismatch: probs=${probs.length} vs labels=${combinedLabels.length}');
      }
      if (debugTopK) _logTopK(probs, k: debugTopKCount);

      // 3) Top-1
      int bestIdx = 0;
      double bestP = -1;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > bestP) {
          bestP = probs[i];
          bestIdx = i;
        }
      }
      final bestLabel = (bestIdx < combinedLabels.length) ? combinedLabels[bestIdx] : 'unknown';

      // Fresh/NotFresh block sums (diagnostic)
      final half = combinedLabels.length ~/ 2;
      final freshSumDbg = probs.take(half).fold<double>(0.0, (a, b) => a + b);
      final notSumDbg = probs.skip(half).fold<double>(0.0, (a, b) => a + b);
      print('Fresh block sum: ${freshSumDbg.toStringAsFixed(3)} | NotFresh block sum: ${notSumDbg.toStringAsFixed(3)}');

      final species = _speciesFromCombined(bestLabel);
      final freshness = _freshnessFromCombined(bestLabel);

      // 4) Breakdowns for UI
      double freshSum = 0, notFreshSum = 0;
      final speciesScores = <String, double>{};
      final freshnessPair = <String, Map<String, double>>{};

      for (int i = 0; i < probs.length; i++) {
        final label = (i < combinedLabels.length) ? combinedLabels[i] : 'unknown';
        final p = probs[i];
        final sp = _speciesFromCombined(label);

        speciesScores.update(sp, (v) => v + p, ifAbsent: () => p);

        final isFresh = label.startsWith(_freshPrefix);
        final key = isFresh ? 'Fresh' : 'Not Fresh';
        final map = (freshnessPair[sp] ??= {'Fresh': 0.0, 'Not Fresh': 0.0});
        map[key] = (map[key] ?? 0.0) + p;

        if (isFresh) freshSum += p; else notFreshSum += p;
      }

      final speciesScoresSorted = Map<String, double>.fromEntries(
        speciesScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      final topkPairs = <MapEntry<int, double>>[];
      for (int i = 0; i < probs.length; i++) topkPairs.add(MapEntry(i, probs[i]));
      topkPairs.sort((a, b) => b.value.compareTo(a.value));
      final topk = topkPairs.take(5).map((e) {
        final lbl = (e.key < combinedLabels.length) ? combinedLabels[e.key] : 'unknown';
        return {'index': e.key, 'label': lbl, 'prob': e.value};
      }).toList();

      final spOrder = speciesScoresSorted.keys.toList();
      if (spOrder.isNotEmpty) {
        final topSp = spOrder.first;
        final pair = freshnessPair[topSp] ?? {'Fresh': 0.0, 'Not Fresh': 0.0};
        final pairFresh = pair['Fresh'] ?? 0.0;
        final pairNot = pair['Not Fresh'] ?? 0.0;
        print(
          '✅ Prediction (species-first) → $freshness | $species | '
          'speciesScore=${(speciesScoresSorted[topSp]! * 100).toStringAsFixed(1)}%  | '
          'pair(F=${(pairFresh * 100).toStringAsFixed(1)}%, NF=${(pairNot * 100).toStringAsFixed(1)}%)',
        );
      } else {
        print('✅ Prediction → $freshness | $species | p=${(bestP * 100).toStringAsFixed(1)}%');
      }

      return {
        'predicted_freshness': freshness,
        'predicted_species': species,
        'confidence': probs[bestIdx],
        'freshness_scores': {'Fresh': freshSum, 'Not Fresh': notFreshSum},
        'species_scores': speciesScoresSorted,
        'topk': topk,
        'best_index': bestIdx,
        'best_label': bestLabel,
      };
    } catch (e, st) {
      print('❌ Prediction error: $e\n$st');
      return {'predicted_freshness': 'Unknown', 'predicted_species': 'Unknown'};
    }
  }

  /// Predict using front + back images with your existing voting rule.
  Future<Map<String, dynamic>> predictPair(String frontPath, String backPath) async {
    if (!_initialized) throw StateError('Call init() first');

    final front = await predict(frontPath);
    final back = await predict(backPath);

    final frontFresh = (front["predicted_freshness"] as String?) ?? "Unknown";
    final backFresh = (back["predicted_freshness"] as String?) ?? "Unknown";
    final finalFreshness = (frontFresh == "Fresh" && backFresh == "Fresh") ? "Fresh" : "Not Fresh";

    final frontSpecies = (front["predicted_species"] as String?) ?? "Unknown";
    final backSpecies = (back["predicted_species"] as String?) ?? "Unknown";
    final frontConf = (front["confidence"] as double?) ?? 0.0;
    final backConf = (back["confidence"] as double?) ?? 0.0;

    final finalSpecies = (frontSpecies == backSpecies)
        ? frontSpecies
        : (frontConf >= backConf ? frontSpecies : backSpecies);

    return {
      "predicted_freshness": finalFreshness,
      "predicted_species": finalSpecies,
      "front_result": front,
      "back_result": back,
    };
  }

  // ======= (Optional) Auto-preprocess (RGB-only and OFF by default) =======
  void _autoSelectPreprocess(img.Image pre) {
    if (_preprocessLocked || _inType != TensorType.float32) return;

    final trials = <Map<String, dynamic>>[
      {'name': 'RGB_ImageNet', 'norm': NormProfile.imagenet},
      {'name': 'RGB_ZeroToOne', 'norm': NormProfile.zeroToOne},
      {'name': 'RGB_MinusOneToOne', 'norm': NormProfile.minusOneToOne},
    ];

    double bestMargin = -1;
    NormProfile bestNorm = _lockedNorm;
    String bestName = '';

    print('🔬 Auto-selecting preprocess variant (RGB-only, one-time):');
    for (final t in trials) {
      final norm = t['norm'] as NormProfile;
      final name = t['name'] as String;

      final probs = _probsForNorm(pre, norm: norm);

      // margin = top1 - top2
      int top1 = 0, top2 = 0;
      double p1 = -1, p2 = -1;
      for (int k = 0; k < probs.length; k++) {
        final v = probs[k];
        if (v > p1) {
          p2 = p1;
          top2 = top1;
          p1 = v;
          top1 = k;
        } else if (v > p2) {
          p2 = v;
          top2 = k;
        }
      }
      final margin = p1 - p2;

      final topLbl = (top1 < combinedLabels.length) ? combinedLabels[top1] : 'unknown';
      print('  $name → $topLbl  top1=${(p1 * 100).toStringAsFixed(1)}%  margin=${(margin * 100).toStringAsFixed(1)}%');

      if (margin > bestMargin) {
        bestMargin = margin;
        bestNorm = norm;
        bestName = name;
      }
    }

    _lockedNorm = bestNorm;
    _preprocessLocked = true;
    print('🔒 Chosen preprocess: $bestName  (norm=$_lockedNorm)');
  }
}
