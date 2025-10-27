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
  String? _freshnessFilter; // "Fresh" | "Not Fresh" | null
  String? _searchQuery;
  String _sortBy = "Newest"; // "Newest" | "Oldest"
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
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
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            prefixIcon: IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.black87),
                              onPressed: () {
                                setState(() {
                                  _showSearch = false;
                                  _searchController.clear();
                                  _searchQuery = null;
                                });
                              },
                            ),
                            suffixIcon: (_searchQuery?.isNotEmpty ?? false)
                                ? IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.black54),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = null;
                                      });
                                    },
                                  )
                                : null,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
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
  value: (_freshnessFilter?.isNotEmpty ?? false) ? _freshnessFilter : null,
  isExpanded: true,
  isDense: true,
  dropdownColor: Colors.white,
  icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
  // This is the visible placeholder when nothing is selected
  hint: const Text(
    "Select Freshness",
    style: TextStyle(
      color: Colors.black,
      fontWeight: FontWeight.w600,
      fontSize: 16,
    ),
  ),
  decoration: const InputDecoration(
    border: InputBorder.none,
    // keep decoration clean; hint handled above
  ),
  style: const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  ),
  onChanged: (v) => setState(() => _freshnessFilter = v),
  items: const [
    DropdownMenuItem(value: "Fresh", child: Text("Fresh")),
    DropdownMenuItem(value: "Not Fresh", child: Text("Not Fresh")),
  ],
)

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
            if (snapshot.hasError) {
              return _centerText(
                "Error loading history.\n${snapshot.error}",
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _centerText(
                "No scans yet.\nStart scanning fish to see them here!",
              );
            }

            // Apply client-side filters (freshness + search)
            final filteredDocs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>?;

              if (data == null) return false;

              final freshness = (data['freshness'] ?? '').toString();
              final species = (data['species'] ?? '').toString();

              if (_freshnessFilter != null &&
                  _freshnessFilter!.isNotEmpty &&
                  freshness != _freshnessFilter) {
                return false;
              }
              if (_searchQuery != null &&
                  _searchQuery!.isNotEmpty &&
                  !species.toLowerCase().contains(_searchQuery!.toLowerCase())) {
                return false;
              }
              return true;
            }).toList();

            if (filteredDocs.isEmpty) {
              return _centerText("No history matches your filters.");
            }

            return ListView.builder(
              itemCount: filteredDocs.length,
              itemBuilder: (ctx, i) {
                final doc = filteredDocs[i];
                final data = (doc.data() as Map<String, dynamic>)..removeWhere(
                    (key, value) => value == null);

                // Timestamp
                DateTime date = DateTime.now();
                final ts = data['timestamp'];
                if (ts is Timestamp) date = ts.toDate();

                final frontPath = (data['frontImagePath'] ?? '') as String;
                final backPath =
                    (data['backImagePath'] as String?) ?? frontPath;
                final species = (data['species'] ?? 'Unknown') as String;
                final freshness = (data['freshness'] ?? 'Unknown') as String;
                final modelName = (data['modelName'] ?? '') as String;
                final thumbPath = frontPath.isNotEmpty ? frontPath : backPath;

                // ✅ extract summary & confidence
                final Map<String, dynamic>? savedSummary =
                    (data['summary'] is Map)
                        ? Map<String, dynamic>.from(data['summary'])
                        : null;

                final double? savedConfidence = (data['confidence'] is num)
                    ? (data['confidence'] as num).toDouble()
                    : null;

                final resultToPass = savedSummary ??
                    (savedConfidence != null
                        ? {'confidence': savedConfidence}
                        : null);

                return Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Dismissible(
                    key: Key(doc.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      return await showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("Confirm Deletion"),
                          content:
                              const Text("Delete this scan history entry?"),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await doc.reference.delete();
                                  if (mounted) {
                                    Navigator.of(context).pop(true);
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  Navigator.of(context).pop(false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Delete failed: ${e.toString()}'),
                                    ),
                                  );
                                }
                              },
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
                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: (thumbPath.isNotEmpty &&
                                    File(thumbPath).existsSync())
                                ? Image.file(
                                    File(thumbPath),
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

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        species,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    if (modelName.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          modelName,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 4),

                                Row(
                                  children: [
                                    _buildFreshnessBadge(freshness),
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
                                  "Fish id: ${doc.id}",
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
                                          frontImagePath: frontPath.isNotEmpty
                                              ? frontPath
                                              : backPath,
                                          backImagePath: backPath.isNotEmpty
                                              ? backPath
                                              : frontPath,
                                          species: species,
                                          freshnessLabel: freshness,
                                          modelName: modelName.isNotEmpty
                                              ? modelName
                                              : null,
                                          result: resultToPass, // ✅ pass result
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

  Widget _centerText(String msg) {
    return Center(
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
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
            const Divider(),
            ListTile(
              title: const Text("Clear filters"),
              onTap: () => setState(() {
                _freshnessFilter = null;
                _searchQuery = null;
                _searchController.clear();
                _showSearch = false;
                Navigator.pop(context);
              }),
            ),
          ],
        ),
      ),
    );
  }
}
