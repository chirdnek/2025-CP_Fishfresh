// lib/services/fish_model_efficient.dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures, unused_local_variable, unused_field, unused_element, unintended_html_in_doc_comment

import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Normalization presets
enum NormProfile { imagenet, zeroToOne, minusOneToOne }

/// EfficientNet-Lite2 (TFLite) — matches timm cfg:
/// • Input: 3×260×260
/// • Mean: (0.5, 0.5, 0.5), Std: (0.5, 0.5, 0.5)  →  [-1, +1] range
class FishModelEfficientLite2 {
  Interpreter? _interpreter;
  bool _initialized = false;

  // Expose for runtime 'ready' checks
  bool get isInitialized => _initialized;

  // === Labels ===
  late List<String> combinedLabels;
  late List<String> _originalLoadedLabels;
  final String _freshPrefix = 'fresh__';
  final String _notFreshPrefix = 'not_fresh__';

  // === Config (default assets) — adjust to your pubspec assets ===
  String modelAssetPath;
  String labelsAssetPath;

  // allow runtime to inject paths (compat with your FishRuntime._maybeConfigurePaths)
  void setModelPath(String p) { modelAssetPath = p; }
  void setLabelsPath(String p) { labelsAssetPath = p; }
  void setPaths(String modelPath, String labelsPath) {
    modelAssetPath = modelPath; labelsAssetPath = labelsPath;
  }
  void configure({String? modelPath, String? labelsPath}) {
    if (modelPath != null) modelAssetPath = modelPath;
    if (labelsPath != null) labelsAssetPath = labelsPath;
  }

  // Ensemble (RGB-only, optional)
  final bool _useEnsemble;

  // Expected input side
  final int expectSide = 260;

  // Debug
  final bool debugTopK;
  final int debugTopKCount;

  // ---- Preprocess selection ----
  bool _preprocessLocked = true;                 // keep locked
  final bool _lockedUseRgb = true;               // RGB only
  NormProfile _lockedNorm = NormProfile.minusOneToOne; // ✅ match timm: mean=.5 std=.5 → [-1,1]

  // Cached IO tensor meta
  late Tensor _inTensor;
  late Tensor _outTensor;
  late int _h;
  late int _w;
  late TensorType _inType;
  late TensorType _outType;

  FishModelEfficientLite2({
    this.modelAssetPath  = 'assets/model/efficientnetv2_Oct_19_4-18_am_float32.tflite', // ✅ name matches ModelRegistry suggestion
    this.labelsAssetPath = 'assets/model/classes_flat.json',
    bool useEnsemble = false,
    this.debugTopK = false,
    this.debugTopKCount = 12,
  }) : _useEnsemble = useEnsemble;

  // ===== Utilities =====
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
          case TensorType.float32: return 0.0;
          case TensorType.uint8:
          case TensorType.int8:
          case TensorType.int32:   return 0;
          default:                 return 0;
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
      if (x is List) for (final e in x) walk(e);
      else if (x is num) out.add(x.toDouble());
    }
    walk(obj);
    return out;
  }

  // ===== Initialization =====
  Future<void> init() async {
    if (_initialized) return;

    // --- Load labels (allow flat array or species map) ---
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

    // --- Load interpreter ---
    _interpreter = await Interpreter.fromAsset(modelAssetPath);

    // --- Cache IO meta ---
    _inTensor = _interpreter!.getInputTensor(0);
    _outTensor = _interpreter!.getOutputTensor(0);
    _inType = _inTensor.type;
    _outType = _outTensor.type;

    final inShape = _inTensor.shape; // expect [1,H,W,3]
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      throw Exception('Unexpected input shape $inShape. Expected [1,H,W,3].');
    }
    _h = inShape[1];
    _w = inShape[2];

    if (!(_h == expectSide && _w == expectSide)) {
      print('⚠️ Model input is ${_w}x${_h}, expected $expectSide×$expectSide (tf_efficientnet_lite2).');
    }

    final outShape = _outTensor.shape;
    final numUnits = outShape.isNotEmpty ? outShape.last : 0;

    print('📦 Loaded TFLite: $modelAssetPath');
    print('   • Input: $_inType $inShape  (expects 260×260, RGB)');
    print('   • Output: $_outType ${_outTensor.shape}');
    print('   • Labels: ${combinedLabels.length} | Out units: $numUnits');
    if (combinedLabels.length != numUnits) {
      print('🚨 Label count and output units differ — check classes_flat.json order/length.');
    }
    print('   • Preprocess: RGB, [-1, +1] (mean=.5 std=.5)');

    _initialized = true;
    print('✅ Model initialized');
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // --- Label helpers ---
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
    for (int i = 0; i < probs.length; i++) pairs.add(MapEntry(i, probs[i]));
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

  // --- Resize(shorterSide≈1.15*side) → CenterCrop(side) ---
  img.Image _resizeShortSideThenCenterCrop(img.Image im, int side, {double scale = 1.15}) {
    final w = im.width, h = im.height;
    final targetShort = (side * scale).round();

    final shortSide = math.min(w, h).toDouble();
    final scaleFactor = targetShort / shortSide;
    final newW = math.max(1, (w * scaleFactor).round());
    final newH = math.max(1, (h * scaleFactor).round());

    final resized = img.copyResize(im, width: newW, height: newH);

    final x0 = math.max(0, (resized.width - side) ~/ 2);
    final y0 = math.max(0, (resized.height - side) ~/ 2);
    final cropW = math.min(side, resized.width);
    final cropH = math.min(side, resized.height);
    final cropped = img.copyCrop(resized, x: x0, y: y0, width: cropW, height: cropH);

    if (cropped.width != side || cropped.height != side) {
      return img.copyResize(cropped, width: side, height: side);
    }
    return cropped;
  }

  // ===== RGB input builders =====
  Object _buildInputNHWC(img.Image resized) {
    final n = 1, h = expectSide, w = expectSide, c = 3;

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
      final params = _inTensor.params;
      final double scale = params.scale;
      final int zeroPoint = params.zeroPoint;

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

      // ImageNet stats kept here for completeness, but lite2 uses [-1,1]
      const meanIM = [0.485, 0.456, 0.406];
      const stdIM  = [0.229, 0.224, 0.225];

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

          if (_lockedNorm == NormProfile.imagenet) {
            r = (r - meanIM[0]) / stdIM[0];
            g = (g - meanIM[1]) / stdIM[1];
            b = (b - meanIM[2]) / stdIM[2];
          } else if (_lockedNorm == NormProfile.zeroToOne) {
            // 0..1
          } else if (_lockedNorm == NormProfile.minusOneToOne) {
            // ✅ lite2 default
            r = r * 2.0 - 1.0;
            g = g * 2.0 - 1.0;
            b = b * 2.0 - 1.0;
          }

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
    try {
      final qp = _outTensor.params;
      final double scale = qp.scale;
      final int zeroPoint = qp.zeroPoint;

      final rawNums = <int>[];
      void walk(dynamic x) {
        if (x is List) for (final e in x) walk(e);
        else if (x is num) rawNums.add(x.toInt());
      }
      walk(outputBuffer);

      return rawNums.map((v) => scale * (v - zeroPoint)).toList();
    } catch (_) {
      return _flattenToDoubleList(outputBuffer);
    }
  }

  // Optional ensemble (RGB-only)
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

  List<double> _probsFromEnsemble(img.Image pre) {
    final variants = <NormProfile>[
      NormProfile.minusOneToOne, // ✅ primary
      NormProfile.zeroToOne,
      NormProfile.imagenet,
    ];
    List<double>? sum;
    for (final v in variants) {
      final probs = _probsForNorm(pre, norm: v);
      if (sum == null) sum = List<double>.from(probs);
      else for (int i = 0; i < sum.length; i++) sum[i] += probs[i];
    }
    for (int i = 0; i < sum!.length; i++) sum[i] /= variants.length;
    return sum;
  }

  // ======= Public prediction APIs =======
  Future<Map<String, dynamic>> predict(String imagePath) async {
    if (!_initialized) throw StateError('Call init() first');

    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded0 = img.decodeImage(bytes);
      if (decoded0 == null) throw Exception('Cannot decode image: $imagePath');
      final decoded = img.bakeOrientation(decoded0);
      final preprocessed = _resizeShortSideThenCenterCrop(decoded, expectSide);

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

      int bestIdx = 0; double bestP = -1;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > bestP) { bestP = probs[i]; bestIdx = i; }
      }
      final bestLabel = (bestIdx < combinedLabels.length) ? combinedLabels[bestIdx] : 'unknown';

      final species = _speciesFromCombined(bestLabel);
      final freshness = _freshnessFromCombined(bestLabel);

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

      return {
        'predicted_freshness': freshness,
        'predicted_species': species,
        'confidence': probs[bestIdx],
        'freshness_scores': {'Fresh': freshSum, 'Not Fresh': notFreshSum},
        'species_scores': speciesScoresSorted,
        'topk': _topK(probs, 5),
        'best_index': bestIdx,
        'best_label': bestLabel,
      };
    } catch (e, st) {
      print('❌ Prediction error: $e\n$st');
      return {'predicted_freshness': 'Unknown', 'predicted_species': 'Unknown'};
    }
  }

  Future<Map<String, dynamic>> predictPair(String frontPath, String backPath) async {
    if (!_initialized) throw StateError('Call init() first');
    final front = await predict(frontPath);
    final back  = await predict(backPath);

    final frontFresh = (front["predicted_freshness"] as String?) ?? "Unknown";
    final backFresh  = (back["predicted_freshness"] as String?) ?? "Unknown";
    final finalFreshness = (frontFresh == "Fresh" && backFresh == "Fresh") ? "Fresh" : "Not Fresh";

    final frontSpecies = (front["predicted_species"] as String?) ?? "Unknown";
    final backSpecies  = (back["predicted_species"] as String?) ?? "Unknown";
    final frontConf    = (front["confidence"] as double?) ?? 0.0;
    final backConf     = (back["confidence"] as double?) ?? 0.0;

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

  List<Map<String, dynamic>> _topK(List<double> probs, int k) {
    final pairs = <MapEntry<int, double>>[];
    for (int i = 0; i < probs.length; i++) pairs.add(MapEntry(i, probs[i]));
    pairs.sort((a, b) => b.value.compareTo(a.value));
    return pairs.take(k).map((e) {
      final lbl = (e.key < combinedLabels.length) ? combinedLabels[e.key] : 'unknown';
      return {'index': e.key, 'label': lbl, 'prob': e.value};
    }).toList();
  }

  // Optional: auto-preprocess (kept but disabled by default)
  void _autoSelectPreprocess(img.Image pre) {
    if (_preprocessLocked || _inType != TensorType.float32) return;

    final trials = <Map<String, dynamic>>[
      {'name': 'RGB_MinusOneToOne', 'norm': NormProfile.minusOneToOne}, // ✅ primary
      {'name': 'RGB_ZeroToOne',     'norm': NormProfile.zeroToOne},
      {'name': 'RGB_ImageNet',      'norm': NormProfile.imagenet},
    ];

    double bestMargin = -1;
    NormProfile bestNorm = _lockedNorm;
    String bestName = '';

    print('🔬 Auto-selecting preprocess (RGB-only):');
    for (final t in trials) {
      final norm = t['norm'] as NormProfile;
      final name = t['name'] as String;

      final probs = _probsForNorm(pre, norm: norm);

      int top1 = 0, top2 = 0;
      double p1 = -1, p2 = -1;
      for (int k = 0; k < probs.length; k++) {
        final v = probs[k];
        if (v > p1) { p2 = p1; top2 = top1; p1 = v; top1 = k; }
        else if (v > p2) { p2 = v; top2 = k; }
      }
      final margin = p1 - p2;

      final topLbl = (top1 < combinedLabels.length) ? combinedLabels[top1] : 'unknown';
      print('  $name → $topLbl  top1=${(p1 * 100).toStringAsFixed(1)}%  margin=${(margin * 100).toStringAsFixed(1)}%');

      if (margin > bestMargin) { bestMargin = margin; bestNorm = norm; bestName = name; }
    }

    _lockedNorm = bestNorm;
    _preprocessLocked = true;
    print('🔒 Chosen preprocess: $bestName  (norm=$_lockedNorm)');
  }
}
