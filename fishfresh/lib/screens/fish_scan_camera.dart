// lib/screens/fish_scan_camera.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, unused_field, deprecated_member_use, unused_import

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/fish_runtime.dart';
import '../services/model_registry.dart';
import '../services/save_scan_history.dart';
import 'fish_result_screen.dart';

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
  bool _scanning = false;
  bool _runningInference = false;
  double _scanLineY = 0.0;
  int _step = 0; // 0=front, 1=back
  String? _frontImagePath;
  String? _backImagePath;

  double _zoomLevel = 1.0;
  double _maxZoom = 1.0;
  int _currentCameraIndex = 0;
  Timer? _scanTimer;

  // Focus & exposure UI/logic
  Offset? _focusUiPos;               // where the box shows (screen coords)
  Timer? _hideFocusTimer;
  bool _showExposureSlider = false;  // show vertical line with sun
  double _exposureOffset = 0.0;      // current device exposure offset
  double _minExposure = 0.0;
  double _maxExposure = 0.0;

  // Drag tracking for exposure slider
  Offset? _dragStartUiPos;
  double _startProgress = 0.5;       // 0..1 mapped to exposure range

  // === Model runtime ===
  final FishRuntime _runtime = FishRuntime();

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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
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
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (_disposed) {
        await controller.dispose();
        return;
      }

      await controller.setFlashMode(FlashMode.off);

      try { await controller.setFocusMode(FocusMode.auto); } catch (_) {}
      try { await controller.setExposureMode(ExposureMode.auto); } catch (_) {}

      _maxZoom = await controller.getMaxZoomLevel();
      _zoomLevel = 1.0;

      try {
        _minExposure = await controller.getMinExposureOffset();
        _maxExposure = await controller.getMaxExposureOffset();
        // read current exposure
        _exposureOffset = 0.0;
      } catch (e) {
        _minExposure = 0.0;
        _maxExposure = 0.0;
        _exposureOffset = 0.0;
        debugPrint('⚠️ Exposure range not available: $e');
      }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Camera error: $e")),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (!_isReady || _controller == null) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
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
    if (!_isReady || _controller == null || _scanning || _runningInference) return;

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
    if (!_isReady || _controller == null || _disposed || _runningInference) return;

    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Gallery permission denied")),
          );
        }
      }

      final file = await _controller!.takePicture();

      // Best-effort save to gallery
      try { await PhotoManager.editor.saveImageWithPath(file.path); } catch (e) { debugPrint("⚠️ Save failed: $e"); }

      if (_step == 0) {
        _frontImagePath = file.path;
        _step = 1;
        if (mounted && !_disposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Front captured — now capture the BACK")),
          );
          setState(() {});
        }
      } else {
        _backImagePath = file.path;
        await _chooseModelAndRun(); // we have both images now
      }
    } catch (e) {
      debugPrint("❌ Capture failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  Future<void> _chooseModelAndRun() async {
    if (_frontImagePath == null || _backImagePath == null) return;
    if (!mounted || _disposed) return;

    final def = await _pickModel(context);
    if (def == null) return;

    setState(() => _runningInference = true);

    try {
      await _runtime.load(def);

      final sw = Stopwatch()..start();
      final model = _runtime.model;
      final pairRes = await model.predictPair(_frontImagePath!, _backImagePath!);
      sw.stop();
      final int latencyMs = sw.elapsedMilliseconds;

      if (!mounted) return;

      final front = (pairRes['front_result'] as Map?) ?? const {};
      final back  = (pairRes['back_result'] as Map?) ?? const {};

      final summary = <String, dynamic>{
        'confidence': (front['confidence'] as num?)?.toDouble()
            ?? (back['confidence'] as num?)?.toDouble()
            ?? 0.0,
        'freshness_scores': (front['freshness_scores'] as Map<String, dynamic>?)
            ?? (back['freshness_scores'] as Map<String, dynamic>?),
        'species_scores': (front['species_scores'] as Map<String, dynamic>?)
            ?? (back['species_scores'] as Map<String, dynamic>?),
        'latency_ms': latencyMs,
      };

      final String species =
          (pairRes['predicted_species'] as String?) ?? 'Unknown';
      final String freshness =
          (pairRes['predicted_freshness'] as String?) ?? 'Unknown';
      final String activeModelName = def.name;

      try {
        await ScanHistoryService.save(
          species: species,
          freshness: freshness,
          frontImagePath: _frontImagePath!,
          backImagePath: _backImagePath,
          modelName: activeModelName,
          summary: summary,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e')),
          );
        }
      }

      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            frontImagePath: _frontImagePath!,
            backImagePath: _backImagePath ?? _frontImagePath!,
            species: species,
            freshnessLabel: freshness,
            result: summary,
            modelName: activeModelName,
          ),
        ),
      );

      _step = 0;
      _frontImagePath = null;
      _backImagePath = null;
    } catch (e) {
      debugPrint('❌ Inference error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inference error: $e')),
        );
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() => _runningInference = false);
      }
    }
  }

  // ===================== Focus + exposure gestures =====================

  // Map a progress [0..1] to exposure offset
  double _progressToExposure(double p) {
    final range = _maxExposure - _minExposure;
    return (_minExposure + (p.clamp(0.0, 1.0) * range));
  }

  // Compute current progress from exposure offset
  double _exposureToProgress(double val) {
    if (_maxExposure == _minExposure) return 0.5;
    return ((val - _minExposure) / (_maxExposure - _minExposure))
        .clamp(0.0, 1.0);
  }

  // Convert UI tap to normalized camera coords and set focus/exposure points
  Future<void> _setFocusAndExposurePoint(
      Offset uiTap, BoxConstraints c) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final previewSize = _controller!.value.previewSize!;
    final intrinsicW = previewSize.height;
    final intrinsicH = previewSize.width;

    final screenW = c.maxWidth;
    final screenH = c.maxHeight;

    final scale = (screenW / intrinsicW) > (screenH / intrinsicH)
        ? (screenW / intrinsicW)
        : (screenH / intrinsicH);

    final displayW = intrinsicW * scale;
    final displayH = intrinsicH * scale;

    final dx = (screenW - displayW) / 2.0;
    final dy = (screenH - displayH) / 2.0;

    final tapX = uiTap.dx;
    final tapY = uiTap.dy;

    final clampedX = tapX.clamp(dx, dx + displayW) - dx;
    final clampedY = tapY.clamp(dy, dy + displayH) - dy;

    final nx = (clampedX / displayW).toDouble();
    final ny = (clampedY / displayH).toDouble();

    try { await _controller!.setFocusPoint(Offset(nx, ny)); } catch (_) {}
    try { await _controller!.setExposurePoint(Offset(nx, ny)); } catch (_) {}
  }

  // Handle finger down (start focus box, prep slider)
  Future<void> _onPanDown(DragDownDetails d, BoxConstraints c) async {
    _focusUiPos = d.localPosition;
    _dragStartUiPos = d.localPosition;
    _showExposureSlider = false; // hidden until user moves
    _hideFocusTimer?.cancel();

    // sync progress from current exposure
    _startProgress = _exposureToProgress(_exposureOffset);

    await _setFocusAndExposurePoint(d.localPosition, c);

    setState(() {});
    // hide the box if the user doesn't drag (after 1s)
    _hideFocusTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_showExposureSlider) {
        setState(() => _focusUiPos = null);
      }
    });
  }

  // Handle drag to adjust exposure; reveal slider when user moves vertically
  Future<void> _onPanUpdate(DragUpdateDetails d) async {
    if (_controller == null) return;
    if (_dragStartUiPos == null) return;

    // Threshold to reveal the slider
    if (!_showExposureSlider && d.delta.distance > 4) {
      setState(() => _showExposureSlider = true);
    }

    if (_maxExposure == _minExposure) return;

    // Move up => increase brightness
    final dy = d.localPosition.dy - _dragStartUiPos!.dy;
    final progress = (_startProgress - (dy / 150.0)).clamp(0.0, 1.0);

    final newExposure = _progressToExposure(progress);
    _exposureOffset = newExposure;
    try { await _controller!.setExposureOffset(_exposureOffset); } catch (_) {}

    setState(() {
      // keep the box visible while sliding
      _focusUiPos ??= _dragStartUiPos;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    // Hide slider + box shortly after release
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _showExposureSlider = false;
        _focusUiPos = null;
      });
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _hideFocusTimer?.cancel();
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _onPanDown(d, constraints),
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              children: [
                // Preview
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
                      _TopButton(icon: Icons.close, onTap: () => Navigator.of(context).pop()),
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

                // Step label
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

                // Scan animation
                if (_scanning)
                  Positioned(
                    top: _scanLineY,
                    left: 0,
                    right: 0,
                    child: Container(height: 3, color: Colors.cyanAccent),
                  ),

                // Focus box
                if (_focusUiPos != null)
                  Positioned(
                    left: _focusUiPos!.dx - 28,
                    top: _focusUiPos!.dy - 28,
                    child: IgnorePointer(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                // Exposure vertical slider (line + sun) near the box
                if (_focusUiPos != null && _showExposureSlider)
                  _ExposureSliderOverlay(
                    anchor: _focusUiPos!,
                    progress: _exposureToProgress(_exposureOffset),
                  ),

                // Capture button
               // Capture button (full circle is clickable, with extra hit area)
Positioned(
  bottom: MediaQuery.of(context).padding.bottom + 24,
  left: 0,
  right: 0,
  child: Center(
    child: AbsorbPointer(
      absorbing: _runningInference, // disable while analyzing
      child: Opacity(
        opacity: _runningInference ? 0.35 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _startScanAndCapture,
            customBorder: const CircleBorder(),      // makes whole circle clickable
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Container(
              width: 96,                              // big touch target
              height: 96,
              alignment: Alignment.center,
              // optional outer ring (also clickable)
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Container(
                width: 78,                            // inner capture circle
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
                            Text("Analyzing fish...", style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==== Bottom-sheet model picker ====
  Future<ModelDef?> _pickModel(BuildContext context) async {
    return await showModalBottomSheet<ModelDef>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text('Choose model to run', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final m in ModelRegistry.all)
                ListTile(
                  title: Text(m.name),
                  subtitle: Text(m.assetPath.split('/').last),
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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

/// Simple vertical exposure overlay placed to the right of [anchor].
class _ExposureSliderOverlay extends StatelessWidget {
  final Offset anchor;   // focus box center in screen coords
  final double progress; // 0..1 (0 = bottom/dark, 1 = top/bright)
  const _ExposureSliderOverlay({required this.anchor, required this.progress});

  @override
  Widget build(BuildContext context) {
    // Visual constants
    const double lineLen = 160.0;
    const double lineThickness = 2.0;
    const double xOffset = 42.0; // distance right of focus box
    const double iconSize = 22.0;

    final topY = anchor.dy - (lineLen / 2);
    final iconY = topY + (1 - progress.clamp(0, 1)) * lineLen;

    final screen = MediaQuery.of(context).size;
    final left = (anchor.dx + xOffset).clamp(16.0, screen.width - 32.0);

    return Stack(
      children: [
        // vertical line
        Positioned(
          left: left,
          top: topY,
          child: Container(
            width: lineThickness,
            height: lineLen,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        // sun icon (current position)
        Positioned(
          left: left - (iconSize / 2) + (lineThickness / 2),
          top: iconY - (iconSize / 2),
          child: const Icon(Icons.wb_sunny, color: Colors.white, size: iconSize),
        ),
      ],
    );
  }
}
