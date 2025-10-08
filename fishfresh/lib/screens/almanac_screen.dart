// lib/screens/fish_almanac.dart
// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';

class FishAlmanacPage extends StatelessWidget {
  final List<Map<String, String>> fishes = [
    {
      "image": "assets/images/bigeye_scad.jpg",
      "tagalog": "Matangbaka",
      "chavacano": "Matangbaka",
      "english": "Bigeye Scad",
      "scientific": "Selar crumenophthalmus",
      "info":
          "Matangbaka is commonly sold in Zamboanga City’s markets. Known for its large eyes, "
              "it is a staple among local households. Vendors often highlight its freshness by "
              "showing its clear eyes. Historically, it has been one of the city’s affordable "
              "and accessible fish for everyday meals."
    },
    {
      "image": "assets/images/country_maiden.jpg",
      "tagalog": "Tamban",
      "chavacano": "Tamban",
      "english": "Country Maiden",
      "scientific": "Sardinella longiceps",
      "info":
          "Tamban is one of the most important fish in Zamboanga, popularly dried as tuyo "
              "or smoked. It has cultural and economic significance in households, often linked "
              "to local fishing traditions and livelihoods."
    },
    {
      "image": "assets/images/fringella_sardinella.jpg",
      "tagalog": "Sardinas",
      "chavacano": "Sardinas",
      "english": "Fringella Sardinella",
      "scientific": "Sardinella fimbriata",
      "info":
          "Sardinas is strongly tied to Zamboanga City’s sardine industry. Local factories "
              "process them into canned sardines, a major livelihood and export product. It is "
              "both a cultural and economic symbol of the city."
    },
    {
      "image": "assets/images/indian_mackerel.jpg",
      "tagalog": "Alumahan",
      "chavacano": "Alumahan",
      "english": "Indian Mackerel",
      "scientific": "Rastrelliger kanagurta",
      "info":
          "Alumahan is a favorite in households, often fried or grilled. In Zamboanga, it "
              "is seen daily in wet markets. Its freshness is judged by its shiny skin and firm body."
    },
    {
      "image": "assets/images/yellowfin_tuna.jpg",
      "tagalog": "Tambakol",
      "chavacano": "Tambakol",
      "english": "Yellowfin Tuna",
      "scientific": "Thunnus albacares",
      "info":
          "Tambakol plays a major role in Zamboanga’s fishing economy, particularly for export. "
              "It is also a prized catch for local consumption. Known for its size and meat quality, "
              "it reflects Zamboanga’s reputation as a tuna hub."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fish Almanac"),
        backgroundColor: const Color(0xFF1A5A4A),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF0E1F17),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: fishes.length,
        itemBuilder: (context, index) {
          final fish = fishes[index];
          return Card(
            color: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fish Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      fish["image"]!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Localized Names (line by line)
                  Text("Tagalog: ${fish["tagalog"]}",
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text("Chavacano: ${fish["chavacano"]}",
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text("English: ${fish["english"]}",
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),

                  const SizedBox(height: 6),

                  // Scientific Name
                  Text(
                    "Scientific: ${fish["scientific"]}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.greenAccent,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Info
                  Text(
                    fish["info"]!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
