// lib/services/fish_model.dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures, unused_local_variable, unintended_html_in_doc_comment

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

  late List<String> combinedLabels;
  final _freshPrefix = 'fresh__';
  final _notFreshPrefix = 'not_fresh__';

  Future<void> ensureInited() async {
    await init(); // init() already checks _initialized
  }

  Future<void> init() async {
    if (_initialized) return;

    // Load combined class labels
    final jsonStr = await rootBundle.loadString('assets/model/classes_flat.json');
    final parsed = json.decode(jsonStr);
    if (parsed is List) {
      combinedLabels = List<String>.from(parsed);
    } else if (parsed is Map<String, dynamic>) {
      final freshness = List<String>.from(parsed['freshness_classes'] ?? const []);
      final species = List<String>.from(parsed['species_classes'] ?? const []);
      final fresh = species.map((s) => 'fresh__${s}').toList();
      final notFresh = species.map((s) => 'not_fresh__${s}').toList();
      combinedLabels = [...fresh, ...notFresh];
    } else {
      throw Exception('Unsupported classes.json format.');
    }

    // Load model
    _interpreter = await Interpreter.fromAsset(
      // NOTE: this must match your pubspec asset key
      'assets/model/mobilenetv2_torchvision_Nov_25_2-27_am_float32.tflite',
    );

    _initialized = true;
    print("✅ Model initialized (${combinedLabels.length} classes)");
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // ===================== NEW: single-image API (for camera + YOLO pipeline) =====================

  /// One-image prediction — this is what the camera (YOLO pipeline) should call.
  /// Returns:
  /// {
  ///   'predicted_freshness': 'Fresh' | 'Not Fresh' | 'Unknown',
  ///   'predicted_species'  : '<species name>' | 'Unknown',
  ///   'confidence'         : double 0..1
  /// }
  Future<Map<String, dynamic>> predictSingle(String imagePath) async {
    if (!_initialized) {
      throw StateError('Call init()/ensureInited() first');
    }
    return predict(imagePath);
  }

  // ===================== (Optional) legacy pair API – no longer used by camera =====================

  /// OLD: Predict using both front + back images.
  /// You can keep this for other features (e.g., gallery), but the camera
  /// now uses `predictSingle` only.
  Future<Map<String, dynamic>> predictPair(String frontPath, String backPath) async {
    if (!_initialized) {
      throw StateError('Call init() first');
    }

    final front = await predict(frontPath);
    final back  = await predict(backPath);

    // Freshness consensus: both must be Fresh
    final frontFresh = (front["predicted_freshness"] as String?) ?? "Unknown";
    final backFresh  = (back["predicted_freshness"] as String?) ?? "Unknown";
    final finalFreshness =
        (frontFresh == "Fresh" && backFresh == "Fresh") ? "Fresh" : "Not Fresh";

    // Species agreement or pick higher confidence
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

  // ===================== helpers =====================

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

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  /// Low-level single-image prediction core
  Future<Map<String, dynamic>> predict(String imagePath) async {
    if (!_initialized) throw StateError('Call init() first');

    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Cannot decode image');

      // --- Normalize like training (ImageNet-style) ---
      const mean = [0.485, 0.456, 0.406];
      const std = [0.229, 0.224, 0.225];

      final resized = img.copyResize(image, width: 224, height: 224);
      final input = Float32List(1 * 224 * 224 * 3);
      int i = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final p = resized.getPixel(x, y);
          // image package Pixel → r/g/b properties
          final r = p.r / 255.0;
          final g = p.g / 255.0;
          final b = p.b / 255.0;
          input[i++] = (r - mean[0]) / std[0];
          input[i++] = (g - mean[1]) / std[1];
          input[i++] = (b - mean[2]) / std[2];
        }
      }

      // TFLite expects NHWC: [1, 224, 224, 3]
      final inputBuffer = input.reshape([1, 224, 224, 3]);

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final outputFlat = List<double>.filled(
        outputShape.reduce((a, b) => a * b),
        0.0,
      );
      final output = outputFlat.reshape(outputShape);
      
   try {
        _interpreter!.run(inputBuffer, output);
      } catch (e, st) {
        print('❌ FishModel TFLite run() error: $e\n$st');
        rethrow; // let _runDetectorAndModel catch it as "Classifier error"
      }
      _interpreter!.run(inputBuffer, output);

      // Flatten logits
      final logits = output
          .expand((x) => x is List ? x : [x])
          .cast<double>()
          .toList();

      final probs = _softmax(logits);

      if (probs.length != combinedLabels.length) {
        print('⚠️ Mismatch: ${probs.length} != ${combinedLabels.length}');
      }

      int bestIdx = 0;
      double bestP = -1;
      for (int j = 0; j < probs.length; j++) {
        if (probs[j] > bestP) {
          bestP = probs[j];
          bestIdx = j;
        }
      }

      final bestLabel = combinedLabels[bestIdx];
      final species = _speciesFromCombined(bestLabel);
      final freshness = _freshnessFromCombined(bestLabel);

      print('✅ Prediction → $freshness | $species | p=${bestP.toStringAsFixed(3)}');

      return {
        'predicted_freshness': freshness,
        'predicted_species': species,
        'confidence': bestP,
      };
    } catch (e, st) {
      print('❌ Prediction error: $e\n$st');
      return {
        'predicted_freshness': 'Unknown',
        'predicted_species': 'Unknown',
        'confidence': 0.0,
      };
    }
  }
}
