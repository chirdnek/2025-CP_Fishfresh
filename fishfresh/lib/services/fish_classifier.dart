// lib/services/fish_classifier.dart
// ResNet50 (torchvision) classifier wrapper for species + freshness
//
// • Uses dynamic input size from TFLite (no hardcoded 224)
// • Preprocess matches your Kaggle val_tfms:
//     Resize(shorter-side = int(INPUT_SIZE * 1.15)) → CenterCrop(INPUT_SIZE)
//   where INPUT_SIZE = side from TFLite (usually 224)
// • ImageNet normalization: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
// • 5 species × 2 freshness (10 classes) with labels like "fresh__bigeye_scad"
// • Species + Freshness aggregation (block voting) like your old FishModelResNet
// • TEMP: toned-down fringescale_sardinella by penalizing its logits

// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FishClassLabel {
  final int index;
  final String label;     // e.g. "fresh__bigeye_scad"
  final String species;   // e.g. "bigeye_scad"
  final String freshness; // "Fresh" / "Not Fresh" / ""

  FishClassLabel({
    required this.index,
    required this.label,
    required this.species,
    required this.freshness,
  });
}

class FishClassification {
  final FishClassLabel label;
  final double confidence; // species-block confidence (Fresh+NotFresh)

  FishClassification({
    required this.label,
    required this.confidence,
  });
}

class FishClassifier {
  FishClassifier._private();
  static final instance = FishClassifier._private();

  // ⬇️ Your ResNet50 TFLite
  static const _tfliteAsset =
      'assets/model/resnet50_torchvision_Dec_6_5-33_pm_6species_float32.tflite';

  // ⬇️ classes_flat.json copied from /kaggle/working/models/classes_flat.json
  static const _labelsAsset = 'assets/model/classes_flat.json';

  // ImageNet normalization (torchvision ResNet50)
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std  = [0.229, 0.224, 0.225];

  // Label prefixes in your dataset
  static const String _freshPrefix = 'fresh__';
  static const String _notFreshPrefix = 'not_fresh__';

  Interpreter? _interpreter;
  bool _isInited = false;
  late List<FishClassLabel> _labels;

  // Cached IO meta
  late Tensor _inTensor;
  late Tensor _outTensor;
  late TensorType _inType;
  late TensorType _outType;

  late int _side;  // expected crop size (e.g. 224)

  // Indices for fringescale_sardinella (both fresh + not_fresh)
  late List<int> _fringescaleIndices;

  Future<void> ensureInited() async {
    if (_isInited) return;

    // 1) Load labels (must match numClasses from the model)
    _labels = await _loadLabels(_labelsAsset);
    debugPrint('🔖 FishClassifier: loaded ${_labels.length} labels from $_labelsAsset');
    for (final lbl in _labels) {
      debugPrint('  idx=${lbl.index.toString().padLeft(2)}'
          ' label="${lbl.label}"'
          ' species="${lbl.species}"'
          ' freshness="${lbl.freshness}"');
    }

    // Collect indices for fringescale_sardinella
    _fringescaleIndices = _labels
        .where((lbl) => lbl.species == 'fringescale_sardinella')
        .map((lbl) => lbl.index)
        .toList();
    debugPrint('🐟 Fringescale indices: $_fringescaleIndices');

    // 2) Load classifier interpreter
    _interpreter = await Interpreter.fromAsset(
      _tfliteAsset,
      options: InterpreterOptions()..threads = 2,
    );

    // 3) Cache tensor meta and derive resize/crop config
    _inTensor = _interpreter!.getInputTensor(0);
    _outTensor = _interpreter!.getOutputTensor(0);
    _inType = _inTensor.type;
    _outType = _outTensor.type;

    final inShape = _inTensor.shape; // expect [1, H, W, 3]
    debugPrint('FishClassifier input shape: $inShape  dtype: $_inType');
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      throw Exception(
        'FishClassifier: unexpected input shape $inShape. Expected [1, H, W, 3].',
      );
    }

    final h = inShape[1];
    final w = inShape[2];
    if (h != w) {
      debugPrint(
        '⚠️ FishClassifier: non-square input $w×$h, using min(h,w) for center-crop.',
      );
    }
    _side = math.min(h, w); // this should be 224 for your ResNet TFLite

    final outShape = _outTensor.shape; // e.g., [1, 10]
    final numUnits = outShape.isNotEmpty ? outShape.last : 0;
    debugPrint('FishClassifier output shape: $_outType $outShape (numClasses=$numUnits)');
    debugPrint(
      'FishClassifier preprocess (Kaggle val_tfms): '
      'resize(shorter=int($_side * 1.15)) → center-crop($_side)',
    );

    // ⚠️ label count MUST match numClasses from the model
    if (numUnits != _labels.length) {
      debugPrint(
        '❌ FishClassifier MISMATCH: model outputs $numUnits classes but labels list has ${_labels.length}.',
      );
      throw Exception(
        'FishClassifier: numClasses ($numUnits) != labels.length (${_labels.length}). '
        'Use a matching classes_flat.json for this TFLite.',
      );
    }

    if (_inType != TensorType.float32) {
      debugPrint(
        '⚠️ FishClassifier: expected float32 input, but got $_inType. Code assumes float32.',
      );
    }

    _isInited = true;
  }

  /// Main entry: classify a cropped fish image (YOLO crop).
  Future<FishClassification> classify(img.Image crop) async {
    if (!_isInited) await ensureInited();

    // 1) Resize(shorter=int(side * 1.15)) + CenterCrop(side) — like Kaggle val_tfms
    final pre = _resizeShortSideThenCenterCrop(crop);

    // 2) Convert to normalized float32 tensor [1, H, W, 3]
    final inputTensor = [_imageToFloat32(pre)];

    // 3) Prepare output buffer [1, numClasses]
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final numClasses = outputShape.last;
    final output =
        List.generate(1, (_) => List<double>.filled(numClasses, 0.0));

    _interpreter!.run(inputTensor, output);

    // 4) Get logits
    final logits = output[0];

    // TEMP: penalize fringescale logits so it doesn't dominate weak cases.
    const double penalty = 0.8; // tweak this in [0.5, 1.5] if needed
    for (final idx in _fringescaleIndices) {
      if (idx >= 0 && idx < logits.length) {
        logits[idx] -= penalty;
      }
    }

    // Now softmax on adjusted logits → probabilities
    final probs = _softmax(logits);

    // 🔍 Debug: top-3 after penalty (for inspection)
    final indexed = <int, double>{};
    for (int i = 0; i < probs.length; i++) {
      indexed[i] = probs[i];
    }
    final topK = indexed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final k = math.min(3, topK.length);
    final topStr = List.generate(k, (i) {
      final idx = topK[i].key;
      final p = topK[i].value * 100.0;
      final lbl = (idx >= 0 && idx < _labels.length)
          ? _labels[idx].label
          : 'idx=$idx';
      return '#$i: idx=$idx  $lbl  (${p.toStringAsFixed(1)}%)';
    }).join(' | ');
    debugPrint('🎯 ResNet50 FishClassifier top-k (after penalty): $topStr');

    // 5) Species + Freshness aggregation (like old FishModelResNet)
    final speciesScores = <String, double>{};              // sum of fresh+not_fresh per species
    final freshnessPair = <String, Map<String, double>>{}; // per species: { Fresh, Not Fresh }

    for (int i = 0; i < probs.length; i++) {
      final lbl = _labels[i];
      final p = probs[i];
      final sp = lbl.species;
      final fr = lbl.freshness; // "Fresh" or "Not Fresh" or ""

      // Skip unknown/empty species (just in case)
      if (sp.isEmpty) continue;

      // 5.1) Species total score
      speciesScores.update(sp, (v) => v + p, ifAbsent: () => p);

      // 5.2) Freshness pair per species
      final map = (freshnessPair[sp] ??= {'Fresh': 0.0, 'Not Fresh': 0.0});
      if (fr == 'Fresh' || fr == 'Not Fresh') {
        map[fr] = (map[fr] ?? 0.0) + p;
      }
    }

    if (speciesScores.isEmpty) {
      // Fallback to raw argmax if something goes weird
      int bestIdx = 0;
      double bestScore = probs[0];
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > bestScore) {
          bestScore = probs[i];
          bestIdx = i;
        }
      }
      final fallbackLabel = _labels[bestIdx];
      debugPrint('⚠️ FishClassifier: speciesScores empty, falling back to argmax.');
      return FishClassification(
        label: fallbackLabel,
        confidence: bestScore,
      );
    }

    // 6) Pick best species by combined fresh+not_fresh probability
    final sortedSpecies = speciesScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSpecies = sortedSpecies.first.key;
    final topSpeciesScore = sortedSpecies.first.value;

    final pair = freshnessPair[topSpecies] ?? {'Fresh': 0.0, 'Not Fresh': 0.0};
    final freshScore = pair['Fresh'] ?? 0.0;
    final notFreshScore = pair['Not Fresh'] ?? 0.0;

    final decidedFreshness =
        freshScore >= notFreshScore ? 'Fresh' : 'Not Fresh';

    debugPrint(
      '✅ Species-block decision → species="$topSpecies" '
      '| Fresh=${(freshScore * 100).toStringAsFixed(1)}% '
      '| NotFresh=${(notFreshScore * 100).toStringAsFixed(1)}% '
      '| speciesScore=${(topSpeciesScore * 100).toStringAsFixed(1)}%',
    );

    // 7) Find a concrete label object that matches (species + freshness)
    FishClassLabel? chosenLabel;
    for (final lbl in _labels) {
      if (lbl.species == topSpecies && lbl.freshness == decidedFreshness) {
        chosenLabel = lbl;
        break;
      }
    }

    // If not found (weird), fall back to the highest-prob label from that species
    if (chosenLabel == null) {
      double bestP = -1;
      int bestIdx = 0;
      for (int i = 0; i < probs.length; i++) {
        final lbl = _labels[i];
        if (lbl.species != topSpecies) continue;
        if (probs[i] > bestP) {
          bestP = probs[i];
          bestIdx = i;
        }
      }
      chosenLabel = _labels[bestIdx];
      debugPrint(
        '⚠️ FishClassifier: no exact (species+freshness) match found, using best neuron within species.',
      );
    }

    // Confidence: use the species-score (Fresh+NotFresh for that species),
    // so UI sees how "sure" we are about the species as a whole.
    return FishClassification(
      label: chosenLabel,
      confidence: topSpeciesScore,
    );
  }

  // --- Geometry: Resize(shorter-side = int(side * 1.15)) → CenterCrop(side) ---
  img.Image _resizeShortSideThenCenterCrop(img.Image im) {
    final int side = _side;

    // Match Kaggle val_tfms: Resize(int(INPUT_SIZE * 1.15)) → CenterCrop(INPUT_SIZE)
    const double _resizeFactor = 1.15;
    final int targetShort = math.max(1, (side * _resizeFactor).round());

    final int w = im.width;
    final int h = im.height;

    final double shortSide = math.min(w, h).toDouble();
    final double scaleFactor = targetShort / shortSide;
    final int newW = math.max(1, (w * scaleFactor).round());
    final int newH = math.max(1, (h * scaleFactor).round());

    final img.Image resized = img.copyResize(im, width: newW, height: newH);

    final int x0 = math.max(0, (resized.width - side) ~/ 2);
    final int y0 = math.max(0, (resized.height - side) ~/ 2);
    final int cropW = math.min(side, resized.width);
    final int cropH = math.min(side, resized.height);

    final img.Image cropped = img.copyCrop(
      resized,
      x: x0,
      y: y0,
      width: cropW,
      height: cropH,
    );

    if (cropped.width != side || cropped.height != side) {
      return img.copyResize(cropped, width: side, height: side);
    }
    return cropped;
  }

  // --- Helpers ---

  /// Convert image to [H][W][3] float32, **with ImageNet normalization**.
  List<List<List<double>>> _imageToFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;

    return List.generate(
      h,
      (y) => List.generate(
        w,
        (x) {
          final p = image.getPixel(x, y);

          final r = p.r / 255.0;
          final g = p.g / 255.0;
          final b = p.b / 255.0;

          final nr = (r - _mean[0]) / _std[0];
          final ng = (g - _mean[1]) / _std[1];
          final nb = (b - _mean[2]) / _std[2]; // ✅ fixed: subtract mean[2], not std

          return [nr, ng, nb];
        },
      ),
    );
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
    final sumExp = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sumExp).toList();
  }

  // --- Label loading: "fresh__species" / "not_fresh__species" ---

  Future<List<FishClassLabel>> _loadLabels(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = json.decode(raw);

    final List<FishClassLabel> labels = [];

    String _parseFreshness(String label) {
      if (label.startsWith(_freshPrefix)) return 'Fresh';
      if (label.startsWith(_notFreshPrefix)) return 'Not Fresh';
      return '';
    }

    String _parseSpecies(String label) {
      if (label.startsWith(_freshPrefix)) {
        return label.substring(_freshPrefix.length);
      }
      if (label.startsWith(_notFreshPrefix)) {
        return label.substring(_notFreshPrefix.length);
      }
      // Fallback: entire string
      return label;
    }

    // Map<String,dynamic> format: { "0": "fresh__bigeye_scad", ... }
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final idx = int.tryParse(entry.key);
        if (idx == null) {
          debugPrint(
            '⚠️ FishClassifier: label map key "${entry.key}" is not an int index.',
          );
          continue;
        }

        String rawLabel;
        if (entry.value is String) {
          rawLabel = (entry.value as String).trim();
        } else if (entry.value is Map<String, dynamic>) {
          final v = entry.value as Map<String, dynamic>;
          rawLabel = (v['label'] ?? '').toString().trim();
        } else {
          rawLabel = entry.value.toString().trim();
        }

        final species = _parseSpecies(rawLabel);
        final freshness = _parseFreshness(rawLabel);

        labels.add(FishClassLabel(
          index: idx,
          label: rawLabel,
          species: species,
          freshness: freshness,
        ));
      }
      labels.sort((a, b) => a.index.compareTo(b.index));
      return labels;
    }

    // List format: [ "fresh__bigeye_scad", "fresh__country_maiden", ... ]
    if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final value = data[i];
        String rawLabel;

        if (value is String) {
          rawLabel = value.trim();
        } else if (value is Map<String, dynamic>) {
          final v = value;
          rawLabel = (v['label'] ?? '').toString().trim();
        } else {
          rawLabel = value.toString().trim();
        }

        final species = _parseSpecies(rawLabel);
        final freshness = _parseFreshness(rawLabel);

        labels.add(FishClassLabel(
          index: i,
          label: rawLabel,
          species: species,
          freshness: freshness,
        ));
      }
      return labels;
    }

    throw Exception(
      'Unsupported JSON format for $_labelsAsset: ${data.runtimeType}',
    );
  }
}
