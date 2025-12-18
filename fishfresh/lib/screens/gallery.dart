// lib/screens/gallery.dart
// ignore_for_file: use_super_parameters, prefer_is_empty, unused_import

import 'dart:io';
import 'dart:async'; // for Timer

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// 🔹 YOLO + RESNET PIPELINE ONLY
import '../services/fish_pipeline.dart';

import 'fish_result_screen.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({Key? key}) : super(key: key);

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _all = [];
  bool _loading = true;
  bool _processing = false; // running analysis
  final List<AssetEntity> _selected = [];

  final ScrollController _scrollController = ScrollController();

  // 🔹 Floating date bubble state
  String? _currentDateLabel;
  bool _showDateBubble = false;
  Timer? _hideBubbleTimer;
  double _bubbleTop = 0.0; // y-position in pixels

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hideBubbleTimer?.cancel();
    super.dispose();
  }

  // Format date as a "timeline" label: Today, Yesterday, Nov 24, etc.
  String _formatTimelineLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(d).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';

    if (now.year == dt.year) {
      // Same year → just month + day
      return DateFormat('MMM d').format(dt); // e.g. "Nov 24"
    } else {
      // Different year → month + day + year
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  /// Update the label *and* the vertical position of the bubble based on scroll.
  void _updateBubbleFromScroll() {
    if (_all.isEmpty || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final offset = position.pixels.clamp(0.0, maxScroll);

    final progress =
        maxScroll == 0 ? 0.0 : (offset / maxScroll).clamp(0.0, 1.0); // 0..1

    int index = (progress * (_all.length - 1)).round();
    index = index.clamp(0, _all.length - 1);

    final asset = _all[index];
    final label = _formatTimelineLabel(asset.createDateTime);

    // approximate thumb vertical range within the screen
    final size = MediaQuery.of(context).size;
    // keep it between 18% and 78% of screen height (avoid app bar & bottom bar)
    final double minTop = size.height * 0.18;
    final double maxTop = size.height * 0.78;
    final double bubbleTop = minTop + (maxTop - minTop) * progress;

    setState(() {
      _currentDateLabel = label;
      _showDateBubble = true;
      _bubbleTop = bubbleTop;
    });

    // Restart hide timer
    _hideBubbleTimer?.cancel();
    _hideBubbleTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _showDateBubble = false);
    });
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth) {
      if (!mounted) return;
      setState(() => _loading = false);
      PhotoManager.openSetting();
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true, // "All photos" / "Recents"
    );

    if (albums.isEmpty) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _loading = false;
      });
      return;
    }

    final first = albums.first;

    // 🔹 Load *all* images using pagination
    const int pageSize = 100;
    int page = 0;
    final List<AssetEntity> allAssets = [];

    while (true) {
      final pageItems =
          await first.getAssetListPaged(page: page, size: pageSize);

      if (pageItems.isEmpty) break;

      allAssets.addAll(pageItems);

      if (pageItems.length < pageSize) {
        // last page
        break;
      }
      page++;
    }

    if (!mounted) return;
    setState(() {
      _all = allAssets;
      _loading = false;
    });
  }

  void _toggle(AssetEntity asset) {
    if (_processing) return; // don't change selection while analyzing
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else {
        if (_selected.length < 1) _selected.add(asset);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // YOLO + RESNET PIPELINE (single mode, automatic)
  // ---------------------------------------------------------------------------
  Future<void> _runYoloResNet() async {
    if (_selected.length != 1 || _processing) return;

    setState(() => _processing = true);

    final asset = _selected[0];
    final file = await asset.file;
    if (file == null) {
      if (mounted) setState(() => _processing = false);
      return;
    }

    try {
      final bytes = await file.readAsBytes();

      // Use full pipeline (YOLO + crops + ResNet)
      final result = await FishPipeline.instance.runOnBytes(
        bytes,
        mode: ScanMode.auto,
      );

      final species =
          (result['overall_species'] ?? 'Unknown').toString();
      final freshness =
          (result['overall_freshness'] ?? 'Unknown').toString();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: file.path,
            species: species,
            freshnessLabel: freshness,
            result: result,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final bool hasSelection = _selected.length == 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text(
          'Select a photo',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // ── Scrollable grid with scrollbar ──
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification ||
                        notification is UserScrollNotification) {
                      _updateBubbleFromScroll();
                    }
                    return false;
                  },
                  child: Scrollbar(
                    thumbVisibility: true,
                    controller: _scrollController,
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(10),
                      itemCount: _all.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (_, i) {
                        final asset = _all[i];
                        final selectedIndex =
                            _selected.indexOf(asset); // -1 if not selected
                        final isSel = selectedIndex >= 0;

                        return GestureDetector(
                          onTap: () => _toggle(asset),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image(
                                  image: AssetEntityImageProvider(
                                    asset,
                                    isOriginal: false,
                                    thumbnailSize:
                                        const ThumbnailSize(300, 300),
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),

                              // dark overlay when selected
                              if (isSel)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black38,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),

                              // ✅ check icon when selected
                              if (isSel)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.cyanAccent,
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.black,
                                      size: 16,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // ── Floating date bubble that tracks the scroll thumb ──
                if (_showDateBubble && _currentDateLabel != null)
                  Positioned(
                    right: 16,
                    top: _bubbleTop == 0.0
                        ? size.height * 0.30 // default before first scroll
                        : _bubbleTop,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _currentDateLabel!,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _processing
                          ? 'Analyzing photo...'
                          : !hasSelection
                              ? 'Select 1 photo to analyze'
                              : '1 photo selected — tap Analyze',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (hasSelection && !_processing) ? _runYoloResNet : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white24,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Analyze',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
