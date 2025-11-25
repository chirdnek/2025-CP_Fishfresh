import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class FishDetConfig {
  final String detectorName;
  final int inputSize;
  final double confThreshold;
  final double iouThreshold;
  final int maxDetections;
  final String tfliteAsset;
  final Map<int, String> labelMap;

  FishDetConfig({
    required this.detectorName,
    required this.inputSize,
    required this.confThreshold,
    required this.iouThreshold,
    required this.maxDetections,
    required this.tfliteAsset,
    required this.labelMap,
  });

  static Future<FishDetConfig> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final jsonData = json.decode(raw);

    final labelsRaw = jsonData["label_map"] as Map<String, dynamic>;
    final labels = {
      for (var e in labelsRaw.entries) int.parse(e.key): e.value.toString()
    };

    return FishDetConfig(
      detectorName: jsonData["detector_name"],
      inputSize: jsonData["input_size"],
      confThreshold: jsonData["conf_threshold"].toDouble(),
      iouThreshold: jsonData["iou_threshold"].toDouble(),
      maxDetections: jsonData["max_detections"],
      tfliteAsset: jsonData["tflite_asset"],
      labelMap: labels,
    );
  }
}
