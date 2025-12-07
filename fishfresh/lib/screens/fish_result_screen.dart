// lib/screens/fish_result_screen.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use, unintended_html_in_doc_comment, unnecessary_nullable_for_final_variable_declarations, use_build_context_synchronously, unused_element, unnecessary_brace_in_string_interps, unnecessary_to_list_in_spreads

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fish_scan_camera.dart';
import 'package:camera/camera.dart';

// PDF + printing
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  /// Small view-model for each box: normalized rect + ID + freshness
  List<_BoxVisual> _boxesFromPerFish(List<Map<String, dynamic>> perFish) {
    final boxes = <_BoxVisual>[];
    for (final f in perFish) {
      final m = f['box_norm'];
      if (m is! Map) continue;

      final l = (m['left'] as num?)?.toDouble();
      final t = (m['top'] as num?)?.toDouble();
      final r = (m['right'] as num?)?.toDouble();
      final b = (m['bottom'] as num?)?.toDouble();
      if (l == null || t == null || r == null || b == null) continue;

      final id = _asInt(f['fish_box_id']) ?? (boxes.length + 1);
      final freshness = _canonicalFreshness(f);

      boxes.add(
        _BoxVisual(
          normRect: ui.Rect.fromLTRB(l, t, r, b),
          id: id,
          freshness: freshness,
        ),
      );
    }
    return boxes;
  }

  /// Main image widget with optional multiple bounding boxes overlay.
  /// We:
  ///  1) decode the image to get true width/height
  ///  2) build a SizedBox with that exact size
  ///  3) draw the Image + CustomPaint in the same coordinate system
  ///  4) wrap everything in FittedBox(BoxFit.contain) so it scales nicely
  Widget _imageWithBoxes(String path, List<_BoxVisual> boxes) {
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
                fit: BoxFit.fill, // 1:1 with SizedBox (no extra cropping)
              ),
              if (boxes.isNotEmpty)
                CustomPaint(
                  painter: _MultiBoxPainter(boxes),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== PDF / PRINT HELPERS =====================

  Future<Uint8List> _buildReportPdf() async {
    final pdf = pw.Document();
    final now = DateFormat('MMMM d, yyyy • h:mm a').format(DateTime.now());

    // Extract per-fish info (same logic as in build)
    final List<dynamic> perFishRaw =
        (result?['per_fish'] is List) ? (result!['per_fish'] as List) : const [];
    final List<Map<String, dynamic>> perFish =
        perFishRaw.map((e) => (e as Map).cast<String, dynamic>()).toList();

    final int numFish = perFish.length;
    final int freshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'fresh').length;
    final int notFreshCount =
        perFish.where((f) => _canonicalFreshness(f) == 'not fresh').length;

    // Species counts
    final Map<String, int> speciesCounts = {};
    for (final f in perFish) {
      final rawLabel = (f['species'] ?? '').toString();
      final key = _extractSpecies(rawLabel);
      if (key.isEmpty) continue;
      speciesCounts[key] = (speciesCounts[key] ?? 0) + 1;
    }

    String freshnessSummary;
    if (numFish > 0) {
      freshnessSummary = '$freshCount Fresh, $notFreshCount Not Fresh';
    } else {
      freshnessSummary = freshnessLabel;
    }

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

    final int? latencyMs = _asInt(result?['latency_ms']);

    // Load image for PDF (if available)
    pw.ImageProvider? pdfImage;
    final file = File(imagePath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      pdfImage = pw.MemoryImage(bytes);
    }

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FishFresh Scan Report',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    now,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              if (latencyMs != null)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Inference latency',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '$latencyMs ms',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),

      if (pdfImage != null)
  pw.Container(
    height: 250,
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(width: 0.5),
    ),
    child: pw.ClipRRect(
      horizontalRadius: 8,
      verticalRadius: 8,
      child: pw.Image(
        pdfImage,
        fit: pw.BoxFit.contain,
      ),
    ),
  ),
if (pdfImage != null) pw.SizedBox(height: 16),


          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Bullet(
            text: 'Overall freshness: $freshnessSummary',
          ),
          pw.Bullet(
            text: 'Detected species: $speciesSummary',
          ),
          if (numFish > 0)
            pw.Bullet(
              text: 'Number of detected fish: $numFish',
            ),
          pw.SizedBox(height: 16),

          if (numFish > 0)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Model Summary (Per Fish)',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...perFish.map((f) {
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
                  final id = _asInt(f['fish_box_id']) ?? 0;

                  return pw.Bullet(
                    text:
                        'Fish #$id: $sp – $frText (${conf.toStringAsFixed(1)}%)',
                  );
                }).toList(),
              ],
            ),

          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated by FishFresh',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _exportPdf(BuildContext context) async {
    try {
      final bytes = await _buildReportPdf();
      final fileName =
          'FishFresh_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      await Printing.sharePdf(
        bytes: bytes,
        filename: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export PDF: $e')),
        );
      }
    }
  }

  Future<void> _printReport(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (format) async => _buildReportPdf(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e')),
        );
      }
    }
  }

  void _exitToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ===================== UI BUILD =====================

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

    // species counts map
    final Map<String, int> speciesCounts = {};
    for (final f in perFish) {
      final rawLabel = (f['species'] ?? '').toString();
      final key = _extractSpecies(rawLabel);
      if (key.isEmpty) continue;
      speciesCounts[key] = (speciesCounts[key] ?? 0) + 1;
    }

    // freshness summary text
    String freshnessSummary;
    if (numFish > 0) {
      freshnessSummary = '$freshCount Fresh, $notFreshCount Not Fresh';
    } else {
      freshnessSummary = freshnessLabel;
    }

    // species summary text
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
      final id = _asInt(f['fish_box_id']) ?? (i + 1);

      perBoxLines.add(
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '• Fish #$id: $sp – $frText '
            '(${conf.toStringAsFixed(1)}%)',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }

    // boxes for overlay – from per_fish.box_norm + fish_box_id + freshness
    final List<_BoxVisual> boxes = _boxesFromPerFish(perFish);

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
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'pdf') {
                await _exportPdf(context); // Print as PDF / share
              } else if (value == 'print') {
                await _printReport(context); // Direct print dialog
              } else if (value == 'exit') {
                _exitToHome(context); // Exit to home/root
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Text('Print as PDF'),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Text('Print directly'),
              ),
              const PopupMenuItem(
                value: 'exit',
                child: Text('Exit to Home'),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // ── Image with bounding boxes ──
              _imageWithBoxes(imagePath, boxes),

              const SizedBox(height: 20),

              // Freshness summary
              Text(
                freshnessSummary,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              // Species chip
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
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
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
                      ...perBoxLines,
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

/// View-model for drawing each box
class _BoxVisual {
  final ui.Rect normRect;   // normalized 0..1 rect from pipeline
  final int id;             // fish_box_id
  final String freshness;   // 'fresh' | 'not fresh' | ''

  const _BoxVisual({
    required this.normRect,
    required this.id,
    required this.freshness,
  });
}

/// Painter that draws multiple bounding boxes with labels:
///  - Green for Fresh, Red for Not Fresh
///  - "Fish #<id>" at the top-left of each box
class _MultiBoxPainter extends CustomPainter {
  final List<_BoxVisual> boxes;
  _MultiBoxPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;

    for (final b in boxes) {
      // Convert normalized rect to pixel rect in this canvas size
      final rect = Rect.fromLTRB(
        b.normRect.left * size.width,
        b.normRect.top * size.height,
        b.normRect.right * size.width,
        b.normRect.bottom * size.height,
      );

      final bool isNotFresh = b.freshness == 'not fresh';

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = isNotFresh ? Colors.redAccent : const Color(0xFF00E676);

      // Draw rounded rectangle
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);

      // Draw "Fish #id" at top-left of the box
      final textSpan = TextSpan(
        text: 'Fish #${b.id}',
        style: TextStyle(
          color: isNotFresh ? Colors.redAccent : const Color(0xFF00E676),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();

      const double padding = 2.0;
      final offset = Offset(rect.left + padding, rect.top + padding);
      tp.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant _MultiBoxPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
