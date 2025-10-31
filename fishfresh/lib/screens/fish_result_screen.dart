// lib/screens/fish_result_screen.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use, unintended_html_in_doc_comment, unnecessary_nullable_for_final_variable_declarations, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'fish_scan_camera.dart';

class FishResultScreen extends StatelessWidget {
  /// Front and back captured/scanned images
  final String frontImagePath;
  final String backImagePath;

  /// Species slug (e.g., "mackerel_scad") and freshness ("Fresh"/"Not Fresh")
  final String species;
  final String freshnessLabel;

  /// Optional: runtime result map from predictor
  final Map<String, dynamic>? result;

  const FishResultScreen({
    required this.frontImagePath,
    required this.backImagePath,
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

  Color _freshnessBg(String f) {
    switch (f) {
      case 'Fresh':
        return Colors.green.shade700;
      case 'Not Fresh':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('MMMM d, yyyy • h:mm a').format(DateTime.now());
    final speciesPretty = _titleCase(species);
    final chipColor = _freshnessBg(freshnessLabel);

    final double? topConfidence = _asDouble(result?['confidence']);
    final Map<String, dynamic>? freshnessScores =
        (result?['freshness_scores'] is Map<String, dynamic>)
            ? (result!['freshness_scores'] as Map<String, dynamic>)
            : null;
    final Map<String, dynamic>? speciesScores =
        (result?['species_scores'] is Map<String, dynamic>)
            ? (result!['species_scores'] as Map<String, dynamic>)
            : null;

    final int? latencyMs = _asInt(result?['latency_ms']);
    final List<dynamic> topk =
        (result?['topk'] is List) ? (result!['topk'] as List) : const [];

    return Scaffold(
      backgroundColor: const Color(0xFF0E1F17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Single-model: no dynamic title
        title: const Text('Result', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // ── Front and Back images ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _imageTile(frontImagePath, 'Front'),
                  const SizedBox(width: 12),
                  _imageTile(backImagePath, 'Back'),
                ],
              ),

              const SizedBox(height: 20),

              // Freshness main label
              Text(
                freshnessLabel,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              // Species chip
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  speciesPretty,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Latency chip only (no model chip)
              if (latencyMs != null)
                Chip(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  avatar: const Icon(Icons.speed, color: Colors.white70, size: 18),
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

              // Model Summary
              if (topConfidence != null ||
                  freshnessScores != null ||
                  (speciesScores != null && speciesScores.isNotEmpty) ||
                  topk.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
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
                      const SizedBox(height: 12),
                      if (topConfidence != null)
                        Text(
                          "Top class confidence: ${(topConfidence * 100).toStringAsFixed(1)}%",
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      if (freshnessScores != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Freshness scores →  Fresh: "
                          "${(_asDouble(freshnessScores['Fresh']) * 100).toStringAsFixed(1)}%   "
                          "Not Fresh: "
                          "${(_asDouble(freshnessScores['Not Fresh']) * 100).toStringAsFixed(1)}%",
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                      if (speciesScores != null && speciesScores.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._topSpeciesLines(speciesScores, species),
                      ],
                      if (topk.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text("Top-K classes:",
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        ...topk.take(5).map((e) {
                          final label =
                              (e is Map && e['label'] is String) ? e['label'] as String : '';
                          final prob = (e is Map) ? _asDouble(e['prob']) : 0.0;
                          return Text(
                            "• ${_titleCase(label)} — ${(prob * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          );
                        }),
                      ],
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

  /// Helper to show labeled images side by side
  Widget _imageTile(String path, String label) {
    final exists = File(path).existsSync();
    final img = exists
        ? FileImage(File(path))
        : const AssetImage("assets/images/fallback.png") as ImageProvider;
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image(image: img, fit: BoxFit.cover),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Species lines
  List<Widget> _topSpeciesLines(
      Map<String, dynamic> speciesScores, String predictedRaw) {
    final entries = speciesScores.entries
        .map((e) => MapEntry(e.key, _asDouble(e.value)))
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    final idx = entries.indexWhere((e) => e.key == predictedRaw);
    if (idx > 0) {
      final hit = entries.removeAt(idx);
      entries.insert(0, hit);
    }
    return entries.take(3).map((e) {
      return Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          "• ${_titleCase(e.key)}: ${(e.value * 100).toStringAsFixed(1)}%",
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }).toList();
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
}
