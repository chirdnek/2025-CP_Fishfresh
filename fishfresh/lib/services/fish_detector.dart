// lib/services/fish_detector.dart
// YOLOv8 TFLite fish detector wrapper

// ignore_for_file: unused_import, unnecessary_null_comparison, unnecessary_cast, unnecessary_import, unnecessary_brace_in_string_interps, unused_element, unintended_html_in_doc_comment

import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import 'fishdet_config.dart';

class FishDetection {
  final Rect box;
  final double score;
  final int classId;

  FishDetection({
    required this.box,
    required this.score,
    required this.classId,
  });
}

class _LetterboxInfo {
  final img.Image image; // size x size
  final double scale;    // gain
  final int padX;
  final int padY;
  _LetterboxInfo({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

_LetterboxInfo _letterbox(img.Image src, int size) {
  final int w = src.width;
  final int h = src.height;

  final double gain = math.min(size / w, size / h);
  final int newW = (w * gain).round();
  final int newH = (h * gain).round();

  final int padX = ((size - newW) / 2).round();
  final int padY = ((size - newH) / 2).round();

  final img.Image resized = img.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );

  final img.Image out = img.Image(width: size, height: size);

  // Padding color 114 like Ultralytics
  img.fill(out, color: img.ColorRgb8(114, 114, 114));

  img.compositeImage(out, resized, dstX: padX, dstY: padY);

  return _LetterboxInfo(image: out, scale: gain, padX: padX, padY: padY);
}


class FishDetector {
  FishDetector._private();
  static final instance = FishDetector._private();

  late FishDetConfig _config;
  Interpreter? _interpreter;
  bool _isInited = false;

  Future<void> ensureInited() async {
    if (_isInited) return;

    // 1. Load config JSON
    _config = await FishDetConfig.load('assets/model/fishdet_config.json');

    // 2. Load interpreter
    try {
      _interpreter = await Interpreter.fromAsset(
        _config.tfliteAsset,
        options: InterpreterOptions()..threads = 2,
      );
      _isInited = true;
    } catch (e) {
      debugPrint('FishDetector: failed to load interpreter: $e');
      _interpreter = null;
      _isInited = false;
    }
  }

  /// Main detection function.
  /// Returns an empty list if:
  ///  - interpreter is not available
  ///  - image cannot be decoded
  ///  - model returns no detections / invalid output
  Future<List<FishDetection>> detect(Uint8List imageBytes) async {
    if (!_isInited || _interpreter == null) {
      await ensureInited();
      if (_interpreter == null) {
        debugPrint('FishDetector: interpreter is null, returning no detections.');
        return [];
      }
    }

    // Decode original image (for original width/height)
    final original = img.decodeImage(imageBytes);
    if (original == null) {
      debugPrint('FishDetector: failed to decode image.');
      return [];
    }
    final origW = original.width;
    final origH = original.height;

    // Letterbox resize (keep aspect ratio + pad) — matches Ultralytics behavior
    final _LetterboxInfo lb = _letterbox(original, _config.inputSize);
    final img.Image resized = lb.image;

    // ---------------- INPUT SHAPE ----------------
    final inTensors = _interpreter!.getInputTensors();
    if (inTensors.isEmpty) {
      debugPrint('FishDetector: no input tensors found.');
      return [];
    }
    final inShape = inTensors[0].shape;
    debugPrint('FishDetector: input shape = $inShape');

    dynamic inputTensor;

    // Case 1: NCHW  [1, 3, H, W]
    if (inShape.length == 4 && inShape[1] == 3) {
      final b = inShape[0], c = inShape[1], h = inShape[2], w = inShape[3];
      if (b != 1 || h != _config.inputSize || w != _config.inputSize) {
        debugPrint('FishDetector: unexpected NCHW input shape $inShape');
        return [];
      }

      inputTensor = List.generate(
        b,
        (_) => List.generate(
          c,
          (ci) => List.generate(
            h,
            (y) => List.generate(
              w,
              (x) {
                final p = resized.getPixel(x, y);
                final r = p.r / 255.0;
                final g = p.g / 255.0;
                final bch = p.b / 255.0;
                if (ci == 0) return r; // R
                if (ci == 1) return g; // G
                return bch;            // B
              },
            ),
          ),
        ),
      );

      debugPrint('FishDetector: built NCHW input tensor.');
    }
    // Case 2: NHWC [1, H, W, 3]
    else if (inShape.length == 4 && inShape[3] == 3) {
      final b = inShape[0], h = inShape[1], w = inShape[2], c = inShape[3];
      if (b != 1 || h != _config.inputSize || w != _config.inputSize || c != 3) {
        debugPrint('FishDetector: unexpected NHWC input shape $inShape');
        return [];
      }

      inputTensor = List.generate(
        b,
        (_) => List.generate(
          h,
          (y) => List.generate(
            w,
            (x) {
              final p = resized.getPixel(x, y);
              return [
                p.r / 255.0,
                p.g / 255.0,
                p.b / 255.0,
              ];
            },
          ),
        ),
      );

      debugPrint('FishDetector: built NHWC input tensor.');
    } else {
      debugPrint('FishDetector: unsupported input shape $inShape');
      return [];
    }

    // ---------------- OUTPUT BUFFER ----------------
    final outTensor = _interpreter!.getOutputTensors()[0];
    final outShape = outTensor.shape; // e.g. [1, 605, 12096]
    debugPrint('FishDetector: output tensor shape = $outShape');

    final output = _allocOutputBuffer(outShape);


    try {
      // Single input, single output
      _interpreter!.run(inputTensor, output);
    } catch (e) {
      debugPrint('FishDetector: run error: $e');
      return [];
    }

    

    // Parse detections
    try {
      final parsed = _parseYolo(output, origW, origH, lb);
      debugPrint(
        'FishDetector: parsed ${parsed.length} detections '
        '(conf >= ${_config.confThreshold}).',
      );
      return parsed;
    } catch (e) {
      debugPrint('FishDetector: parse error: $e');
      return [];
    }
  }

  /// Run YOLO directly on a CameraImage from the preview stream.
  Future<List<FishDetection>> detectFromCameraImage(
    CameraImage cam, {
    int maxSide = 640,
  }) async {
    // 1) Convert preview frame (YUV420) to RGB image
    final img.Image rgb = _yuv420ToImage(cam);

    // 2) Resize to keep YOLO light for live preview
    img.Image work = rgb;
    final int maxDim = rgb.width > rgb.height ? rgb.width : rgb.height;
    if (maxDim > maxSide) {
      final scale = maxSide / maxDim;
      work = img.copyResize(
        rgb,
        width: (rgb.width * scale).round(),
        height: (rgb.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    // 3) Encode to JPG and reuse existing detect(Uint8List bytes)
    final jpgBytes = Uint8List.fromList(img.encodeJpg(work, quality: 80));
    return detect(jpgBytes);
  }

  // YUV420 -> RGB for CameraImage
  img.Image _yuv420ToImage(CameraImage cam) {
    final int width = cam.width;
    final int height = cam.height;

    final img.Image image = img.Image(width: width, height: height);

    final Plane planeY = cam.planes[0];
    final Plane planeU = cam.planes[1];
    final Plane planeV = cam.planes[2];

    for (int y = 0; y < height; y++) {
      final int uvRow = (y ~/ 2) * planeU.bytesPerRow;

      for (int x = 0; x < width; x++) {
        final int uvIndex = uvRow + (x ~/ 2) * (planeU.bytesPerPixel ?? 1);

        final int yp = planeY.bytes[y * planeY.bytesPerRow + x];

        final int up = planeU.bytes[uvIndex];
        final int vp = planeV.bytes[uvIndex];

        final int u = up - 128;
        final int v = vp - 128;

        int r = (yp + 1.370705 * v).round();
        int g = (yp - 0.337633 * u - 0.698001 * v).round();
        int b = (yp + 1.732446 * u).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  /// Allocates a nested List<double> buffer matching the given shape.
  dynamic _allocOutputBuffer(List<int> shape) {
    if (shape.isEmpty) return <double>[];

    dynamic build(int dim, List<int> dims) {
      if (dim == dims.length - 1) {
        // last dimension → list of doubles
        return List<double>.filled(dims[dim], 0.0);
      } else {
        return List.generate(
          dims[dim],
          (_) => build(dim + 1, dims),
        );
      }
    }

    return build(0, shape);
  }
    List<FishDetection> _parseYolo(Object rawOutput, int origW, int origH, _LetterboxInfo lb) {
    if (rawOutput is! List) {
      debugPrint(
          'FishDetector: rawOutput is not a List (got ${rawOutput.runtimeType}).');
      return [];
    }

    final out = rawOutput as List;
    if (out.isEmpty) {
      debugPrint('FishDetector: raw output list is empty.');
      return [];
    }

    // Expect [1, C, N] or [1, N, C] (or without the leading 1)
    List matrix;
    if (out.length == 1 && out.first is List) {
      matrix = out.first as List;
    } else {
      matrix = out;
    }

    if (matrix.isEmpty || matrix.first is! List) {
      debugPrint('FishDetector: output matrix malformed.');
      return [];
    }

    final List<List<double>> m = matrix
        .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
        .toList();

    final int dim0 = m.length;       // either C or N
    final int dim1 = m.first.length; // either N or C

    // Heuristic: channels is usually small (e.g., 605), boxes is large (e.g., 8400)
    final bool cFirst = (dim0 <= 200 && dim1 > 200); // [C][N]
    final int channels = cFirst ? dim0 : dim1;
    final int numBoxes = cFirst ? dim1 : dim0;

    // Access function: value at channel c, box j
    double at(int c, int j) => cFirst ? m[c][j] : m[j][c];

    debugPrint('FishDetector: parsed layout = ${cFirst ? "[C][N]" : "[N][C]"} '
        'channels=$channels, numBoxes=$numBoxes');

    if (channels < 5) {
      debugPrint('FishDetector: channels < 5, cannot parse.');
      return [];
    }

    // YOLOv8 TFLite is typically [x,y,w,h, cls...]
    const int clsOffset = 4;
    final int numClasses = channels - clsOffset;

    if (numClasses <= 0) {
      debugPrint('FishDetector: numClasses <= 0 (channels=$channels).');
      return [];
    }

    if (numBoxes > 0) {
      debugPrint(
        'FishDetector: sample x=${at(0,0)} y=${at(1,0)} w=${at(2,0)} h=${at(3,0)}',
      );
    }


    final List<FishDetection> results = [];
    double globalMaxCls = 0.0;



    for (int j = 0; j < numBoxes; j++) {
      // Normalized coords 0..1 → scale to original image
      final double xRaw = at(0, j);
      final double yRaw = at(1, j);
      final double wRaw = at(2, j);
      final double hRaw = at(3, j);

      if (!xRaw.isFinite || !yRaw.isFinite || !wRaw.isFinite || !hRaw.isFinite) {
        continue;
      }
      if (wRaw <= 0 || hRaw <= 0) continue;

      final double inSize = _config.inputSize.toDouble();

      // Some exports output 0..1, others output pixels (0..inSize).
      final bool isNorm =
          (xRaw <= 1.5 && yRaw <= 1.5 && wRaw <= 1.5 && hRaw <= 1.5);

      final double xcIn = isNorm ? xRaw * inSize : xRaw;
      final double ycIn = isNorm ? yRaw * inSize : yRaw;
      final double wIn  = isNorm ? wRaw * inSize : wRaw;
      final double hIn  = isNorm ? hRaw * inSize : hRaw;


      // undo padding + scale
      final double gain = lb.scale;
      final double xc = (xcIn - lb.padX) / gain;
      final double yc = (ycIn - lb.padY) / gain;
      final double w  = wIn / gain;
      final double h  = hIn / gain;

      // max class score (we treat this as the final confidence)
      double bestCls = 0.0;
      int bestClassIdx = 0;
      for (int c = 0; c < numClasses; c++) {
        final double s = at(clsOffset + c, j);
        if (s > bestCls) {
          bestCls = s;
          bestClassIdx = c;
        }
      }

      if (!bestCls.isFinite) bestCls = 0.0;

      // Track global max for debugging
      if (bestCls > globalMaxCls) globalMaxCls = bestCls;

      // THRESHOLD: use bestCls directly vs confThreshold from config
      if (bestCls < _config.confThreshold) {
        continue;
      }

      // convert to box corners + clamp inside image
      double left = xc - w / 2.0;
      double top  = yc - h / 2.0;
      double right = left + w;
      double bottom = top + h;

      left = left.clamp(0.0, origW.toDouble());
      top = top.clamp(0.0, origH.toDouble());
      right = right.clamp(0.0, origW.toDouble());
      bottom = bottom.clamp(0.0, origH.toDouble());

      if (right <= left || bottom <= top) continue;

      results.add(
        FishDetection(
          box: Rect.fromLTRB(left, top, right, bottom),
          score: bestCls,      // use class score as detection confidence
          classId: bestClassIdx,
        ),
      );
    }

    debugPrint(
      'FishDetector: globalMaxCls=$globalMaxCls, '
      'after parse => ${results.length} boxes above conf ${_config.confThreshold}.',
    );

    // Sort and cap
    results.sort((a, b) => b.score.compareTo(a.score));
    const int maxKeep = 50;
    if (results.length > maxKeep) {
      return results.sublist(0, maxKeep);
    }

    return results;
  }

}