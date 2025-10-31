// lib/services/fish_model.dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures, unused_local_variable

import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FishModel {
  Interpreter? _interpreter;
  bool _initialized = false;
  Future<void>? _initializing;                // 🔒 prevent concurrent init
  bool get isReady => _initialized;

  // Labels (combined: fresh__/not_fresh__ + species)
  late List<String> combinedLabels;
  final _freshPrefix = 'fresh__';
  final _notFreshPrefix = 'not_fresh__';

  // Update these two paths for your current model + labels
  static const _modelPath =
      'assets/model/mobilenetv2_torchvision_Oct_25_3-08_pm_float32.tflite';
  static const _labelsPath = 'assets/model/classes_flat.json';

  // Public: ensure model is ready (safe to call many times)
  Future<void> ensureInited() async {
    if (_initialized) return;
    _initializing ??= _init();
    try {
      await _initializing;
    } finally {
      _initializing = null; // allow retry if it failed
    }
  }

  Future<void> _init() async {
    if (_initialized) return;

    // 1) Load & parse labels first (fail fast if missing)
    ByteData labelsBytes;
    try {
      labelsBytes = await rootBundle.load(_labelsPath);
    } catch (e) {
      throw StateError(
        'classes_flat.json not found. Make sure it is in pubspec.yaml.\nTried: $_labelsPath\nError: $e',
      );
    }

    final jsonStr = utf8.decode(labelsBytes.buffer.asUint8List());
    final parsed = json.decode(jsonStr);
    if (parsed is List) {
      combinedLabels = List<String>.from(parsed);
    } else if (parsed is Map<String, dynamic>) {
      final species = List<String>.from(parsed['species_classes'] ?? const []);
      final fresh = species.map((s) => '$_freshPrefix$s').toList();
      final notFresh = species.map((s) => '$_notFreshPrefix$s').toList();
      combinedLabels = [...fresh, ...notFresh];
    } else {
      throw StateError('Unsupported labels JSON format in $_labelsPath');
    }

    // 2) Verify model file exists in assets
    try {
      await rootBundle.load(_modelPath); // throws if missing
    } catch (e) {
      throw StateError(
        'TFLite model not found or not bundled.\nTried: $_modelPath\nError: $e',
      );
    }

    // 3) Create interpreter
    try {
      _interpreter = await Interpreter.fromAsset(_modelPath);
    } catch (e) {
      throw StateError('Failed to create TFLite interpreter from $_modelPath\nError: $e');
    }

    _initialized = true;
    print('✅ FishModel initialized — classes: ${combinedLabels.length}');
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // ======== PUBLIC API ========

  /// Run prediction for two images and fuse:
  /// - Freshness: both must be Fresh, else Not Fresh
  /// - Species: if disagree, keep higher-confidence one
  Future<Map<String, dynamic>> predictPair(String frontPath, String backPath) async {
    await ensureInited();

    final front = await predict(frontPath);
    final back  = await predict(backPath);

    final frontFresh = (front['predicted_freshness'] as String?) ?? 'Unknown';
    final backFresh  = (back['predicted_freshness'] as String?) ?? 'Unknown';
    final finalFreshness =
        (frontFresh == 'Fresh' && backFresh == 'Fresh') ? 'Fresh' : 'Not Fresh';

    final frontSpecies = (front['predicted_species'] as String?) ?? 'Unknown';
    final backSpecies  = (back['predicted_species'] as String?) ?? 'Unknown';
    final frontConf    = (front['confidence'] as double?) ?? 0.0;
    final backConf     = (back['confidence'] as double?) ?? 0.0;

    final finalSpecies = (frontSpecies == backSpecies)
        ? frontSpecies
        : (frontConf >= backConf ? frontSpecies : backSpecies);

    return {
      'predicted_freshness': finalFreshness,
      'predicted_species': finalSpecies,
      'front_result': front,
      'back_result': back,
    };
  }

  Future<Map<String, dynamic>> predict(String imagePath) async {
    await ensureInited();

    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Cannot decode image bytes');

      // === Preprocess (NHWC 224x224x3; normalize like training) ===
      const mean = [0.485, 0.456, 0.406];
      const std  = [0.229, 0.224, 0.225];

      final resized = img.copyResize(image, width: 224, height: 224);
      final input = Float32List(1 * 224 * 224 * 3);
      int i = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final p = resized.getPixel(x, y);
          final r = p.r / 255.0;
          final g = p.g / 255.0;
          final b = p.b / 255.0;
          input[i++] = (r - mean[0]) / std[0];
          input[i++] = (g - mean[1]) / std[1];
          input[i++] = (b - mean[2]) / std[2];
        }
      }

      // Most TF/TFLite models expect NHWC
      final inputBuffer = input.reshape([1, 224, 224, 3]);

      // Prepare output buffer based on tensor 0 shape
      final outShape = _interpreter!.getOutputTensor(0).shape;
      final flatLen = outShape.reduce((a, b) => a * b);
      final output = List.filled(flatLen, 0.0).reshape(outShape);

      _interpreter!.run(inputBuffer, output);

      // Flatten to 1D double list
      final logits = output.expand((x) => x is List ? x : [x]).cast<double>().toList();
      final probs  = _softmax(logits);

      if (probs.length != combinedLabels.length) {
        print('⚠️ Label mismatch: probs=${probs.length} labels=${combinedLabels.length}');
      }

      // Argmax
      int bestIdx = 0;
      double bestP = -1;
      for (int j = 0; j < probs.length; j++) {
        if (probs[j] > bestP) { bestP = probs[j]; bestIdx = j; }
      }

      final bestLabel = combinedLabels[bestIdx];
      final species   = _speciesFromCombined(bestLabel);
      final freshness = _freshnessFromCombined(bestLabel);

      print('✅ Pred: $freshness | $species | p=${bestP.toStringAsFixed(3)}');

      return {
        'predicted_freshness': freshness,
        'predicted_species': species,
        'confidence': bestP,
        // Optional: expose raw probs if you want
        // 'probs': probs,
      };
    } catch (e, st) {
      print('❌ Prediction error: $e\n$st');
      return {'predicted_freshness': 'Unknown', 'predicted_species': 'Unknown'};
    }
  }

  // ======== helpers ========

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  String _freshnessFromCombined(String combined) {
    if (combined.startsWith(_freshPrefix)) return 'Fresh';
    if (combined.startsWith(_notFreshPrefix)) return 'Not Fresh';
    return 'Unknown';
  }

  String _speciesFromCombined(String combined) {
    if (combined.startsWith(_freshPrefix)) return combined.substring(_freshPrefix.length);
    if (combined.startsWith(_notFreshPrefix)) return combined.substring(_notFreshPrefix.length);
    return combined;
  }
}
