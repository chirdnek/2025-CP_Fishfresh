// lib/services/fish_pipeline.dart
// YOLOv8 TFLite + ResNet pipeline
// ignore_for_file: avoid_print, constant_identifier_names, no_leading_underscores_for_local_identifiers, unnecessary_import, unused_element

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'fish_detector.dart';
import 'fish_classifier.dart';

/// Modes:
///  - auto   : if YOLO finds >=2 boxes → tray; else → single crop
///  - single : always single-fish crop (YOLO bbox if available, else full-frame)
///  - tray   : always multi-fish YOLO + crop + ResNet per fish
enum ScanMode { auto, single, tray }

class FishPipeline {
  FishPipeline._private();
  static final instance = FishPipeline._private();

  bool _isInited = false;

  Future<void> ensureInited() async {
    if (_isInited) return;
    await FishDetector.instance.ensureInited();
    await FishClassifier.instance.ensureInited();
    _isInited = true;
  }

  // ---------------------------------------------------------------------------
  // IoU (Intersection over Union)
  // ---------------------------------------------------------------------------
  double _iou(Rect a, Rect b) {
    final double xA = a.left > b.left ? a.left : b.left;
    final double yA = a.top > b.top ? a.top : b.top;
    final double xB = a.right < b.right ? a.right : b.right;
    final double yB = a.bottom < b.bottom ? a.bottom : b.bottom;

    if (xB <= xA || yB <= yA) return 0.0;

    final inter = (xB - xA) * (yB - yA);
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    return inter / (areaA + areaB - inter);
  }

  // ---------------------------------------------------------------------------
  // NMS-style suppression (keep best boxes, drop strong overlaps)
  // ---------------------------------------------------------------------------
  List<FishDetection> _nms(
    List<FishDetection> dets, {
    required double iouThresh,
  }) {
    if (dets.isEmpty) return [];

    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <FishDetection>[];

    for (final d in sorted) {
      bool keep = true;
      for (final k in kept) {
        if (_iou(d.box, k.box) >= iouThresh) {
          keep = false;
          break;
        }
      }
      if (keep) kept.add(d);
    }
    return kept;
  }

  // ---------------------------------------------------------------------------
  // Aspect helpers
  // ---------------------------------------------------------------------------

  /// Generic aspect check: orientation-agnostic
  /// (ratio = longer side / shorter side).
  bool _validAspect(
    Rect r, {
    required double minRatio,
    required double maxRatio,
  }) {
    final double w = r.width;
    final double h = r.height;
    if (w <= 0 || h <= 0) return false;

    final double longSide = w >= h ? w : h;
    final double shortSide = w >= h ? h : w;
    final double ratio = longSide / shortSide;

    return ratio >= minRatio && ratio <= maxRatio;
  }

  // ---------------------------------------------------------------------------
  // SINGLE-FISH FILTER (currently not used, but kept for future tuning)
  // ---------------------------------------------------------------------------

  List<FishDetection> _filterSingle(
    List<FishDetection> dets,
    double imgW,
    double imgH, {
    double maxAreaFrac = 0.85,
    double minAreaFrac = 0.01,
  }) {
    final double imageArea = imgW * imgH;

    return dets.where((d) {
      final Rect b = d.box;
      final double boxArea = b.width * b.height;

      if (boxArea > imageArea * maxAreaFrac) return false;
      if (boxArea < imageArea * minAreaFrac) return false;

      if (!_validAspect(b, minRatio: 1.5, maxRatio: 8.0)) return false;

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // TRAY FILTER (loose – we want one box per fish, not per tray/row)
  // ---------------------------------------------------------------------------

  List<FishDetection> _filterTray(
    List<FishDetection> dets,
    double imgW,
    double imgH, {
    double maxAreaFrac = 0.45,
    double minAreaFrac = 0.010,
  }) {
    if (dets.isEmpty) return [];

    final double imageArea = imgW * imgH;
    final kept = <FishDetection>[];

    for (final d in dets) {
      final Rect b = d.box;
      final double boxArea = b.width * b.height;
      final double areaFrac = boxArea / imageArea;
      final double widthFrac = b.width / imgW;
      final double heightFrac = b.height / imgH;

      if (areaFrac < minAreaFrac) continue;
      if (areaFrac > maxAreaFrac) continue;

      if (!_validAspect(b, minRatio: 1.3, maxRatio: 6.5)) continue;

      // Drop "row" boxes (very wide, not tall)
      if (widthFrac > 0.75 && heightFrac < 0.40) {
        continue;
      }

      // Drop near-whole-tray boxes
      if (areaFrac > 0.30 && (widthFrac > 0.85 || heightFrac > 0.85)) {
        continue;
      }

      kept.add(d);
    }

    return kept;
  }

  // ---------------------------------------------------------------------------
  // Expand bounding box slightly for UI (pretty boxes)
  // ---------------------------------------------------------------------------

  Rect _expandForUi(Rect r, double W, double H) {
    // small margin → more "normal" boxes
    const double marginFracX = 0.03;
    const double marginFracY = 0.05;

    final double ex = r.width * marginFracX;
    final double ey = r.height * marginFracY;

    double left = (r.left - ex).clamp(0.0, W);
    double top = (r.top - ey).clamp(0.0, H);
    double right = (r.right + ex).clamp(0.0, W);
    double bottom = (r.bottom + ey).clamp(0.0, H);

    if (right <= left) right = left + 1;
    if (bottom <= top) bottom = top + 1;

    return Rect.fromLTRB(left, top, right, bottom);
  }


  // ---------------------------------------------------------------------------
  // Expand bounding box for crops (more context)
  // ---------------------------------------------------------------------------


  Rect _expandForCrop(Rect r, double W, double H) {
    const double marginFracX = 0.08;
    const double marginFracY = 0.08;

    final double ex = r.width * marginFracX;
    final double ey = r.height * marginFracY;

    double left = (r.left - ex).clamp(0.0, W);
    double top = (r.top - ey).clamp(0.0, H);
    double right = (r.right + ex).clamp(0.0, W);
    double bottom = (r.bottom + ey).clamp(0.0, H);

    if (right <= left) right = left + 1;
    if (bottom <= top) bottom = top + 1;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ---------------------------------------------------------------------------
  // Make a square crop around a bbox (for classifier only)
  // ---------------------------------------------------------------------------
  Rect _squareAround(
    Rect r,
    double W,
    double H, {
    double scale = 1.20,
  }) {
    final double cx = (r.left + r.right) / 2.0;
    final double cy = (r.top + r.bottom) / 2.0;

    final double baseSide = r.width >= r.height ? r.width : r.height;
    double side = baseSide * scale;

    double left = cx - side / 2.0;
    double top = cy - side / 2.0;
    double right = cx + side / 2.0;
    double bottom = cy + side / 2.0;

    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > W) {
      final overflow = right - W;
      left -= overflow;
      right = W;
    }
    if (bottom > H) {
      final overflow = bottom - H;
      top -= overflow;
      bottom = H;
    }

    if (right <= left) right = left + 1;
    if (bottom <= top) bottom = top + 1;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ---------------------------------------------------------------------------
  // Main pipeline
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> runOnBytes(
    Uint8List bytes, {
    ScanMode mode = ScanMode.auto,
  }) async {
    await ensureInited();

    img.Image? fullImg = img.decodeImage(bytes);
    if (fullImg == null) throw Exception("Decode failed");

    // Apply EXIF orientation to pixels (prevents rotated/offset crops)
    try {
      fullImg = img.bakeOrientation(fullImg);
    } catch (_) {
      // If bakeOrientation isn't available in your image package version, ignore for now.
    }
    if (fullImg == null) {
      throw Exception("Decode failed");
    }

    final double imgW = fullImg.width.toDouble();
    final double imgH = fullImg.height.toDouble();

    // 1) Run detector
    final sw = Stopwatch()..start();
    var rawDetections = await FishDetector.instance.detect(bytes);
    sw.stop();

    debugPrint(
      'FishPipeline: raw YOLO detections = ${rawDetections.length} (requested mode=${mode.name})',
    );
    // Keep ONLY the YOLO "Fish" class (matches your notebook classes=[fish_id])
    const int fishClassId = 192;
    rawDetections = rawDetections.where((d) => d.classId == fishClassId).toList();
    debugPrint('FishPipeline: fish-only detections = ${rawDetections.length}');


    // ---- If YOLO completely fails, fall back to full-frame ResNet (single) ----
    if (rawDetections.isEmpty && mode != ScanMode.tray) {
      final cls = await FishClassifier.instance.classify(fullImg);
      final species = cls.label.species;
      final freshness = cls.label.freshness;
      final clsConf = cls.confidence;

      return {
        'latency_ms': sw.elapsedMilliseconds,
        'per_fish': [
          {
            'fish_box_id': 1,
            'box_norm': {
              'left': 0.0,
              'top': 0.0,
              'right': 1.0,
              'bottom': 1.0,
            },
            'species': species,
            'freshness': freshness,
            'cls_conf': clsConf,
            'det_score': 1.0,
          }
        ],
        'overall_species': species,
        'overall_freshness': freshness,
        'scan_mode': 'single-no-yolo',
      };
    }

    // 2) NMS
    var merged = _nms(rawDetections, iouThresh: 0.45);
    debugPrint('FishPipeline: after NMS = ${merged.length}');

    // Sort by score and keep bestDet for UI / single mode
    merged.sort((a, b) => b.score.compareTo(a.score));
    final bestDet = merged.isNotEmpty ? merged.first : null;

    // 3) Tray candidates (for multi-fish)
    var trayCandidates =
        _filterTray(List<FishDetection>.from(merged), imgW, imgH);
    debugPrint(
      'FishPipeline: tray candidates after filter = ${trayCandidates.length}',
    );

    // -----------------------------------------------------------------------
    // Decide mode
    // -----------------------------------------------------------------------
    bool trayMode;
    if (mode == ScanMode.tray) {
      trayMode = true;
    } else if (mode == ScanMode.single) {
      trayMode = false;
    } else {
      trayMode = trayCandidates.length >= 2;
    }

    final resolvedMode = trayMode ? 'tray' : 'single';
    debugPrint('FishPipeline: effective mode = $resolvedMode');

    // -----------------------------------------------------------------------
    // SINGLE / CROP PATH
    // -----------------------------------------------------------------------
    if (!trayMode) {
      Rect uiRect;
      Rect cropRect;
      img.Image cropImage;

      if (bestDet != null) {
        // nice-looking UI box (rectangular, small margin)
        uiRect = _expandForUi(bestDet.box, imgW, imgH);

        // bigger square for classifier
        final Rect expandedForCrop =
            _expandForCrop(bestDet.box, imgW, imgH);
        cropRect = _squareAround(expandedForCrop, imgW, imgH, scale: 1.20);

        final int left = cropRect.left.floor().clamp(0, fullImg.width - 1);
        final int top = cropRect.top.floor().clamp(0, fullImg.height - 1);
        final int right =
            cropRect.right.ceil().clamp(left + 1, fullImg.width);
        final int bottom =
            cropRect.bottom.ceil().clamp(top + 1, fullImg.height);

        final int w = (right - left).clamp(1, fullImg.width);
        final int h = (bottom - top).clamp(1, fullImg.height);

        cropImage = img.copyCrop(
          fullImg,
          x: left,
          y: top,
          width: w,
          height: h,
        );
      } else {
        uiRect = Rect.fromLTRB(0.0, 0.0, imgW, imgH);
        cropRect = uiRect;
        cropImage = fullImg;
      }

      final cls = await FishClassifier.instance.classify(cropImage);
      final species = cls.label.species;
      final freshness = cls.label.freshness;
      final clsConf = cls.confidence;

      final perFish = [
        {
          'fish_box_id': 1,
          'box_norm': {
            'left': uiRect.left / imgW,
            'top': uiRect.top / imgH,
            'right': uiRect.right / imgW,
            'bottom': uiRect.bottom / imgH,
          },
          'species': species,
          'freshness': freshness,
          'cls_conf': clsConf,
          'det_score': bestDet?.score ?? 1.0,
        }
      ];

      return {
        'latency_ms': sw.elapsedMilliseconds,
        'per_fish': perFish,
        'overall_species': species,
        'overall_freshness': freshness,
        'scan_mode': resolvedMode,
      };
    }

    // -----------------------------------------------------------------------
    // TRAY / MULTI-FISH PATH
    // -----------------------------------------------------------------------

    if (trayCandidates.isEmpty) {
      // Safety: fall back to single behaviour
      Rect uiRect;
      Rect cropRect;
      img.Image cropImage;

      if (bestDet != null) {
        uiRect = _expandForUi(bestDet.box, imgW, imgH);
        final Rect expandedForCrop =
            _expandForCrop(bestDet.box, imgW, imgH);
        cropRect = _squareAround(expandedForCrop, imgW, imgH, scale: 1.20);

        final int left = cropRect.left.floor().clamp(0, fullImg.width - 1);
        final int top = cropRect.top.floor().clamp(0, fullImg.height - 1);
        final int right =
            cropRect.right.ceil().clamp(left + 1, fullImg.width);
        final int bottom =
            cropRect.bottom.ceil().clamp(top + 1, fullImg.height);

        final int w = (right - left).clamp(1, fullImg.width);
        final int h = (bottom - top).clamp(1, fullImg.height);

        cropImage = img.copyCrop(
          fullImg,
          x: left,
          y: top,
          width: w,
          height: h,
        );
      } else {
        uiRect = Rect.fromLTRB(0.0, 0.0, imgW, imgH);
        cropRect = uiRect;
        cropImage = fullImg;
      }

      final cls = await FishClassifier.instance.classify(cropImage);
      final species = cls.label.species;
      final freshness = cls.label.freshness;
      final clsConf = cls.confidence;

      final perFish = [
        {
          'fish_box_id': 1,
          'box_norm': {
            'left': uiRect.left / imgW,
            'top': uiRect.top / imgH,
            'right': uiRect.right / imgW,
            'bottom': uiRect.bottom / imgH,
          },
          'species': species,
          'freshness': freshness,
          'cls_conf': clsConf,
          'det_score': bestDet?.score ?? 1.0,
        }
      ];

      return {
        'latency_ms': sw.elapsedMilliseconds,
        'per_fish': perFish,
        'overall_species': species,
        'overall_freshness': freshness,
        'scan_mode': 'single-fallback',
      };
    }

    // Optional: cap number of tray detections
    const int maxTrayDetections = 8;
    if (trayCandidates.length > maxTrayDetections) {
      trayCandidates.sort((a, b) => b.score.compareTo(a.score));
      trayCandidates = trayCandidates.sublist(0, maxTrayDetections);
    }

    // 4) Crop + classify per fish (tray mode)
    final perFish = <Map<String, dynamic>>[];
    int boxCounter = 0;

    for (final d in trayCandidates) {
      boxCounter++;

      // YOLO box → pretty UI rect
      final Rect uiRect = _expandForUi(d.box, imgW, imgH);

      // For classifier: slightly bigger square around expanded crop region
      final Rect expandedForCrop =
          _expandForCrop(d.box, imgW, imgH);
      final Rect cropRect =
          _squareAround(expandedForCrop, imgW, imgH, scale: 1.20);

      final int left = cropRect.left.floor().clamp(0, fullImg.width - 1);
      final int top = cropRect.top.floor().clamp(0, fullImg.height - 1);
      final int right =
          cropRect.right.ceil().clamp(left + 1, fullImg.width);
      final int bottom =
          cropRect.bottom.ceil().clamp(top + 1, fullImg.height);

      final int w = (right - left).clamp(1, fullImg.width);
      final int h = (bottom - top).clamp(1, fullImg.height);

      final crop = img.copyCrop(
        fullImg,
        x: left,
        y: top,
        width: w,
        height: h,
      );

      final cls = await FishClassifier.instance.classify(crop);

      final String species = cls.label.species;
      final String freshness = cls.label.freshness;
      final double clsConf = cls.confidence;
      final double detScore = d.score;

      perFish.add({
        'fish_box_id': boxCounter,
        'box_norm': {
          'left': uiRect.left / imgW,
          'top': uiRect.top / imgH,
          'right': uiRect.right / imgW,
          'bottom': uiRect.bottom / imgH,
        },
        'species': species,
        'freshness': freshness,
        'cls_conf': clsConf,
        'det_score': detScore,
      });
    }

    // -----------------------------------------------------------------------
    // 5) TRAY-LEVEL SUMMARY (no species snapping)
    // -----------------------------------------------------------------------
    final Map<String, int> speciesCounts = {};
    for (final f in perFish) {
      final s = (f['species'] ?? '') as String;
      if (s.isEmpty) continue;
      speciesCounts[s] = (speciesCounts[s] ?? 0) + 1;
    }

    String overallSpecies;
    String overallFreshness;

    if (speciesCounts.isNotEmpty) {
      final majorityEntry = speciesCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final String majoritySpecies = majorityEntry.key;

      overallSpecies = majoritySpecies;

      double freshSum = 0.0;
      double notFreshSum = 0.0;

      for (final f in perFish) {
        final s = (f['species'] ?? '') as String;
        if (s != majoritySpecies) continue;

        final fr = ((f['freshness'] ?? '') as String).toLowerCase();
        final double c = (f['cls_conf'] ?? 0.0) as double;

        if (fr == 'fresh') {
          freshSum += c;
        } else if (fr == 'not fresh') {
          notFreshSum += c;
        }
      }

      if (freshSum == 0.0 && notFreshSum == 0.0) {
        overallFreshness = 'Unknown';
      } else {
        overallFreshness =
            (freshSum >= notFreshSum) ? 'Fresh' : 'Not Fresh';
      }
    } else {
      Map<String, dynamic> top = perFish.first;
      for (final f in perFish) {
        if ((f['cls_conf'] as double) > (top['cls_conf'] as double)) {
          top = f;
        }
      }
      overallSpecies = (top['species'] ?? 'Unknown').toString();
      overallFreshness = (top['freshness'] ?? 'Unknown').toString();
    }

    return {
      'latency_ms': sw.elapsedMilliseconds,
      'per_fish': perFish,
      'overall_species': overallSpecies,
      'overall_freshness': overallFreshness,
      'scan_mode': resolvedMode,
    };
  }
}