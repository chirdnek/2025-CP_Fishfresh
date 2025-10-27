// lib/services/core/fish_model_core.dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures, unused_local_variable, unused_field, unused_element, prefer_final_fields

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Normalization profiles (RGB only in this app)
enum NormProfile { imagenet, zeroToOne, minusOneToOne }

/// Resize+crop styles
enum ResizeStyle {
  /// TorchVision eval: resize shorter-side ≈ 256 → center-crop SIDE (typically 224).
  torchvision,

  /// TF-EfficientNet: resize shorter-side ≈ 1.15×SIDE → center-crop SIDE (e.g., SIDE=260 → ~299→260).
  efficientnetLike,
}

/// Shared core for all your models (MobileNetV2, EfficientNet-Lite2, ResNet-50).
/// - Reads model input size from the TFLite interpreter (no hardcoding).
/// - Applies per-model normalization & resize style.
/// - Works with float32 / uint8 / int8 input-output tensors.
/// - Provides predict() and predictPair().
class FishModelCore {
  // ===== Config (constructor) =====
  final String modelAssetPath;
  final String labelsAssetPath;

  /// Optional: averages multiple normalization passes (float32 only)
  final bool useEnsemble;

  /// Debug top-K printout in console
  final bool debugTopK;
  final int debugTopKCount;

  /// Geometric preprocessing
  final ResizeStyle resizeStyle;

  /// Normalization profile for float32 models
  final NormProfile normProfile;

  // ---- Open-set / Unknown (OOD) gating thresholds ----
  // If any of these checks fail, we return Unknown.
  final double minTop1;         // required minimum top-1 probability
  final double minMargin;       // required (top1 - top2)
  final double maxEntropy;      // maximum allowed softmax entropy (nats)
  final double minFreshBlock;   // either Fresh or NotFresh block sum must exceed this

  FishModelCore({
    required this.modelAssetPath,
    required this.labelsAssetPath,
    this.useEnsemble = false,
    this.debugTopK = false,
    this.debugTopKCount = 12,
    required this.resizeStyle,
    this.normProfile = NormProfile.imagenet,

    // sensible defaults for 8-class (fresh/not_fresh × 4 species)
    this.minTop1 = 0.55,
    this.minMargin = 0.15,
    this.maxEntropy = 1.70,
    this.minFreshBlock = 0.60,
  }) {
    // lock the selected norm
    _lockedNorm = normProfile;
  }

  // ===== Runtime =====
  Interpreter? _interpreter;
  bool _initialized = false;

  // Labels (flat, with fresh__* first then not_fresh__*)
  late List<String> combinedLabels;
  final String _freshPrefix = 'fresh__';
  final String _notFreshPrefix = 'not_fresh__';

  // Preprocess (RGB-only)
  final bool _lockedUseRgb = true;
  late NormProfile _lockedNorm; // set from constructor
  bool _preprocessLocked = true;

  // Cached IO tensor meta
  late Tensor _inTensor, _outTensor;
  late TensorType _inType, _outType;

  // Determined from model
  late int _side;            // crop side (min(H,W))
  late double _resizeShort;  // target shorter-side before crop

  bool get isInitialized => _initialized;
  int get inputSide => _side;

  // ===== Initialization =====
  Future<void> init() async {
    if (_initialized) return;

    // Load labels (either flat list or species map flattened into fresh/not_fresh blocks)
    final raw = await rootBundle.loadString(labelsAssetPath);
    final parsed = json.decode(raw);
    if (parsed is List) {
      combinedLabels = List<String>.from(parsed);
    } else if (parsed is Map<String, dynamic>) {
      final species = List<String>.from(parsed['species_classes'] ?? const []);
      combinedLabels = [
        ...species.map((s) => 'fresh__$s'),
        ...species.map((s) => 'not_fresh__$s'),
      ];
    } else {
      throw Exception('Unsupported labels json format: $labelsAssetPath');
    }

    // Load TFLite
    _interpreter = await Interpreter.fromAsset(modelAssetPath);

    // IO meta
    _inTensor = _interpreter!.getInputTensor(0);
    _outTensor = _interpreter!.getOutputTensor(0);
    _inType = _inTensor.type;
    _outType = _outTensor.type;

    final inShape = _inTensor.shape; // [1,H,W,3]
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      throw Exception('Unexpected input shape $inShape (expect [1,H,W,3])');
    }
    final int h = inShape[1], w = inShape[2];
    _side = math.min(h, w);

    // Decide resize target shorter-side
    switch (resizeStyle) {
      case ResizeStyle.torchvision:
        // classic 256->224 style, scaled if SIDE != 224
        _resizeShort = 256.0 * (_side / 224.0);
        break;
      case ResizeStyle.efficientnetLike:
        _resizeShort = 1.15 * _side;
        break;
    }

    // Logs
    final outShape = _outTensor.shape;
    final units = outShape.isNotEmpty ? outShape.last : 0;
    print('📦 Loaded TFLite: $modelAssetPath');
    print('🧪 Input: $inShape ($_inType) | Output: $outShape ($_outType)');
    print('🧰 Preprocess: RGB + ${_lockedNorm.name} | resize(shorter=${_resizeShort.toStringAsFixed(1)}) → center-crop($_side)');
    print('🏷️  Labels: ${combinedLabels.length} | Units: $units');
    if (combinedLabels.length != units) {
      print('🚨 Label count != output units. Fix classes_flat.json to match the head order from training/export.');
    }

    _initialized = true;
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // ===== Geometry: resize(shorter=_resizeShort) → center-crop(_side) =====
  img.Image _resizeShortSideThenCenterCrop(img.Image im) {
    final int w = im.width, h = im.height;
    final int targetShort = math.max(1, _resizeShort.round());

    final double shortSide = math.min(w, h).toDouble();
    final double scale = targetShort / shortSide;
    final int newW = math.max(1, (w * scale).round());
    final int newH = math.max(1, (h * scale).round());

    final img.Image resized = img.copyResize(im, width: newW, height: newH);

    final int x0 = math.max(0, (resized.width - _side) ~/ 2);
    final int y0 = math.max(0, (resized.height - _side) ~/ 2);
    final int cropW = math.min(_side, resized.width);
    final int cropH = math.min(_side, resized.height);

    final img.Image cropped = img.copyCrop(resized, x: x0, y: y0, width: cropW, height: cropH);

    if (cropped.width != _side || cropped.height != _side) {
      return img.copyResize(cropped, width: _side, height: _side);
    }
    return cropped;
  }

  // ===== Nested list builders (NHWC) =====
  List _as4DFloat(Float32List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0.0))));
    int i = 0;
    for (var ni = 0; ni < n; ni++) {
      for (var yi = 0; yi < h; yi++) {
        for (var xi = 0; xi < w; xi++) {
          for (var ci = 0; ci < c; ci++) out[ni][yi][xi][ci] = flat[i++];
        }
      }
    }
    return out;
  }

  List _as4DUint8(Uint8List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0))));
    int i = 0;
    for (var ni = 0; ni < n; ni++) {
      for (var yi = 0; yi < h; yi++) {
        for (var xi = 0; xi < w; xi++) {
          for (var ci = 0; ci < c; ci++) out[ni][yi][xi][ci] = flat[i++];
        }
      }
    }
    return out;
  }

  List _as4DInt8(Int8List flat, int n, int h, int w, int c) {
    final out = List.generate(n, (_) => List.generate(h, (_) => List.generate(w, (_) => List.filled(c, 0))));
    int i = 0;
    for (var ni = 0; ni < n; ni++) {
      for (var yi = 0; yi < h; yi++) {
        for (var xi = 0; xi < w; xi++) {
          for (var ci = 0; ci < c; ci++) out[ni][yi][xi][ci] = flat[i++];
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
          case TensorType.int32: return 0;
          default: return 0;
        }
      }
      final len = dims.first;
      final tail = dims.sublist(1);
      return List.generate(len, (_) => build(tail));
    }
    return build(shape);
  }

  // ===== Build input tensor (NHWC) with proper normalization =====
  Object _buildInputNHWC(img.Image resized) {
    final int n = 1, h = _side, w = _side, c = 3;

    if (_inType == TensorType.uint8) {
      final flat = Uint8List(h * w * c);
      int i = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          flat[i++] = p.r.toInt();
          flat[i++] = p.g.toInt();
          flat[i++] = p.b.toInt();
        }
      }
      return _as4DUint8(flat, n, h, w, c);
    }

    if (_inType == TensorType.int8) {
      final qp = _inTensor.params; // scale & zeroPoint
      final double scale = qp.scale;
      final int zeroPoint = qp.zeroPoint;

      final flat = Int8List(h * w * c);
      int i = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          final r = (((p.r / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
          final g = (((p.g / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
          final b = (((p.b / scale).round() + zeroPoint).clamp(-128, 127)).toInt();
          flat[i++] = r; flat[i++] = g; flat[i++] = b;
        }
      }
      return _as4DInt8(flat, n, h, w, c);
    }

    // float32 path with normalization
    const meanIM = [0.485, 0.456, 0.406];
    const stdIM  = [0.229, 0.224, 0.225];

    final flat = Float32List(h * w * c);
    int i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = resized.getPixel(x, y);
        double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

        switch (_lockedNorm) {
          case NormProfile.imagenet:
            r = (r - meanIM[0]) / stdIM[0];
            g = (g - meanIM[1]) / stdIM[1];
            b = (b - meanIM[2]) / stdIM[2];
            break;
          case NormProfile.minusOneToOne:
            r = r * 2.0 - 1.0;
            g = g * 2.0 - 1.0;
            b = b * 2.0 - 1.0;
            break;
          case NormProfile.zeroToOne:
            // keep 0..1
            break;
        }

        flat[i++] = r; flat[i++] = g; flat[i++] = b;
      }
    }
    return _as4DFloat(flat, n, h, w, c);
  }

  // ===== Output helpers =====
  Object _buildOutputBuffer() => _zerosLikeShape(_outTensor.shape, _outType);

  List<double> _flattenToDoubleList(dynamic obj) {
    final out = <double>[];
    void walk(dynamic x) {
      if (x is List) for (final e in x) walk(e);
      else if (x is num) out.add(x.toDouble());
    }
    walk(obj);
    return out;
  }

  List<double> _extractLogits(Object buf) {
    if (_outType == TensorType.float32) return _flattenToDoubleList(buf);
    // quantized output
    try {
      final qp = _outTensor.params;
      final double scale = qp.scale;
      final int zeroPoint = qp.zeroPoint;
      final raw = <int>[];
      void walk(dynamic x) {
        if (x is List) for (final e in x) walk(e);
        else if (x is num) raw.add(x.toInt());
      }
      walk(buf);
      return raw.map((v) => scale * (v - zeroPoint)).toList();
    } catch (_) {
      return _flattenToDoubleList(buf);
    }
  }

  List<double> _softmax(List<double> logits) {
    final m = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - m)).toList();
    final s = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / s).toList();
  }

  void _logTopK(List<double> probs, {int k = 5}) {
    final pairs = <MapEntry<int, double>>[];
    for (var i = 0; i < probs.length; i++) pairs.add(MapEntry(i, probs[i]));
    pairs.sort((a, b) => b.value.compareTo(a.value));
    for (final e in pairs.take(k)) {
      final label = e.key < combinedLabels.length ? combinedLabels[e.key] : '??';
      print('   #${e.key}  ${label.padRight(30)}  ${(e.value * 100).toStringAsFixed(2)}%');
    }
  }

  // ===== Optional ensemble (float32 only; averages across norms) =====
  List<double> _probsForNorm(img.Image pre, {required NormProfile norm}) {
    final saved = _lockedNorm;
    _lockedNorm = norm;
    final input = _buildInputNHWC(pre);
    final out = _buildOutputBuffer();
    _interpreter!.run(input, out);
    final probs = _softmax(_extractLogits(out));
    _lockedNorm = saved;
    return probs;
  }

  List<double> _probsFromEnsemble(img.Image pre) {
    final variants = <NormProfile>[
      normProfile, // primary
      if (normProfile != NormProfile.imagenet) NormProfile.imagenet,
      if (normProfile != NormProfile.minusOneToOne) NormProfile.minusOneToOne,
      if (normProfile != NormProfile.zeroToOne) NormProfile.zeroToOne,
    ];
    List<double>? acc;
    for (final v in variants) {
      final p = _probsForNorm(pre, norm: v);
      if (acc == null) acc = List<double>.from(p);
      else for (int i = 0; i < acc.length; i++) acc[i] += p[i];
    }
    for (int i = 0; i < acc!.length; i++) acc[i] /= variants.length;
    return acc;
  }

  // ===== OOD helpers =====
  double _entropy(List<double> p) {
    const double eps = 1e-12;
    double h = 0.0;
    for (final x in p) {
      final v = x.clamp(0.0, 1.0);
      h += v <= eps ? 0.0 : -v * math.log(v);
    }
    return h; // nats
  }

  bool _isUnknown({
    required List<double> probs,
    required double top1,
    required double top2,
    required double freshSum,
    required double notFreshSum,
  }) {
    final ent = _entropy(probs);
    final margin = top1 - top2;
    final blockOK = (freshSum >= minFreshBlock) || (notFreshSum >= minFreshBlock);

    if (top1 < minTop1) return true;
    if (margin < minMargin) return true;
    if (ent > maxEntropy) return true;
    if (!blockOK) return true;

    return false;
  }

  // ===== Public: predict single image =====
  Future<Map<String, dynamic>> predict(String imagePath) async {
    if (!_initialized) throw StateError('Call init() first');

    try {
      // load & preprocess
      final bytes = await File(imagePath).readAsBytes();
      final decoded0 = img.decodeImage(bytes);
      if (decoded0 == null) throw Exception('Cannot decode image: $imagePath');
      final decoded = img.bakeOrientation(decoded0);
      final pre = _resizeShortSideThenCenterCrop(decoded);

      // run
      List<double> probs;
      if (_inType == TensorType.float32 && useEnsemble) {
        probs = _probsFromEnsemble(pre);
      } else {
        final input = _buildInputNHWC(pre);
        final output = _buildOutputBuffer();
        _interpreter!.run(input, output);
        probs = _softmax(_extractLogits(output));
      }

      if (probs.length != combinedLabels.length) {
        print('⚠️ probs=${probs.length} vs labels=${combinedLabels.length}');
      }
      if (debugTopK) {
        print('🔎 Top-$debugTopKCount');
        _logTopK(probs, k: debugTopKCount);
      }

      // --- find top-1 and top-2 ---
      final pairs = <MapEntry<int, double>>[];
      for (int i = 0; i < probs.length; i++) pairs.add(MapEntry(i, probs[i]));
      pairs.sort((a, b) => b.value.compareTo(a.value));
      final best = pairs[0];
      final second = pairs.length > 1 ? pairs[1] : MapEntry(-1, 0.0);

      final bestIdx = best.key;
      final top1 = best.value;
      final top2 = second.value;
      final bestLabel = bestIdx < combinedLabels.length ? combinedLabels[bestIdx] : 'unknown';

      // diagnostic block sums (and for OOD gate)
      final half = combinedLabels.length ~/ 2;
      final freshSum = probs.take(half).fold<double>(0.0, (a, b) => a + b);
      final notFreshSum = probs.skip(half).fold<double>(0.0, (a, b) => a + b);
      print('Fresh block sum: ${freshSum.toStringAsFixed(3)} | NotFresh block sum: ${notFreshSum.toStringAsFixed(3)}');

      // === Unknown decision ===
      final unknown = _isUnknown(
        probs: probs,
        top1: top1,
        top2: top2,
        freshSum: freshSum,
        notFreshSum: notFreshSum,
      );

      // build breakdowns for UI (kept even if Unknown so charts can show distribution)
      final speciesScores = <String, double>{};
      final freshnessPair = <String, Map<String, double>>{};
      double freshSumUI = 0, notFreshSumUI = 0;

      for (int i = 0; i < probs.length; i++) {
        final label = (i < combinedLabels.length) ? combinedLabels[i] : 'unknown';
        final p = probs[i];
        final sp = _speciesFromCombined(label);

        speciesScores.update(sp, (v) => v + p, ifAbsent: () => p);

        final isFresh = label.startsWith(_freshPrefix);
        final key = isFresh ? 'Fresh' : 'Not Fresh';
        final mp = (freshnessPair[sp] ??= {'Fresh': 0.0, 'Not Fresh': 0.0});
        mp[key] = (mp[key] ?? 0.0) + p;

        if (isFresh) freshSumUI += p; else notFreshSumUI += p;
      }

      final speciesScoresSorted = Map<String, double>.fromEntries(
        speciesScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      final topk = pairs.take(5).map((e) => {
        'index': e.key,
        'label': e.key < combinedLabels.length ? combinedLabels[e.key] : 'unknown',
        'prob': e.value,
      }).toList();

      final String predSpecies = unknown ? 'Unknown' : _speciesFromCombined(bestLabel);
      final String predFreshness = unknown ? 'Unknown' : _freshnessFromCombined(bestLabel);

      return {
        'predicted_freshness': predFreshness,
        'predicted_species': predSpecies,
        'confidence': top1,
        'freshness_scores': {'Fresh': freshSumUI, 'Not Fresh': notFreshSumUI},
        'species_scores': speciesScoresSorted,
        'topk': topk,
        'best_index': bestIdx,
        'best_label': unknown ? 'unknown' : bestLabel,
        'unknown': unknown,
      };
    } catch (e, st) {
      print('❌ Prediction error: $e\n$st');
      return {'predicted_freshness': 'Unknown', 'predicted_species': 'Unknown', 'unknown': true};
    }
  }

  // ===== Public: predict with front/back voting =====
  Future<Map<String, dynamic>> predictPair(String frontPath, String backPath) async {
    final a = await predict(frontPath);
    final b = await predict(backPath);

    final aUnknown = (a['unknown'] as bool?) ?? false;
    final bUnknown = (b['unknown'] as bool?) ?? false;

    String finalFreshness, finalSpecies;

    if (aUnknown && bUnknown) {
      finalFreshness = 'Unknown';
      finalSpecies = 'Unknown';
    } else if (aUnknown) {
      finalFreshness = (b['predicted_freshness'] as String?) ?? 'Unknown';
      finalSpecies = (b['predicted_species'] as String?) ?? 'Unknown';
    } else if (bUnknown) {
      finalFreshness = (a['predicted_freshness'] as String?) ?? 'Unknown';
      finalSpecies = (a['predicted_species'] as String?) ?? 'Unknown';
    } else {
      // conservative freshness: only Fresh if both Fresh
      final fA = (a['predicted_freshness'] as String?) ?? 'Unknown';
      final fB = (b['predicted_freshness'] as String?) ?? 'Unknown';
      finalFreshness = (fA == 'Fresh' && fB == 'Fresh') ? 'Fresh' : 'Not Fresh';

      // species: agree else pick higher-confidence
      final sA = (a['predicted_species'] as String?) ?? 'Unknown';
      final sB = (b['predicted_species'] as String?) ?? 'Unknown';
      final cA = (a['confidence'] as double?) ?? 0.0;
      final cB = (b['confidence'] as double?) ?? 0.0;
      finalSpecies = (sA == sB) ? sA : (cA >= cB ? sA : sB);
    }

    return {
      'predicted_freshness': finalFreshness,
      'predicted_species': finalSpecies,
      'front_result': a,
      'back_result': b,
    };
  }

  // ===== helpers =====
  String _freshnessFromCombined(String lbl) {
    if (lbl.startsWith(_freshPrefix)) return 'Fresh';
    if (lbl.startsWith(_notFreshPrefix)) return 'Not Fresh';
    return 'Unknown';
  }

  String _speciesFromCombined(String lbl) {
    if (lbl.startsWith(_freshPrefix)) return lbl.substring(_freshPrefix.length);
    if (lbl.startsWith(_notFreshPrefix)) return lbl.substring(_notFreshPrefix.length);
    return lbl;
  }
}
