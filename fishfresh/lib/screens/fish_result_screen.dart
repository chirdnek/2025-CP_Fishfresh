// lib/screens/fish_result_screen.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use, unintended_html_in_doc_comment, unnecessary_nullable_for_final_variable_declarations, use_build_context_synchronously, unused_element, unnecessary_brace_in_string_interps

import 'dart:io';
import 'dart:ui' as ui show Rect;
import 'package:image/image.dart' as img; 
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fish_scan_camera.dart';
import 'package:camera/camera.dart';

class FishResultScreen extends StatelessWidget {
  /// Single captured/scanned image
  final String imagePath;

  /// Overall species and freshness coming from caller (used as fallback only)
  final String species;
  final String freshnessLabel;

  /// Full pipeline result map (per_fish, latency_ms, etc.)
  final Map<String, dynamic>? result;

  const FishResultScreen({
    required this.imagePath,
    required this.species,
    required this.freshnessLabel,
    this.result,
  });

  // ---- helpers ----

  String _titleCase(String s) {
    return s
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }

  /// From raw classifier label like "fresh__bigeye_scad" or "not_fresh__indian_mackerel"
  /// → "fresh" / "not fresh" / "".
  String _extractFreshness(String raw) {
    String v = raw.toLowerCase().trim();

    // canonical format: fresh__*, not_fresh__*
    if (v.startsWith('fresh__')) return 'fresh';
    if (v.startsWith('not_fresh__')) return 'not fresh';

    // fallback for old formats: "Fresh Bigeye Scad", "Not Fresh Bigeye Scad"
    if (v.contains('not') && v.contains('fresh')) return 'not fresh';
    if (v.contains('fresh')) return 'fresh';

    return '';
  }

  /// From raw classifier label like "fresh__bigeye_scad"
  /// or "not_fresh__indian_mackerel" or "Fresh Bigeye Scad"
  /// → "bigeye scad", "indian mackerel", etc.
  String _extractSpecies(String raw) {
    String v = raw.toLowerCase().trim();

    // if "__" format, drop freshness prefix
    if (v.contains('__')) {
      v = v.split('__').last;
    } else {
      // old "Fresh Bigeye Scad" style: remove freshness words
      v = v.replaceAll(RegExp(r'\bnot\s*fresh\b'), '');
      v = v.replaceAll(RegExp(r'\bfresh\b'), '');
    }

    v = v.replaceAll('_', ' ').trim();
    return v;
  }

  /// Decide canonical freshness for one fish map from per_fish.
  /// Prefers the explicit "freshness" field; falls back to "species" label.
  String _canonicalFreshness(Map<String, dynamic> f) {
    final String freshnessField =
        _extractFreshness((f['freshness'] ?? '').toString());
    if (freshnessField == 'fresh' || freshnessField == 'not fresh') {
      return freshnessField;
    }

    final String fromSpecies =
        _extractFreshness((f['species'] ?? '').toString());
    if (fromSpecies == 'fresh' || fromSpecies == 'not fresh') {
      return fromSpecies;
    }

    return ''; // unknown
  }

  Color _freshnessBg() {
    // we color the chip based on majority freshness if we have data
    final List<dynamic> perFishRaw =
        (result?['per_fish'] is List) ? (result!['per_fish'] as List) : const [];
    final List<Map<String, dynamic>> perFish =
        perFishRaw.map((e) => (e as Map).cast<String, dynamic>()).toList();

    if (perFish.isEmpty) {
      // fallback to the single freshnessLabel
      switch (freshnessLabel) {
        case 'Fresh':
          return Colors.green.shade700;
        case 'Not Fresh':
          return Colors.red.shade700;
        default:
          return Colors.grey.shade700;
      }
    }

    final int freshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'fresh').length;
    final int notFreshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'not fresh').length;

    if (freshCount > notFreshCount) {
      return Colors.green.shade700;
    } else if (notFreshCount > freshCount) {
      return Colors.red.shade700;
    } else {
      return Colors.grey.shade700;
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Decode boxes from per_fish[].box_norm (0–1) into normalized Rects.
  List<ui.Rect> _boxesFromPerFish(List<Map<String, dynamic>> perFish) {
    final boxes = <ui.Rect>[];
    for (final f in perFish) {
      final m = f['box_norm'];
      if (m is! Map) continue;

      final l = (m['left'] as num?)?.toDouble();
      final t = (m['top'] as num?)?.toDouble();
      final r = (m['right'] as num?)?.toDouble();
      final b = (m['bottom'] as num?)?.toDouble();
      if (l != null && t != null && r != null && b != null) {
        boxes.add(ui.Rect.fromLTRB(l, t, r, b));
      }
    }
    return boxes;
  }

  /// Main image widget with optional multiple bounding boxes overlay.
   /// Main image widget with optional multiple bounding boxes overlay.
  /// We:
  ///  1) decode the image to get true width/height
  ///  2) build a SizedBox with that exact size
  ///  3) draw the Image + CustomPaint in the same coordinate system
  ///  4) wrap everything in FittedBox(BoxFit.contain) so it scales nicely
  Widget _imageWithBoxes(String path, List<ui.Rect> normBoxes) {
    final file = File(path);
    if (!file.existsSync()) {
      final imgProvider =
          const AssetImage("assets/images/fallback.png") as ImageProvider;

      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Image(image: imgProvider, fit: BoxFit.contain),
      );
    }

    // Read image bytes once to get true width/height
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // fallback if decode fails
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.file(file, fit: BoxFit.contain),
      );
    }

    final double imgW = decoded.width.toDouble();
    final double imgH = decoded.height.toDouble();

    // Convert normalized boxes (0..1) to pixel coords in ORIGINAL image space
    final pixelRects = normBoxes
        .map(
          (nb) => ui.Rect.fromLTRB(
            nb.left * imgW,
            nb.top * imgH,
            nb.right * imgW,
            nb.bottom * imgH,
          ),
        )
        .toList();

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: imgW,
          height: imgH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Draw the raw image exactly at its native aspect ratio
              Image.file(
                file,
                fit: BoxFit.fill, // <-- 1:1 with SizedBox (no extra cropping)
              ),
              if (pixelRects.isNotEmpty)
                CustomPaint(
                  painter: _MultiBoxPainter(pixelRects),
                ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final now = DateFormat('MMMM d, yyyy • h:mm a').format(DateTime.now());

    // latency
    final int? latencyMs = _asInt(result?['latency_ms']);

    // per-fish info from pipeline
    final List<dynamic> perFishRaw =
        (result?['per_fish'] is List) ? (result!['per_fish'] as List) : const [];
    final List<Map<String, dynamic>> perFish =
        perFishRaw.map((e) => (e as Map).cast<String, dynamic>()).toList();

    final int numFish = perFish.length;

    // counts for Fresh / Not Fresh
    final int freshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'fresh').length;
    final int notFreshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'not fresh').length;

    // species counts map: { "  scad": 3, "indian mackerel": 1, ... }
    final Map<String, int> speciesCounts = {};
    for (final f in perFish) {
      final rawLabel = (f['species'] ?? '').toString();
      final key = _extractSpecies(rawLabel);
      if (key.isEmpty) continue;
      speciesCounts[key] = (speciesCounts[key] ?? 0) + 1;
    }

    // freshness summary text (this replaces "Fresh Bigeye Scad")
    String freshnessSummary;
    if (numFish > 0) {
      // e.g. "3 Fresh, 0 Not Fresh"
      freshnessSummary = '$freshCount Fresh, $notFreshCount Not Fresh';
    } else {
      // fallback for single detection case with no per_fish
      freshnessSummary = freshnessLabel;
    }

    // species summary text, e.g. "3 Bigeye Scad" or "2 Bigeye Scad, 1 Indian Mackerel"
    String speciesSummary;
    if (speciesCounts.isNotEmpty) {
      final parts = <String>[];
      speciesCounts.forEach((slug, count) {
        parts.add('$count ${_titleCase(slug)}');
      });
      speciesSummary = parts.join(', ');
    } else {
      speciesSummary = _titleCase(species);
    }

    // per-box confidences
    final List<Widget> perBoxLines = [];
    for (int i = 0; i < perFish.length; i++) {
      final f = perFish[i];

      final rawLabel = (f['species'] ?? '').toString();
      final sp = _titleCase(_extractSpecies(rawLabel));

      final canonical = _canonicalFreshness(f);
      String frText;
      if (canonical == 'fresh') {
        frText = 'Fresh';
      } else if (canonical == 'not fresh') {
        frText = 'Not Fresh';
      } else {
        frText = (f['freshness'] ?? '').toString();
      }

      final conf = _asDouble(f['cls_conf']) * 100.0;

      perBoxLines.add(
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '• Fish #${i + 1}: $sp – $frText '
            '(${conf.toStringAsFixed(1)}%)',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }

    // detection boxes (normalized) for overlay – from per_fish.box_norm
    final List<ui.Rect> normBoxes = _boxesFromPerFish(perFish);

    final chipColor = _freshnessBg();

    return Scaffold(
      backgroundColor: const Color(0xFF0E1F17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Result', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // ── Image with bounding boxes ──
              _imageWithBoxes(imagePath, normBoxes),

              const SizedBox(height: 20),

              // Freshness summary: e.g. "3 Fresh, 0 Not Fresh"
              Text(
                freshnessSummary,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              // Species chip: e.g. "3 Bigeye Scad" or "2 Bigeye Scad, 1 Indian Mackerel"
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  speciesSummary,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Latency chip (if present)
              if (latencyMs != null)
                Chip(
                  backgroundColor:
                      Colors.white.withValues(alpha: 0.08), // no withOpacity
                  avatar:
                      const Icon(Icons.speed, color: Colors.white70, size: 18),
                  label: Text(
                    '$latencyMs ms',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),

              const SizedBox(height: 12),

              Text(
                now,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // ── Model Summary ──
              if (numFish > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Model Summary",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Detections: $numFish fish "
                        "(Fresh: $freshCount, Not Fresh: $notFreshCount)",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Species: $speciesSummary",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      ...perBoxLines, // one line per bounding box / fish
                    ],
                  ),
                ),

              const SizedBox(height: 30),

              // Buttons
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade400,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text(
                  "Scan Again",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final cameras = await availableCameras();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FishScanCamera(cameras: cameras),
                    ),
                  );
                },
              ),
              const SizedBox(height: 15),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  "Done",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter that draws multiple rounded bounding boxes
/// (rects are already in pixel coords of the widget)
class _MultiBoxPainter extends CustomPainter {
  final List<ui.Rect> rects;
  _MultiBoxPainter(this.rects);

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF00E676); // green accent

    for (final r in rects) {
      final rrect = RRect.fromRectAndRadius(r, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MultiBoxPainter oldDelegate) =>
      oldDelegate.rects != rects;
}
