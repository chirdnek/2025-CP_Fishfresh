// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Image
            CircleAvatar(
              radius: 90,
              backgroundImage: FileImage(File(imagePath)),
            ),
            const SizedBox(height: 16),

            // Freshness
            Text(
              freshnessLabel,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),

            // Species
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

            // Date
            Text(now, style: const TextStyle(color: Colors.white54, fontSize: 12)),

            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade400,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Done",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
