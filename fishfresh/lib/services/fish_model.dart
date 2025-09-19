// lib/services/fish_model.dart
// ignore_for_file: avoid_print

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

  late List<String> freshnessLabels;
  late List<String> speciesLabels;

  Future<void> init() async {
    if (_initialized) return;

    // Load label JSON
    final jsonStr =
        await rootBundle.loadString('assets/model/multitask_labels.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    freshnessLabels = List<String>.from(data['freshness_classes']);
    speciesLabels = List<String>.from(data['species_classes']);

    // Load TFLite model
    _interpreter = await Interpreter.fromAsset(
      'assets/model/mobilenetv2_dli14_Sept_13_10-20_am_float16.tflite',
    );

    _initialized = true;
    print("✅ Model initialized.");
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  /// Softmax helper → converts logits to probabilities
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  Future<Map<String, dynamic>> predict(String imagePath) async {
    if (!_initialized) throw StateError('Call init() first');

    try {
      // Load + decode image
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('❌ Cannot decode image at $imagePath');

      // Resize to 224x224
      final resized = img.copyResize(image, width: 224, height: 224);

      // Convert to normalized Float32 [0–1]
      final input = Float32List(1 * 224 * 224 * 3);
      int idx = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);
          int r = pixel.r.toInt();
          int g = pixel.g.toInt();
          int b = pixel.b.toInt();

          input[idx++] = r / 255.0;
          input[idx++] = g / 255.0;
          input[idx++] = b / 255.0;
        }
      }

      // Reshape to [1,224,224,3]
      final inputBuffer = input.reshape([1, 224, 224, 3]);

      // Prepare output buffer
      var output = List.filled(
        _interpreter!.getOutputTensor(0).shape.reduce((a, b) => a * b),
        0.0,
      ).reshape(_interpreter!.getOutputTensor(0).shape);

      // Run inference
      _interpreter!.run(inputBuffer, output);

      // Flatten to List<double>
      final probs = output
          .expand((e) => e)
          .map((e) => (e as num).toDouble())
          .toList();

      // Split into freshness + species
      final freshLen = freshnessLabels.length;
      final fv = probs.sublist(0, freshLen);
      final sv = probs.sublist(freshLen);

      // Apply softmax
      final freshProbs = _softmax(fv);
      final speciesProbs = _softmax(sv);

      // Get best indexes
      final fi =
          freshProbs.indexOf(freshProbs.reduce((a, b) => a > b ? a : b));
      final si =
          speciesProbs.indexOf(speciesProbs.reduce((a, b) => a > b ? a : b));

      // Only return final labels
      final predictedFreshness = freshnessLabels[fi]; // "Fresh" or "Not Fresh"
      final predictedSpecies = speciesLabels[si]; // One of your 6 species

      print(
          "✅ Prediction done: Freshness=$predictedFreshness, Species=$predictedSpecies");

      return {
        "predicted_freshness": predictedFreshness,
        "predicted_species": predictedSpecies,
      };
    } catch (e, st) {
      print("❌ Prediction error: $e\n$st");
      return {
        "predicted_freshness": "Unknown",
        "predicted_species": "Unknown",
      };
    }
  }

  /// ✅ NEW: Predict using both front + back images
  Future<Map<String, dynamic>> predictPair(
      String frontPath, String backPath) async {
    final frontRes = await predict(frontPath);
    final backRes = await predict(backPath);

    // Freshness → stricter: both must be Fresh, else Not Fresh
    final frontFresh = frontRes["predicted_freshness"];
    final backFresh = backRes["predicted_freshness"];
    String finalFreshness;
    if (frontFresh == "Fresh" && backFresh == "Fresh") {
      finalFreshness = "Fresh";
    } else {
      finalFreshness = "Not Fresh";
    }

    // Species → if they agree, keep it, else fallback to front
    final frontSpecies = frontRes["predicted_species"];
    final backSpecies = backRes["predicted_species"];
    String finalSpecies;
    if (frontSpecies == backSpecies) {
      finalSpecies = frontSpecies;
    } else {
      finalSpecies = frontSpecies; // fallback rule
    }

    return {
      "predicted_freshness": finalFreshness,
      "predicted_species": finalSpecies,
      "front_result": frontRes,
      "back_result": backRes,
    };
  }
}
