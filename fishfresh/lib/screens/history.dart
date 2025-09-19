// lib/screens/history.dart
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fishfresh/screens/fish_result_screen.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _freshnessFilter;
  String? _searchQuery;
  String _sortBy = "Newest";

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text("You must be logged in to see history"),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  hintText: "Select Fish Freshness",
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                value: _freshnessFilter,
                onChanged: (v) => setState(() => _freshnessFilter = v),
                items: [
                  "Fresh",
                  "Very Fresh",
                  "Non-Fresh",
                  "Spoiled Fish",
                ].map((f) {
                  return DropdownMenuItem(value: f, child: Text(f));
                }).toList(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // TODO: search functionality
              },
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _openFilterSheet(context),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scanHistory')
            .orderBy('timestamp', descending: _sortBy == "Newest")
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No scans yet.\nStart scanning fish to see them here!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (_freshnessFilter != null &&
                data['freshness'] != _freshnessFilter) {
              return false;
            }
            if (_searchQuery != null &&
                !data['species']
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery!.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No history matches your filters.",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final date = (data['timestamp'] as Timestamp).toDate();

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (data['localImagePath'] != null &&
                              data['localImagePath'].toString().isNotEmpty)
                          ? Image.file(
                              File(data['localImagePath']),
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 70,
                              height: 70,
                              color: Colors.grey[300],
                              child: const Icon(Icons.image, color: Colors.grey),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['species'] ?? "Unknown Fish",
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildFreshnessBadge(data['freshness']),
                              const SizedBox(width: 8),
                              Text(
                                "${date.day} ${_monthName(date.month)} ${date.year}",
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${date.hour}:${date.minute.toString().padLeft(2, '0')}",
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Fish id: ${data['fishId'] ?? 'N/A'}",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FishResultScreen(
                              imagePath: data['localImagePath'] ?? "",
                              species: data['species'] ?? "Unknown",
                              freshnessLabel: data['freshness'] ?? "Unknown",
                            ),
                          ),
                        );
                      },
                      child: const Text("View details"),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFreshnessBadge(String? freshness) {
    Color color;
    switch (freshness) {
      case "Fresh":
        color = Colors.green;
        break;
      case "Very Fresh":
        color = Colors.blue;
        break;
      case "Non-Fresh":
        color = Colors.orange;
        break;
      case "Spoiled Fish":
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        freshness ?? "Unknown",
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return months[month - 1];
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Sort by",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ListTile(
              title: const Text("Newest"),
              onTap: () => setState(() {
                _sortBy = "Newest";
                Navigator.pop(context);
              }),
            ),
            ListTile(
              title: const Text("Oldest"),
              onTap: () => setState(() {
                _sortBy = "Oldest";
                Navigator.pop(context);
              }),
            ),
          ],
        ),
      ),
    );
  }
}
