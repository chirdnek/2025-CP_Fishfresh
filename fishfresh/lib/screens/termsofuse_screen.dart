import 'package:flutter/material.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF22C08A);
    const backgroundColor = Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: const Text(
          "Terms of Use",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              "Last updated: August 2025",
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),

            // Introduction
            Text(
              "By using FishFresh, you agree to be bound by these Terms of Use. "
              "If you do not agree, please do not use the app.",
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // Sections
            _buildSection(
              number: "1",
              title: "Eligibility",
              content:
                  "You must be at least 13 years old to use this app.",
            ),
            _buildSection(
              number: "2",
              title: "Use of the App",
              content:
                  "You agree not to misuse the app, attempt to hack, or violate laws.",
            ),
            _buildSection(
              number: "3",
              title: "Intellectual Property",
              content:
                  "All content, trademarks, and code belong to FishFresh.",
            ),
            _buildSection(
              number: "4",
              title: "User Content",
              content:
                  "You are responsible for the data you upload.",
            ),
            _buildSection(
              number: "5",
              title: "Privacy",
              content:
                  "See our Privacy Policy for details on how we handle your data.",
            ),
            _buildSection(
              number: "6",
              title: "Limitation of Liability",
              content:
                  "FishFresh is not liable for any damages resulting from app use.",
            ),
            _buildSection(
              number: "7",
              title: "Changes to Terms",
              content:
                  "We may update these terms from time to time.",
            ),
            _buildSection(
              number: "8",
              title: "Contact Us",
              content:
                  "For questions, email: support@fishfresh.com",
            ),

            const SizedBox(height: 30),

            // Close button
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGreen,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "Close",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String number,
    required String title,
    required String content,
  }) {
    const brandGreen = Color(0xFF22C08A);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Number Circle
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: brandGreen,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Title
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
