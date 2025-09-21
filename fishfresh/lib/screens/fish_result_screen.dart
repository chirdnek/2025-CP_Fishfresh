// lib/screens/fish_result_screen.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fish_scan_camera.dart'; // ✅ for "Scan Again"

class FishResultScreen extends StatelessWidget {
  final String imagePath;
  final String species;
  final String freshnessLabel;

  const FishResultScreen({
    super.key,
    required this.imagePath,
    required this.species,
    required this.freshnessLabel,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('MMMM d, yyyy • h:mm a').format(DateTime.now());

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
              // 🔵 Fish Image in Circle
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 110,
                    backgroundColor: Colors.grey.shade800,
                    backgroundImage: File(imagePath).existsSync()
                        ? FileImage(File(imagePath))
                        : const AssetImage("assets/images/fallback.png") as ImageProvider,
                  ),
                  // ✅ FishFresh Logo overlay
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Image.asset(
                      "assets/images/fishfresh_logo.png", // 👈 make sure logo is in assets
                      width: 45,
                      height: 45,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 🟢 Freshness Label
              Text(
                freshnessLabel,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              // 🐟 Species
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  species,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 🕒 Date & Time
              Text(
                now,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),

              const SizedBox(height: 30),

              // 📊 Analysis Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Fish Analysis",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      "- Freshness confidence: 90%\n"
                      "- Eye clarity: Clear and bright\n"
                      "- Gills color: Reddish, healthy\n"
                      "- Scales: Shiny and intact\n"
                      "- Odor: Neutral (AI simulated)",
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ✅ Scan Again Button
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
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const FishScanCamera(cameras: [])),
                  );
                },
              ),

              const SizedBox(height: 15),

              // Done Button
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
