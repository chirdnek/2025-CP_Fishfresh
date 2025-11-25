// ignore_for_file: unused_import, curly_braces_in_flow_control_structures, non_constant_identifier_names

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:image/image.dart' as img;


class ImageService {
  // ============================================================
  // 1) PROFILE: pick & save locally (used in profile_settings.dart)
  // ============================================================
  static Future<String?> pickAndSaveImageLocally() async {
    final picker = ImagePicker();

    // Step 1: Pick image from gallery
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return null;

    // Step 2: Get app's document directory
    final Directory appDir = await getApplicationDocumentsDirectory();

    // Step 3: Create a unique filename
    final String fileName =
        'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Step 4: Create the full file path
    final String savedImagePath = join(appDir.path, fileName);

    // Step 5: Copy the picked image to the app directory
    await File(pickedFile.path).copy(savedImagePath);

    // Step 6: Return the new local path
    return savedImagePath;
  }

  // ============================================================
  // 2) CAPTURE QA + LIGHT NORMALIZATION (for fish scanning)
  // ============================================================

  /// Fallback Laplacian variance (no OpenCV required)
  static double blurScoreVarianceOfLaplacian_Fallback(
      Uint8List rgba, int w, int h,
      {int step = 2}) {
    final sw = (w ~/ step);
    final sh = (h ~/ step);
    final g = Uint8List(sw * sh);

    int p = 0, q = 0;
    for (int y = 0; y < h; y += step) {
      p = (y * w * 4);
      for (int x = 0; x < w; x += step) {
        final r = rgba[p], gch = rgba[p + 1], b = rgba[p + 2];
        final y8 = ((0.299 * r + 0.587 * gch + 0.114 * b)).round();
        g[q++] = y8;
        p += 4 * step;
      }
    }

    // 3x3 Laplacian kernel
    const k = [-1, -1, -1, -1, 8, -1, -1, -1, -1];
    final lap = Float32List(sw * sh);

    int idx(int x, int y) => y * sw + x;
    for (int y = 1; y < sh - 1; y++) {
      for (int x = 1; x < sw - 1; x++) {
        double s = 0;
        int t = 0;
        for (int j = -1; j <= 1; j++) {
          for (int i2 = -1; i2 <= 1; i2++) {
            s += k[t++] * g[idx(x + i2, y + j)];
          }
        }
        lap[idx(x, y)] = s;
      }
    }

    double sum = 0, sum2 = 0;
    final n = (sw - 2) * (sh - 2);
    for (int y = 1; y < sh - 1; y++) {
      for (int x = 1; x < sw - 1; x++) {
        final v = lap[idx(x, y)];
        sum += v;
        sum2 += v * v;
      }
    }
    final mean = sum / n;
    return (sum2 / n) - mean * mean;
  }

  /// Simple global histogram equalization fallback (helps with low-light)
  static Uint8List equalizeBrightnessFallback(Uint8List rgba, int w, int h) {
    final ycbcr = _rgbaToYCbCr(rgba, w, h);
    final y = ycbcr.y;
    _equalizeHistInPlace(y);
    return _yCbCrToRgba(ycbcr.y, ycbcr.cb, ycbcr.cr, w, h);
  }

  // ============================================================
  // 3) Internal helpers for fallback equalization
  // ============================================================

  static _YCbCr _rgbaToYCbCr(Uint8List rgba, int w, int h) {
    final n = w * h;
    final y = Uint8List(n), cb = Uint8List(n), cr = Uint8List(n);
    int p = 0;
    for (int i = 0; i < n; i++) {
      final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
      final yy = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
      final u = (-0.169 * r - 0.331 * g + 0.500 * b + 128).round().clamp(0, 255);
      final v = (0.500 * r - 0.419 * g - 0.081 * b + 128).round().clamp(0, 255);
      y[i] = yy;
      cb[i] = u;
      cr[i] = v;
      p += 4;
    }
    return _YCbCr(y, cb, cr);
  }

  static Uint8List _yCbCrToRgba(
      Uint8List y, Uint8List cb, Uint8List cr, int w, int h) {
    final out = Uint8List(w * h * 4);
    int p = 0;
    for (int i = 0; i < y.length; i++) {
      final Y = y[i].toDouble();
      final U = cb[i].toDouble() - 128;
      final V = cr[i].toDouble() - 128;
      int r = (Y + 1.402 * V).round();
      int g = (Y - 0.344136 * U - 0.714136 * V).round();
      int b = (Y + 1.772 * U).round();
      out[p] = r.clamp(0, 255);
      out[p + 1] = g.clamp(0, 255);
      out[p + 2] = b.clamp(0, 255);
      out[p + 3] = 255;
      p += 4;
    }
    return out;
  }

  static void _equalizeHistInPlace(Uint8List y) {
    final hist = List<int>.filled(256, 0);
    for (final v in y) hist[v]++;
    final cdf = List<int>.filled(256, 0);
    int cum = 0;
    for (int i = 0; i < 256; i++) {
      cum += hist[i];
      cdf[i] = cum;
    }
    final n = y.length;
    final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);
    for (int i = 0; i < n; i++) {
      final v = y[i];
      final eq =
          ((cdf[v] - cdfMin) * 255.0 / (n - cdfMin)).clamp(0, 255).round();
      y[i] = eq;
    }
  }
}

class _YCbCr {
  final Uint8List y, cb, cr;
  _YCbCr(this.y, this.cb, this.cr);
}
