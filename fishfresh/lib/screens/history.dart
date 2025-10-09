// lib/screens/history.dart
// ignore_for_file: deprecated_member_use, unnecessary_null_comparison, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fishfresh/screens/fish_result_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  String? _freshnessFilter;
  String? _searchQuery;
  String _sortBy = "Newest";
  bool _showSearch = false;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("You must be logged in to see history")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,

      /// ---------------- APPBAR ----------------
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showSearch
              ? Row(
                  key: const ValueKey("search"),
                  children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.trim()),
                          decoration: InputDecoration(
                            hintText: "Search species...",
                            hintStyle: const TextStyle(
                              color: Colors.black54, // ✅ dark hint
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            prefixIcon: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.black87,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showSearch = false;
                                  _searchController.clear();
                                  _searchQuery = null;
                                });
                              },
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black, // ✅ black typed text
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey("filters"),
                  children: [
                    Expanded(
                      flex: 5,
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonFormField<String>(
                          value:
                              _freshnessFilter == null ||
                                  _freshnessFilter!.isEmpty
                              ? null
                              : _freshnessFilter,
                          isDense: true,
                          dropdownColor: Colors.white, // ✅ dropdown menu white
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.black,
                          ), // ✅ arrow
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText:
                                "Select Fish Freshness", // ✅ visible when null
                            hintStyle: TextStyle(
                              color: Colors.black, // ✅ black hint text
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black, // ✅ black selected text
                          ),
                          onChanged: (v) =>
                              setState(() => _freshnessFilter = v),
                          items: ["Fresh", "Not Fresh"].map((f) {
                            return DropdownMenuItem(
                              value: f,
                              child: Text(
                                f,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors
                                      .black, // ✅ black text in dropdown list
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    _buildIconBox(
                      icon: Icons.search,
                      onTap: () => setState(() => _showSearch = true),
                    ),
                    const SizedBox(width: 8),
                    _buildIconBox(
                      icon: Icons.filter_list,
                      onTap: () => _openFilterSheet(context),
                    ),
                  ],
                ),
        ),
      ),

      /// ---------------- BODY ----------------
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.fromARGB(255, 9, 59, 51), Colors.black],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
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
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
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
                  _searchQuery!.isNotEmpty &&
                  !data['species'].toString().toLowerCase().contains(
                    _searchQuery!.toLowerCase(),
                  )) {
                return false;
              }
              return true;
            }).toList();

            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  "No history matches your filters.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['timestamp'] as Timestamp).toDate();

                return Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  child: Dismissible(
                    key: Key(doc.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      return await showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("Confirm Deletion"),
                          content: const Text(
                            "Delete this scan history entry?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                (data['localImagePath'] != null &&
                                    data['localImagePath']
                                        .toString()
                                        .isNotEmpty)
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
                                    child: const Icon(
                                      Icons.image,
                                      color: Colors.grey,
                                    ),
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _buildFreshnessBadge(data['freshness']),
                                    const SizedBox(width: 8),
                                    Text(
                                      timeago.format(date, locale: 'en_short'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Fish id: ${data['fishId'] ?? 'N/A'}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FishResultScreen(
                                          imagePath:
                                              data['localImagePath'] ?? "",
                                          species: data['species'] ?? "Unknown",
                                          freshnessLabel:
                                              data['freshness'] ?? "Unknown",
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    "View details",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// ---------------- HELPERS ----------------
  Widget _buildIconBox({required IconData icon, required VoidCallback onTap}) {
    return Container(
      height: 50,
      width: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildFreshnessBadge(String? freshness) {
    Color color;
    switch (freshness) {
      case "Fresh":
        color = Colors.green;
        break;
      case "Not Fresh":
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
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
