// lib/screens/fish_result_screen.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use, unintended_html_in_doc_comment

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fish_scan_camera.dart';
import 'package:camera/camera.dart';

class FishResultScreen extends StatelessWidget {
  /// REQUIRED: path to the captured/scanned image
  final String imagePath;

  /// REQUIRED: separate labels
  /// - species: e.g., "mackerel_scad"
  /// - freshnessLabel: "Fresh" or "Not Fresh"
  final String species;
  final String freshnessLabel;

  /// OPTIONAL: result map from predictor to show extra info (confidence/scores)
  /// Keys (if provided):
  ///  - "confidence": double
  ///  - "freshness_scores": {"Fresh": double, "Not Fresh": double}
  ///  - "species_scores": { "<species>": double, ... }
  final Map<String, dynamic>? result;

  const FishResultScreen({
    super.key,
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
        .map((w) => w[0].toUpperCase() + w.substring(1))
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

    final double? topConfidence = (result?['confidence'] is num)
        ? (result!['confidence'] as num).toDouble()
        : null;
    final Map<String, dynamic>? freshnessScores =
        (result?['freshness_scores'] is Map<String, dynamic>)
            ? (result!['freshness_scores'] as Map<String, dynamic>)
            : null;
    final Map<String, dynamic>? speciesScores =
        (result?['species_scores'] is Map<String, dynamic>)
            ? (result!['species_scores'] as Map<String, dynamic>)
            : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1F17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Image circle + logo
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 110,
                    backgroundColor: Colors.grey.shade800,
                    backgroundImage: File(imagePath).existsSync()
                        ? FileImage(File(imagePath))
                        : const AssetImage("assets/images/fallback.png")
                            as ImageProvider,
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Image.asset(
                      "assets/images/logo1.png",
                      width: 45,
                      height: 45,
                    ),
                  ),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
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

              const SizedBox(height: 20),

              // Timestamp
              Text(
                now,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // Optional: Model summary if result is provided
              if (topConfidence != null ||
                  freshnessScores != null ||
                  (speciesScores != null && speciesScores.isNotEmpty))
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
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      if (freshnessScores != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Freshness scores →  Fresh: "
                          "${(((freshnessScores['Fresh'] ?? 0.0) as num).toDouble() * 100).toStringAsFixed(1)}%   "
                          "Not Fresh: "
                          "${(((freshnessScores['Not Fresh'] ?? 0.0) as num).toDouble() * 100).toStringAsFixed(1)}%",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                      if (speciesScores != null && speciesScores.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _topSpeciesLines(speciesScores, species),
                          ),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Static heuristics (optional)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Fish Analysis (Heuristics)",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      "- Eye clarity: Clear and bright\n"
                      "- Gills color: Reddish\n"
                      "- Scales: Shiny and intact\n"
                      "- Odor: Neutral (AI simulated)",
                      style: TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Scan Again
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

              // Done
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

  /// Build UI lines for top-3 species (by probability), with the predicted species highlighted first if present.
  List<Widget> _topSpeciesLines(
      Map<String, dynamic> speciesScores, String predictedRaw) {
    final entries = speciesScores.entries
        .map((e) => MapEntry(e.key, (e.value as num).toDouble()))
        .toList();

    entries.sort((a, b) => b.value.compareTo(a.value));

    final idx = entries.indexWhere((e) => e.key == predictedRaw);
    if (idx > 0) {
      final hit = entries.removeAt(idx);
      entries.insert(0, hit);
    }

    final top = entries.take(3).toList();

    return top
        .map(
          (e) => Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              "• ${_titleCase(e.key)}: ${(e.value * 100).toStringAsFixed(1)}%",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        )
        .toList();
  }
}
