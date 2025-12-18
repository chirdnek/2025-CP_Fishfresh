// lib/screens/fish_scan_camera.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api,, deprecated_member_use, deprecated_member_use, deprecated_member_use, deprecated_member_use
// unused_field, deprecated_member_use, constant_identifier_names, use_build_context_synchronously,
// unnecessary_brace_in_string_interps, unnecessary_import, unused_element, override_on_non_overriding_member

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/fish_pipeline.dart'; // FishPipeline + ScanMode
import '../services/save_scan_history.dart';
import 'fish_result_screen.dart'; // ✅ your result screen

class FishScanCamera extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FishScanCamera({required this.cameras});

  @override
  State<FishScanCamera> createState() => _FishScanCameraState(); // ✅ fix here
}

class _FishScanCameraState extends State<FishScanCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _disposed = false;
  bool _isReady = false;
  bool _isFlashOn = false;
  bool _runningInference = false;
  int _currentCameraIndex = 0;

  // === Models (through FishPipeline) ===
  bool _modelReady = false;
  String _hint = 'Point the camera at the fish';

  @override
  void initState() {
    super.initState();
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    _initCamera(0);
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      await FishPipeline.instance.ensureInited();
      if (mounted) setState(() => _modelReady = true);
      debugPrint('✅ FishPipeline ready in camera');
    } catch (e) {
      debugPrint('❌ Model init failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Model init failed: $e')),
        );
      }
    }
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
      debugPrint('❌ No cameras found');
      return;
    }

    setState(() {
      _isReady = false;
      _hint = 'Initializing camera…';
    });

    try {
      final cam = widget.cameras[index];

      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (_disposed) {
        await controller.dispose();
        return;
      }

      await controller.setFlashMode(FlashMode.off);

      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      if (mounted && !_disposed) {
        setState(() {
          _controller = controller;
          _currentCameraIndex = index;
          _isReady = true;
          _hint = 'Hold steady and tap the button to capture';
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('❌ Camera init failed: $e');
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (!_isReady || _controller == null) return;

    try {
      _isFlashOn = !_isFlashOn;
      await _controller!
          .setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);

      if (mounted && !_disposed) setState(() {});
    } catch (e) {
      debugPrint('⚡ Flash error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final newIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    await _initCamera(newIndex);
  }

  // Single, smooth capture → analyze (no animations / QA dialogs)
  Future<void> _captureAndAnalyze() async {
    if (!_isReady || _controller == null || _runningInference) return;

    if (!_modelReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Models still loading, please wait...')),
        );
      }
      return;
    }

    try {
      setState(() {
        _runningInference = true;
        _hint = 'Capturing…';
      });

      // Request gallery permission (for saving image)
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gallery permission denied')),
          );
        }
      }

      // 1) Capture photo
      final xFile = await _controller!.takePicture();
      final String originalPath = xFile.path;

      // Optional: save to gallery
      try {
        await PhotoManager.editor.saveImageWithPath(originalPath);
      } catch (_) {}

      setState(() {
        _hint = 'Analyzing fish...';
      });

      // 2) Read ORIGINAL bytes (match gallery path)
      final Uint8List imageBytes = await File(originalPath).readAsBytes();

      // 3) Run the same pipeline as gallery: YOLO + ResNet
      final pipelineResult = await FishPipeline.instance.runOnBytes(
        imageBytes,
        mode: ScanMode.auto,
      );

      final perFish = (pipelineResult['per_fish'] as List<dynamic>?) ??
          const <dynamic>[];

      if (perFish.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No fish detected. Please try again.'),
            ),
          );
          setState(() {
            _hint = 'Adjust framing and retake';
          });
        }
        return;
      }

      final String species =
          (pipelineResult['overall_species'] ?? 'Unknown').toString();
      final String freshness =
          (pipelineResult['overall_freshness'] ?? 'Unknown').toString();

      // 4) Save history using the original photo
      try {
        await ScanHistoryService.save(
          species: species,
          freshness: freshness,
          frontImagePath: originalPath,
          backImagePath: null,
          summary: pipelineResult,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e')),
          );
        }
      }

      // 5) Navigate to result screen
      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: originalPath,
            species: species,
            freshnessLabel: freshness,
            result: pipelineResult,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('❌ _captureAndAnalyze error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture / analysis error: $e')),
        );
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _runningInference = false;
          _hint = 'Point the camera at the fish';
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    const stepLabel = 'Capture the FRONT of the fish';
    final statusColor = _runningInference
        ? const Color(0xAA455A64)
        : const Color(0xAA1565C0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // Top buttons (close, flash, switch)
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
                      icon:
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      onTap: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    _TopButton(
                      icon: Icons.cameraswitch,
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Step label
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                stepLabel,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),

          // Live status hint
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 110,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _hint,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // Capture button
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Center(
              child: AbsorbPointer(
                absorbing: _runningInference,
                child: Opacity(
                  opacity: _runningInference ? 0.35 : 1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _captureAndAnalyze,
                      customBorder: const CircleBorder(),
                      splashColor: Colors.white24,
                      highlightColor: Colors.white10,
                      child: Container(
                        width: 96,
                        height: 96,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera,
                            size: 36,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Inference overlay
          if (_runningInference)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.4),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Analyzing fish...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// UI bits
class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopButton({
    required this.icon,
    required this.onTap,
  });

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
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
