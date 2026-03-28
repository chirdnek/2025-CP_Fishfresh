// lib/services/fish_classifier.dart
// Plain ResNet50 (torchvision) TFLite classifier wrapper for YOLO crops
//
// - Dynamic input size from TFLite tensor (no hardcoded 224)
// - Preprocess matches Kaggle val_tfms:
//     Resize(shorter-side = int(INPUT_SIZE * 1.15)) -> CenterCrop(INPUT_SIZE)
// - ImageNet normalization: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
// - Outputs top-1 label from classes_flat.json (e.g. "fresh__bigeye_scad")
//
// ignore_for_file: no_leading_underscores_for_local_identifiers, constant_identifier_names, curly_braces_in_flow_control_structures, unused_element

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// ignore: unnecessary_import
import 'dart:typed_data';
// ignore: duplicate_import
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
// ignore: duplicate_import
import 'package:flutter/foundation.dart'; // debugPrint


class FishClassLabel {
  final int index;
  final String label; // e.g. "fresh__bigeye_scad"
  final String species; // e.g. "bigeye_scad"
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
  final double confidence; // probability of the winning class (softmax)

  FishClassification({required this.label, required this.confidence});
}

class FishClassifier {
  FishClassifier._private();
  static final instance = FishClassifier._private();

  static const _tfliteAsset =
      'assets/model/resnet50_torchvision_Mar_7_11-07_am_donkey_float32.tflite';

  static const _labelsAsset = 'assets/model/classes_flat.json';

  // ImageNet normalization (torchvision ResNet50)
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];

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

  late int _side; // expected crop size (e.g. 224)

  Future<void> ensureInited() async {
    if (_isInited) return;

    // 1) Load labels (must match numClasses from the model)
    _labels = await _loadLabels(_labelsAsset);
    debugPrint(
      '🔖 FishClassifier: loaded ${_labels.length} labels from $_labelsAsset',
    );

    // 2) Load interpreter
    _interpreter = await Interpreter.fromAsset(
      _tfliteAsset,
      options: InterpreterOptions()..threads = 2,
    );

    // 3) Cache tensor meta + derive resize/crop config
    _inTensor = _interpreter!.getInputTensor(0);
    _outTensor = _interpreter!.getOutputTensor(0);
    _inType = _inTensor.type;

    final inShape = _inTensor.shape; // expect [1, H, W, 3]
    debugPrint('FishClassifier input shape: $inShape  dtype: $_inType');
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      throw Exception(
        'FishClassifier: unexpected input shape $inShape. Expected [1, H, W, 3].',
      );
    }

    final h = inShape[1];
    final w = inShape[2];
    _side = math.min(h, w);

    final outShape = _outTensor.shape; // e.g. [1, numClasses]
    final numClasses = outShape.isNotEmpty ? outShape.last : 0;
    debugPrint(
      'FishClassifier output shape: ${_outTensor.type} $outShape (numClasses=$numClasses)',
    );
    debugPrint(
      'FishClassifier preprocess: resize(shorter=int($_side * 1.15)) -> center-crop($_side)',
    );

    if (numClasses != _labels.length) {
      throw Exception(
        'FishClassifier: numClasses ($numClasses) != labels.length (${_labels.length}). '
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

  /// Main entry: classify a YOLO crop (img.Image).
  Future<FishClassification> classify(img.Image crop) async {
    if (!_isInited) await ensureInited();

    // 1) Preprocess: Violent Squash (Matches updated Python without bars)
    final pre = _squashLikePyTorch(crop);

    // ✅ ADD THIS HERE (save what ResNet actually sees)
    await debugSaveCropToGallery(pre, 'CLS_INPUT');

    // 2) Run model
    final numClasses = _outTensor.shape.last;
    final inputTensor = [_imageToFloat32(pre)];
    final output = List.generate(
      1,
      (_) => List<double>.filled(numClasses, 0.0),
    );

    _interpreter!.run(inputTensor, output);

    // 3) Softmax -> probs
    final probs = _softmax(output[0]);

    // 4) Argmax
    int bestIdx = 0;
    double bestP = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestP) {
        bestP = probs[i];
        bestIdx = i;
      }
    }

    // 🔴 NEW: Threshold Check (The Fix)
    // If the highest confidence is below 40% (0.40), we treat it as "Unknown".
    // You can adjust 0.40 to be stricter (e.g., 0.60) if needed.
    if (bestP < 0.40) {
      debugPrint(
        '⚠️ Low confidence: ${(bestP * 100).toStringAsFixed(1)}% -> Returning Unknown',
      );
      return FishClassification(
        label: FishClassLabel(
          index: -1,
          label: "Unknown",
          species: "Unknown",
          freshness: "Unknown",
        ),
        confidence: bestP,
      );
    }

    final chosenLabel = _labels[bestIdx];

    debugPrint(
      '🎯 FishClassifier top-1: idx=$bestIdx label="${chosenLabel.label}" '
      'p=${(bestP * 100).toStringAsFixed(1)}%',
    );

    return FishClassification(label: chosenLabel, confidence: bestP);
  }

  // --- Geometry: Resize(shorter-side = int(side * 1.15)) -> CenterCrop(side) ---
  img.Image _resizeShortSideThenCenterCrop(img.Image im) {
  final int side = _side;
  final int resizedShort = (side * 1.15).round();

  final int w = im.width;
  final int h = im.height;

  // resize so that the SHORTER side becomes resizedShort
  int newW, newH;
  if (w <= h) {
    newW = resizedShort;
    newH = ((h / w) * resizedShort).round();
  } else {
    newH = resizedShort;
    newW = ((w / h) * resizedShort).round();
  }

  img.Image resized = img.copyResize(
    im,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.cubic, // was linear
  );

  // center crop to side x side
  final int left = ((resized.width - side) / 2).floor().clamp(0, resized.width - side);
  final int top  = ((resized.height - side) / 2).floor().clamp(0, resized.height - side);

  return img.copyCrop(resized, x: left, y: top, width: side, height: side);
}


  img.Image _padToSquareThenResize(img.Image im) {
    // 1) Pad to square (black), like training PadToSquare()
    final int s = math.max(im.width, im.height);

    img.Image squared = im;
    if (im.width != im.height) {
      final canvas = img.Image(width: s, height: s);
      img.fill(canvas, color: img.ColorRgb8(114, 114, 114)); // gray pad

      final int ox = ((s - im.width) / 2).round();
      final int oy = ((s - im.height) / 2).round();
      img.compositeImage(canvas, im, dstX: ox, dstY: oy);
      squared = canvas;
    }

    // 2) Match training/val: Resize(shorter = int(side*1.15)) -> CenterCrop(side)
    return _resizeShortSideThenCenterCrop(squared);
  }

  img.Image _padToSquareThenResizeNoCrop(img.Image im) {
    final int side = _side;
    final int s = math.max(im.width, im.height);

    // Use 114 gray (same style as YOLO letterbox) instead of black
    final canvas = img.Image(width: s, height: s);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final int ox = ((s - im.width) / 2).round();
    final int oy = ((s - im.height) / 2).round();
    img.compositeImage(canvas, im, dstX: ox, dstY: oy);

    return img.copyResize(
      canvas,
      width: side,
      height: side,
      interpolation: img.Interpolation.cubic,
    );
  }

  // --- New Geometry: Violent Squash (Matches updated Python without bars) ---
  img.Image _squashLikePyTorch(img.Image im) {
    return img.copyResize(
      im,
      width: _side,
      height: _side,
      interpolation: img.Interpolation.cubic, // Matches Python's BICUBIC
    );
  }

  /// Convert image to [H][W][3] float32 with ImageNet normalization.
  List<List<List<double>>> _imageToFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;

    return List.generate(
      h,
      (y) => List.generate(w, (x) {
        final p = image.getPixel(x, y);

        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;

        final nr = (r - _mean[0]) / _std[0];
        final ng = (g - _mean[1]) / _std[1];
        final nb = (b - _mean[2]) / _std[2];

        return [nr, ng, nb];
      }),
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

    String parseFreshness(String label) {
      if (label.startsWith(_freshPrefix)) return 'Fresh';
      if (label.startsWith(_notFreshPrefix)) return 'Not Fresh';
      return '';
    }

    String parseSpecies(String label) {
      if (label.startsWith(_freshPrefix))
        return label.substring(_freshPrefix.length);
      if (label.startsWith(_notFreshPrefix))
        return label.substring(_notFreshPrefix.length);
      return label;
    }

    final List<FishClassLabel> labels = [];

    // Map format: { "0": "fresh__bigeye_scad", ... }
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final idx = int.tryParse(entry.key);
        if (idx == null) continue;

        final rawLabel = entry.value.toString().trim();
        labels.add(
          FishClassLabel(
            index: idx,
            label: rawLabel,
            species: parseSpecies(rawLabel),
            freshness: parseFreshness(rawLabel),
          ),
        );
      }
      labels.sort((a, b) => a.index.compareTo(b.index));
      return labels;
    }

    // List format: [ "fresh__bigeye_scad", ... ]
    if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final rawLabel = data[i].toString().trim();
        labels.add(
          FishClassLabel(
            index: i,
            label: rawLabel,
            species: parseSpecies(rawLabel),
            freshness: parseFreshness(rawLabel),
          ),
        );
      }
      return labels;
    }

    throw Exception(
      'Unsupported JSON format for $assetPath: ${data.runtimeType}',
    );
  }

  Future<void> debugSaveCropToGallery(img.Image im, String tag) async {
    try {
      final bytes = img.encodeJpg(im, quality: 95);

      final result = await ImageGallerySaverPlus.saveImage(
        Uint8List.fromList(bytes),
        quality: 95,
        name: 'FishFresh_${tag}_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('🖼️ Saved to Gallery: $result');
    } catch (e) {
      debugPrint('❌ debugSaveCropToGallery failed: $e');
    }
  }

}
