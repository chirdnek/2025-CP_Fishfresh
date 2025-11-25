// lib/services/fish_pipeline.dart
// YOLOv8 TFLite + MobileNet pipeline
// ignore_for_file: avoid_print, constant_identifier_names, no_leading_underscores_for_local_identifiers

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import 'fish_detector.dart';
import 'fish_classifier.dart';

/// Two modes:
///  - single : expect one fish; aggressive NMS + extra filters
///  - tray   : many fish; keep per-fish boxes, drop “whole row/tray” boxes
enum ScanMode { single, tray }

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
  // NMS-style suppression (keep best boxes, drop overlaps)
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
  // Extra filters
  // ---------------------------------------------------------------------------

  /// Aspect check for single-fish shots (orientation agnostic).
  /// We only care that the fish is noticeably longer than tall,
  /// whether it's vertical or horizontal.
  bool _validAspectSingle(Rect r) {
    final double w = r.width;
    final double h = r.height;
    if (w <= 0 || h <= 0) return false;

    // Make orientation-agnostic: length / thickness
    final double longSide = w >= h ? w : h;
    final double shortSide = w >= h ? h : w;
    final double ratio = longSide / shortSide;

    // a single fish should be at least ~1.5x longer than thick, but not crazy
    return ratio >= 1.5 && ratio <= 8.0;
  }

  /// SINGLE-FISH FILTER (only affects ScanMode.single)
  List<FishDetection> _filterSingle(
    List<FishDetection> dets,
    double imgW,
    double imgH, {
    // allow single fish to occupy more of the frame
    double maxAreaFrac = 0.85, // was 0.60
    double minAreaFrac = 0.01,
  }) {
    final double imageArea = imgW * imgH;

    return dets.where((d) {
      final Rect b = d.box;
      final double boxArea = b.width * b.height;

      // too tiny or too huge → drop
      if (boxArea > imageArea * maxAreaFrac) return false;
      if (boxArea < imageArea * minAreaFrac) return false;

      // wrong shape → drop
      if (!_validAspectSingle(b)) return false;

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // SMART TRAY FILTER (unchanged)
  // ---------------------------------------------------------------------------

  List<FishDetection> _filterTray(
    List<FishDetection> dets,
    double imgW,
    double imgH, {
    double maxAreaFrac = 0.35,
    double minAreaFrac = 0.010,
  }) {
    if (dets.isEmpty) return [];

    final double imageArea = imgW * imgH;

    final widths = <double>[];
    final areas = <double>[];

    for (final d in dets) {
      final b = d.box;
      final a = b.width * b.height;
      widths.add(b.width);
      areas.add(a);
    }

    widths.sort();
    areas.sort();

    double _median(List<double> v) {
      if (v.isEmpty) return 0;
      final n = v.length;
      if (n.isOdd) return v[n ~/ 2];
      return (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2.0;
    }

    final double medianW = _median(widths);
    final double medianArea = _median(areas);

    final bool useRelativeHeuristics =
        dets.length >= 3 && medianW > 0 && medianArea > 0;

    final kept = <FishDetection>[];

    for (final d in dets) {
      final Rect b = d.box;
      final double boxArea = b.width * b.height;

      final double areaFrac = boxArea / imageArea;
      final double widthFrac = b.width / imgW;

      if (areaFrac < minAreaFrac) continue;
      if (areaFrac > maxAreaFrac) continue;

      if (useRelativeHeuristics) {
        final bool muchWider = b.width > medianW * 1.6;
        final bool muchBigger = boxArea > medianArea * 1.6;
        if (muchWider && muchBigger) continue;
      }

      if (widthFrac > 0.85 && areaFrac > 0.12) continue;

      kept.add(d);
    }

    return kept;
  }

  // ---------------------------------------------------------------------------
  // Expand bounding box slightly for cropping
  // ---------------------------------------------------------------------------
  Rect _expand(Rect r, double W, double H) {
    const double marginFracX = 0.03;
    const double marginFracY = 0.06;

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
  // Main pipeline
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> runOnBytes(
    Uint8List bytes, {
    ScanMode mode = ScanMode.single,
  }) async {
    await ensureInited();

    final fullImg = img.decodeImage(bytes);
    if (fullImg == null) {
      throw Exception("Decode failed");
    }

    final double imgW = fullImg.width.toDouble();
    final double imgH = fullImg.height.toDouble();

    // 1) Run detector
    final sw = Stopwatch()..start();
    final rawDetections = await FishDetector.instance.detect(bytes);
    sw.stop();

    if (rawDetections.isEmpty) {
      return {
        'latency_ms': sw.elapsedMilliseconds,
        'per_fish': <Map<String, dynamic>>[],
        'overall_species': '',
        'overall_freshness': '',
        'scan_mode': mode.name,
      };
    }

    final bool trayMode = (mode == ScanMode.tray);

    // 2) NMS
    var merged = _nms(
      rawDetections,
      iouThresh: trayMode ? 0.45 : 0.8,
    );

    // 3) Filtering
    if (trayMode) {
      merged = _filterTray(merged, imgW, imgH);
    } else {
      merged = _filterSingle(merged, imgW, imgH);
    }

    if (merged.isEmpty) {
      return {
        'latency_ms': sw.elapsedMilliseconds,
        'per_fish': <Map<String, dynamic>>[],
        'overall_species': '',
        'overall_freshness': '',
        'scan_mode': mode.name,
      };
    }

    // 4) Single mode: keep only highest-score
    if (!trayMode && merged.length > 1) {
      merged.sort((a, b) => b.score.compareTo(a.score));
      merged = [merged.first];
    }

    // 5) Crop + classify
    final perFish = <Map<String, dynamic>>[];

    for (final d in merged) {
      final Rect e = _expand(d.box, imgW, imgH);

      final int left = e.left.floor().clamp(0, fullImg.width - 1);
      final int top = e.top.floor().clamp(0, fullImg.height - 1);
      final int right = e.right.ceil().clamp(left + 1, fullImg.width);
      final int bottom = e.bottom.ceil().clamp(top + 1, fullImg.height);

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

      perFish.add({
        'box_norm': {
          'left': e.left / imgW,
          'top': e.top / imgH,
          'right': e.right / imgW,
          'bottom': e.bottom / imgH,
        },
        'species': cls.label.species,
        'freshness': cls.label.freshness,
        'cls_conf': cls.confidence,
        'det_score': d.score,
      });
    }

    // 6) overall label
    perFish.sort(
      (a, b) => (b['cls_conf'] as double).compareTo(a['cls_conf'] as double),
    );
    final top = perFish.first;

    return {
      'latency_ms': sw.elapsedMilliseconds,
      'per_fish': perFish,
      'overall_species': top['species'],
      'overall_freshness': top['freshness'],
      'scan_mode': mode.name,
    };
  }
}
