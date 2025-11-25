// lib/screens/gallery.dart
// ignore_for_file: use_super_parameters, prefer_is_empty

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({Key? key}) : super(key: key);

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _all = [];
  bool _loading = true;
  final List<AssetEntity> _selected = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth) {
      if (!mounted) return;
      setState(() => _loading = false);
      PhotoManager.openSetting();
      return;
    }

    final albums =
        await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);

    if (albums.isEmpty) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _loading = false;
      });
      return;
    }

    // smaller page size to avoid decoding hundreds at once
    final first = albums.first;
    final list = await first.getAssetListPaged(page: 0, size: 120);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  void _toggle(AssetEntity asset) {
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else {
        if (_selected.length < 1) _selected.add(asset);
      }
    });
  }

  Future<void> _confirm() async {
    if (_selected.length != 1) return;
    final f1 = await _selected[0].file;
    if (f1 == null) return;
    if (!mounted) return;
    Navigator.pop<String>(context, f1.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Select a photo', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _all.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final asset = _all[i];
                final selectedIndex = _selected.indexOf(asset); // -1 if not selected
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
                            thumbnailSize: const ThumbnailSize(300, 300),
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (isSel)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
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
      bottomNavigationBar: Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? 'Select 1 photo to analyze'
                      : '1 selected — ready',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                onPressed: _selected.length == 1 ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white24,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Use photo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
