import 'dart:typed_data';
import 'package:camera/camera.dart';

class GuardResult {
  final bool ok;
  final String hint;
  final double brightness;
  final double sharpness;
  final double edgeDensity;
  final double foregroundRatio;

  const GuardResult({
    required this.ok,
    required this.hint,
    required this.brightness,
    required this.sharpness,
    required this.edgeDensity,
    required this.foregroundRatio,
  });
}

class PreprocessGuard {
  // ---- Tunable thresholds (start here, tweak from field tests) ----
  double minBrightness = 40;     // 0..255 mean
  double maxBrightness = 210;
  double minSharpness  = 60;     // variance of Laplacian
  double minEdgeRatio  = 0.020;  // 2% pixels exceeding gradient threshold
  double minFgRatio    = 0.12;   // 12% “object” area

  // Gradient threshold for edge density (0..255 scale of |gx|+|gy|)
  int edgeGradThreshold = 40;

  /// Evaluate a frame from CameraImage (use planes[0] = Y/luma).
  /// Returns GuardResult with metrics + hint.
  GuardResult evaluateFromCameraImage(CameraImage img) {
    final y = img.planes.first;
    final gray = _extractGrayscaleY(y, img.width, img.height);
    return evaluate(gray, img.width, img.height);
  }

  /// Evaluate raw grayscale bytes (width*height).
  GuardResult evaluate(Uint8List gray, int width, int height) {
    final mean = _mean(gray);
    if (mean < minBrightness) {
      return GuardResult(
        ok: false, hint: 'Too dark—add light or move closer',
        brightness: mean, sharpness: 0, edgeDensity: 0, foregroundRatio: 0,
      );
    }
    if (mean > maxBrightness) {
      return GuardResult(
        ok: false, hint: 'Too bright—reduce glare / tilt phone',
        brightness: mean, sharpness: 0, edgeDensity: 0, foregroundRatio: 0,
      );
    }

    final varLap = _varianceOfLaplacian(gray, width, height);
    if (varLap < minSharpness) {
      return GuardResult(
        ok: false, hint: 'Blurry—hold steady and refocus',
        brightness: mean, sharpness: varLap, edgeDensity: 0, foregroundRatio: 0,
      );
    }

    final edgeRatio = _edgeDensity(gray, width, height, edgeGradThreshold);
    if (edgeRatio < minEdgeRatio) {
      return GuardResult(
        ok: false, hint: 'Not enough structure—move closer / reduce reflections',
        brightness: mean, sharpness: varLap, edgeDensity: edgeRatio, foregroundRatio: 0,
      );
    }

    // Foreground ratio (simple threshold around mean)
    final fg = _foregroundRatio(gray, width, height, mean);
    if (fg < minFgRatio) {
      return GuardResult(
        ok: false, hint: 'Fish not centered—fill more of the frame',
        brightness: mean, sharpness: varLap, edgeDensity: edgeRatio, foregroundRatio: fg,
      );
    }

 return GuardResult(
  ok: true,
  hint: 'Framing looks good — tap the shutter',
  brightness: mean,
  sharpness: varLap,
  edgeDensity: edgeRatio,
  foregroundRatio: fg,
);
  }

  // --------- Low-level helpers (fast, no allocations beyond output) ----------

  Uint8List _extractGrayscaleY(Plane yPlane, int w, int h) {
    if (yPlane.bytesPerRow == w) return yPlane.bytes; // fast path
    final out = Uint8List(w * h);
    final src = yPlane.bytes;
    int dstOff = 0, srcOff = 0;
    for (int r = 0; r < h; r++) {
      out.setRange(dstOff, dstOff + w, src.sublist(srcOff, srcOff + w));
      dstOff += w;
      srcOff += yPlane.bytesPerRow;
    }
    return out;
  }

  double _mean(Uint8List buf) {
    int s = 0;
    for (final v in buf) { s += v; }
    return s / buf.length;
  }

  // 3x3 Laplacian kernel: [0 1 0; 1 -4 1; 0 1 0]
  double _varianceOfLaplacian(Uint8List g, int w, int h) {
    double sum = 0, sumSq = 0;
    int count = 0;
    for (int y = 1; y < h - 1; y++) {
      int row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final c  = g[row + x];
        final up = g[row - w + x];
        final dn = g[row + w + x];
        final le = g[row + x - 1];
        final ri = g[row + x + 1];
        final l  = (up + dn + le + ri) - (4 * c);
        sum   += l;
        sumSq += (l * l);
        count++;
      }
    }
    final m = sum / count;
    return (sumSq / count) - (m * m);
  }

  // Cheap Sobel magnitude ≈ |gx| + |gy|; returns ratio of pixels above threshold.
  double _edgeDensity(Uint8List g, int w, int h, int thr) {
    int edges = 0, total = 0;
    for (int y = 1; y < h - 1; y++) {
      final row = y * w;
      for (int x = 1; x < w - 1; x++) {
        // Sobel X
        final gx =
            - g[row - w + (x - 1)] - 2 * g[row + (x - 1)] - g[row + w + (x - 1)]
            + g[row - w + (x + 1)] + 2 * g[row + (x + 1)] + g[row + w + (x + 1)];
        // Sobel Y
        final gy =
            - g[row - w + (x - 1)] - 2 * g[row - w + x] - g[row - w + (x + 1)]
            + g[row + w + (x - 1)] + 2 * g[row + w + x] + g[row + w + (x + 1)];

        final mag = (gx.abs() + gy.abs()); // L1 norm, faster than sqrt(gx^2+gy^2)
        if (mag > thr) edges++;
        total++;
      }
    }
    return edges / total;
  }

  // Simple foreground via mean threshold (adaptive-ish, very cheap)
  double _foregroundRatio(Uint8List g, int w, int h, double mean) {
    int nz = 0, n = g.length;
    final t = mean.toInt().clamp(0, 255);
    for (int i = 0; i < n; i++) {
      if (g[i] > t) nz++;
    }
    return nz / n;
  }
}
