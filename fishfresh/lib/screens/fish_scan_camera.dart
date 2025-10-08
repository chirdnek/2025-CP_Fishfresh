// lib/screens/fish_scan_camera.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, unused_field, deprecated_member_use

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class FishScanCamera extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FishScanCamera({required this.cameras});

  @override
  State<FishScanCamera> createState() => _FishScanCameraState();
}

class _FishScanCameraState extends State<FishScanCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _disposed = false;
  bool _isReady = false;
  bool _isFlashOn = false;
  bool _isClosing = false;
  bool _scanning = false;
  double _scanLineY = 0.0;
  int _step = 0;
  String? _frontImagePath;
  String? _backImagePath;

  double _zoomLevel = 1.0;
  double _maxZoom = 1.0;
  int _currentCameraIndex = 0;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    _initCamera(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
      _isReady = false;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_currentCameraIndex);
    }
  }

  Future<void> _initCamera(int index) async {
    if (_disposed) return;
    if (widget.cameras.isEmpty) {
      debugPrint("❌ No cameras found");
      return;
    }

    setState(() => _isReady = false);

    try {
      final cam = widget.cameras[index];
      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      if (_disposed) {
        await controller.dispose();
        return;
      }

      await controller.setFlashMode(FlashMode.off);
      _maxZoom = await controller.getMaxZoomLevel();
      _zoomLevel = 1.0;

      if (mounted && !_disposed) {
        setState(() {
          _controller = controller;
          _currentCameraIndex = index;
          _isReady = true;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint("❌ Camera init failed: $e");
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Camera error: $e")));
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (!_isReady || _controller == null) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _controller!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      if (mounted && !_disposed) setState(() {});
    } catch (e) {
      debugPrint("⚡ Flash error: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final newIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    await _initCamera(newIndex);
  }

  void _startScanAndCapture() {
    if (!_isReady || _controller == null || _scanning) return;

    setState(() {
      _scanning = true;
      _scanLineY = 0;
    });

    final screenHeight = MediaQuery.of(context).size.height;
    _scanTimer = Timer.periodic(const Duration(milliseconds: 12), (t) {
      if (!mounted || _disposed) {
        t.cancel();
        return;
      }
      setState(() {
        _scanLineY += 6.0;
        if (_scanLineY >= screenHeight - 100) {
          _scanning = false;
          t.cancel();
          _capturePictureAfterScan();
        }
      });
    });
  }

  Future<void> _capturePictureAfterScan() async {
    if (!_isReady || _controller == null || _disposed || _isClosing) return;
    try {
      final file = await _controller!.takePicture();

      // ✅ save to gallery
      await PhotoManager.editor.saveImageWithPath(file.path);

      if (_step == 0) {
        _frontImagePath = file.path;
        _step = 1;
        if (mounted && !_disposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Front captured — now capture the BACK"),
            ),
          );
          setState(() {});
        }
      } else {
        _backImagePath = file.path;
        _isClosing = true;
        if (mounted) {
          Navigator.of(
            context,
          ).pop({'front': _frontImagePath, 'back': _backImagePath});
        }
      }
    } catch (e) {
      debugPrint("❌ Capture failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _controller != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          // Top buttons
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TopButton(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
                Row(
                  children: [
                    _TopButton(
                      icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      onTap: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    _TopButton(icon: Icons.cameraswitch, onTap: _switchCamera),
                  ],
                ),
              ],
            ),
          ),
          // Step text
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _step == 0
                    ? "Step 1 — Capture FRONT of fish"
                    : "Step 2 — Capture BACK of fish",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          // Scan FX
          if (_scanning)
            Positioned(
              top: _scanLineY,
              left: 0,
              right: 0,
              child: Container(height: 3, color: Colors.cyanAccent),
            ),
          // Capture button
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _startScanAndCapture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera,
                    size: 38,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
