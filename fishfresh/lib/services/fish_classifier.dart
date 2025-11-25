// lib/services/fish_classifier.dart
// Simple TFLite classifier wrapper for species + freshness.

// ignore_for_file: unused_import

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FishClassLabel {
  final int index;
  final String label;     // e.g. "Bangus - Fresh"
  final String species;   // e.g. "Bangus"
  final String freshness; // e.g. "Fresh"

  FishClassLabel({
    required this.index,
    required this.label,
    required this.species,
    required this.freshness,
  });
}

class FishClassification {
  final FishClassLabel label;
  final double confidence;

  FishClassification({
    required this.label,
    required this.confidence,
  });
}

class FishClassifier {
  FishClassifier._private();
  static final instance = FishClassifier._private();

  static const _tfliteAsset =
      'assets/model/mobilenetv2_torchvision_Nov_25_2-27_am_float32.tflite';
  static const _labelsAsset = 'assets/model/classes_flat.json';
  static const _inputSize = 224;

  Interpreter? _interpreter;
  bool _isInited = false;
  late List<FishClassLabel> _labels;

  Future<void> ensureInited() async {
    if (_isInited) return;

    // 1) Load labels
    _labels = await _loadLabels(_labelsAsset);

    // 2) Load classifier interpreter
    _interpreter = await Interpreter.fromAsset(
      _tfliteAsset,
      options: InterpreterOptions()..threads = 2,
    );

    _isInited = true;
  }

  /// Main entry: classify a cropped fish image.
  /// `crop` should already be a tight crop around one fish.
  Future<FishClassification> classify(img.Image crop) async {
    if (!_isInited) await ensureInited();

    // Resize to model input size
    final resized = img.copyResize(
      crop,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.nearest,
    );

    // Convert to normalized float32 tensor [1, H, W, 3]
    final inputTensor = [_imageToFloat32(resized)];

    // Prepare output buffer [1, numClasses]
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final numClasses = outputShape.last;
    final output =
        List.generate(1, (_) => List<double>.filled(numClasses, 0.0));

    _interpreter!.run(inputTensor, output);

    // Softmax & argmax on output[0]
    final probs = _softmax(output[0]);
    int bestIdx = 0;
    double bestScore = probs[0];
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > bestScore) {
        bestScore = probs[i];
        bestIdx = i;
      }
    }

    final label = _labels[bestIdx];
    return FishClassification(
      label: label,
      confidence: bestScore,
    );
  }

  // --- Helpers ---

  /// Convert image to [H][W][3] float32, values in [0,1].
  List<List<List<double>>> _imageToFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;

    return List.generate(
      h,
      (y) => List.generate(
        w,
        (x) {
          final p = image.getPixel(x, y);
          return [
            p.r / 255.0,
            p.g / 255.0,
            p.b / 255.0,
          ];
        },
      ),
    );
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps =
        logits.map((v) => math.exp(v - maxLogit)).toList(); // stabilize
    final sumExp = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sumExp).toList();
  }

  Future<List<FishClassLabel>> _loadLabels(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = json.decode(raw);

    final List<FishClassLabel> labels = [];

    // -------- CASE 1: Map<String, dynamic> --------
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final idx = int.parse(entry.key);
        String label;
        String species;
        String freshness;

        if (entry.value is String) {
          label = entry.value as String;
          final parts = label.split('-').map((e) => e.trim()).toList();
          if (parts.length >= 2) {
            species = parts[0];
            freshness = parts.sublist(1).join('-').trim();
          } else {
            species = label;
            freshness = '';
          }
        } else if (entry.value is Map<String, dynamic>) {
          final v = entry.value as Map<String, dynamic>;
          label = (v['label'] ?? '').toString();
          species = (v['species'] ?? '').toString();
          freshness = (v['freshness'] ?? '').toString();
        } else {
          label = entry.value.toString();
          species = label;
          freshness = '';
        }

        labels.add(FishClassLabel(
          index: idx,
          label: label,
          species: species,
          freshness: freshness,
        ));
      }
      labels.sort((a, b) => a.index.compareTo(b.index));
      return labels;
    }

    // -------- CASE 2: List (most likely your file) --------
    if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final value = data[i];
        String label;
        String species;
        String freshness;

        if (value is String) {
          label = value;
          final parts = label.split('-').map((e) => e.trim()).toList();
          if (parts.length >= 2) {
            species = parts[0];
            freshness = parts.sublist(1).join('-').trim();
          } else {
            species = label;
            freshness = '';
          }
        } else if (value is Map<String, dynamic>) {
          final v = value;
          label = (v['label'] ?? '').toString();
          species = (v['species'] ?? '').toString();
          freshness = (v['freshness'] ?? '').toString();
        } else {
          label = value.toString();
          species = label;
          freshness = '';
        }

        labels.add(FishClassLabel(
          index: i,
          label: label,
          species: species,
          freshness: freshness,
        ));
      }
      return labels;
    }

    // -------- Fallback: truly unsupported --------
    throw Exception('Unsupported JSON format for $_labelsAsset: ${data.runtimeType}');
  }
}
