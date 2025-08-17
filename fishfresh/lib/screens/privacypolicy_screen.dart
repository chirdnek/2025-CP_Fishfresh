import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          "Privacy Policy",
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
            Text(
              "Last updated: August 2025",
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),

            Text(
              "This Privacy Policy explains how FishFresh collects, uses, and protects your personal data when you use our app.",
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            _buildSection(
              number: "1",
              title: "Information We Collect",
              content:
                  "We may collect personal information such as your name, email address, and payment details, as well as usage data to improve the app.",
            ),
            _buildSection(
              number: "2",
              title: "How We Use Your Information",
              content:
                  "Your data is used to provide services, improve functionality, send notifications, and ensure account security.",
            ),
            _buildSection(
              number: "3",
              title: "Sharing Your Data",
              content:
                  "We do not sell your personal data. We may share information with trusted third parties who help us operate our services.",
            ),
            _buildSection(
              number: "4",
              title: "Data Security",
              content:
                  "We implement strong security measures to protect your personal information from unauthorized access.",
            ),
            _buildSection(
              number: "5",
              title: "Your Rights",
              content:
                  "You have the right to access, update, or delete your personal data. Contact us to exercise these rights.",
            ),
            _buildSection(
              number: "6",
              title: "Changes to This Policy",
              content:
                  "We may update this Privacy Policy from time to time. We will notify you of significant changes.",
            ),
            _buildSection(
              number: "7",
              title: "Contact Us",
              content:
                  "For privacy-related inquiries, email: privacy@fishfresh.com",
            ),

            const SizedBox(height: 30),

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
