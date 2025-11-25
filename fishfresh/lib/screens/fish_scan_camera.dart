// lib/screens/fish_scan_camera.dart
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api, unused_field, deprecated_member_use, constant_identifier_names, use_build_context_synchronously, unnecessary_brace_in_string_interps, unnecessary_import, unused_element

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../services/save_scan_history.dart';
import '../services/image_service.dart';
import 'fish_result_screen.dart';
import '../services/fish_pipeline.dart'; // contains FishPipeline + ScanMode

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

  int _currentCameraIndex = 0;
  Timer? _scanTimer;

  // === Models (through FishPipeline) ===
  bool _modelReady = false;

  // === Scan mode: single fish vs tray ===
  bool _isTrayMode = false; // false = Single Fish, true = Tray

  // === Quality thresholds (still-image QA) ===
  static const double _BLUR_THRESHOLD = 100.0; // tune 80–120 per device
  static const int _QA_MAX_SIDE = 1280; // speed up QA decode

  String _hint = 'Initializing camera…';

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

      // Let camera handle autofocus + auto exposure internally
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
          _hint = _isTrayMode
              ? 'Point camera at multiple fish on a tray'
              : 'Point camera at a single fish';
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

  // If user taps the capture button, show scan animation then capture.
  Future<void> _startScanAndCapture({bool auto = false}) async {
    if (!_isReady || _controller == null || _scanning || _runningInference) {
      return;
    }

    if (!_modelReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Models still loading, please wait...')),
        );
      }
      return;
    }

    setState(() {
      _scanning = true;
      _scanLineY = 0;
      _hint = 'Capturing…';
    });

    final screenHeight = MediaQuery.of(context).size.height;
    _scanTimer?.cancel();
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
    if (!_isReady || _controller == null || _disposed || _runningInference) {
      return;
    }

    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gallery permission denied')),
          );
        }
      }

      final file = await _controller!.takePicture();

      try {
        await PhotoManager.editor.saveImageWithPath(file.path);
      } catch (_) {}

      final processedPath = await _qaAndPreprocess(file.path);
      if (processedPath == null) {
        if (mounted && !_disposed) {
          _hint = _isTrayMode
              ? 'Point camera at multiple fish on a tray'
              : 'Point camera at a single fish';
          setState(() {});
        }
        return;
      }

      await _runDetectorAndModel(processedPath);
    } catch (e) {
      debugPrint('❌ Capture failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  /// Full pipeline after capture:
  /// 1) Run FishPipeline (YOLO + MobileNet for every detected fish)
  /// 2) Save history
  /// 3) Navigate to FishResultScreen with full result map
  Future<void> _runDetectorAndModel(String processedPath) async {
    if (!mounted || _disposed) return;

    setState(() {
      _runningInference = true;
      _hint = 'Analyzing fish...';
    });

    try {
      // 1) Read bytes of the processed image
      final file = File(processedPath);
      final Uint8List imageBytes = await file.readAsBytes();

      // 2) Run the full pipeline (YOLO + MobileNet on each detection)
      final pipelineResult = await FishPipeline.instance.runOnBytes(
        imageBytes,
        mode: _isTrayMode ? ScanMode.tray : ScanMode.single,
      );

      final perFish =
          (pipelineResult['per_fish'] as List<dynamic>?) ?? const [];
      if (perFish.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No fish detected. Please scan again.'),
            ),
          );
          setState(() {
            _hint = _isTrayMode
                ? 'No fish detected — align tray of fish fully in the frame'
                : 'No fish detected — align a single fish in the frame';
          });
        }
        return;
      }

      // 3) Extract overall species/freshness for the big labels
      final String species =
          (pipelineResult['overall_species'] ?? 'Unknown').toString();
      final String freshness =
          (pipelineResult['overall_freshness'] ?? 'Unknown').toString();

      // 4) Save scan history (store the whole pipelineResult as summary)
      try {
        await ScanHistoryService.save(
          species: species,
          freshness: freshness,
          frontImagePath: processedPath,
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

      // 5) Go to result screen
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: processedPath,
            species: species,
            freshnessLabel: freshness,
            result: pipelineResult,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('❌ _runDetectorAndModel error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inference error: $e')),
        );
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _runningInference = false;
          _hint = _isTrayMode
              ? 'Point camera at multiple fish on a tray'
              : 'Point camera at a single fish';
        });
      }
    }
  }

  // ===================== QA + preprocess helpers (still image) =====================

  Future<String?> _qaAndPreprocess(String originalPath) async {
    final decoded =
        await _readRgbaFromPath(originalPath, maxSide: _QA_MAX_SIDE);
    if (decoded == null) return null;
    var rgba = decoded.rgba;
    int w = decoded.w, h = decoded.h;

    final blurScore =
        ImageService.blurScoreVarianceOfLaplacian_Fallback(rgba, w, h, step: 2);
    debugPrint('🧪 Blur score: ${blurScore.toStringAsFixed(1)}');

    if (blurScore < _BLUR_THRESHOLD) {
      final retake = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Looks blurry'),
          content: Text(
            'Sharp photos boost accuracy.\n\n'
            'Blur score: ${blurScore.toStringAsFixed(1)} (threshold: $_BLUR_THRESHOLD)\n'
            'Please retake.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Use Anyway')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Retake')),
          ],
        ),
      );
      if (retake == true) return null;
    }

    rgba = ImageService.equalizeBrightnessFallback(rgba, w, h);
    final processedPath =
        await _encodeRgbaToTempJpeg(rgba, w, h, sourcePath: originalPath);
    return processedPath;
  }

  Future<_RgbaImage?> _readRgbaFromPath(String path,
      {int maxSide = 1280}) async {
    try {
      final bytes = await File(path).readAsBytes();
      final img.Image? im = img.decodeImage(bytes);
      if (im == null) return null;

      img.Image work = im;
      final int maxDim = im.width > im.height ? im.width : im.height;
      if (maxDim > maxSide) {
        final scale = maxSide / maxDim;
        work = img.copyResize(im,
            width: (im.width * scale).round(),
            height: (im.height * scale).round(),
            interpolation: img.Interpolation.average);
      }

      final rgba = work.convert(numChannels: 4); // ensure RGBA
      final Uint8List out =
          Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba));
      return _RgbaImage(out, rgba.width, rgba.height);
    } catch (e) {
      debugPrint('❌ readRgbaFromPath failed: $e');
      return null;
    }
  }

  Future<String> _encodeRgbaToTempJpeg(Uint8List rgba, int w, int h,
      {required String sourcePath}) async {
    final img.Image im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    final jpg = img.encodeJpg(im, quality: 95);
    final Directory tmp = await getTemporaryDirectory();

    final stem = p.basenameWithoutExtension(sourcePath);
    final outPath = p.join(
        tmp.path, '${stem}_proc_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final f = File(outPath);
    await f.writeAsBytes(jpg, flush: true);
    return outPath;
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
    if (!_isReady ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    const stepLabel = 'Capture the FRONT of the fish';

    final statusColor = _runningInference || _scanning
        ? const Color(0xAA455A64)
        : const Color(0xAA1565C0); // neutral/blue

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
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
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
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
          if (!_runningInference && !_scanning)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 110,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

          // Scan animation
          if (_scanning)
            Positioned(
              top: _scanLineY,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color: Colors.cyanAccent,
              ),
            ),

          // === Mode toggle: Single vs Tray ===
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 130,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ModeChip(
                  label: 'Single',
                  selected: !_isTrayMode,
                  onTap: () {
                    if (_isTrayMode) {
                      setState(() {
                        _isTrayMode = false;
                        _hint = 'Point camera at a single fish';
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Tray',
                  selected: _isTrayMode,
                  onTap: () {
                    if (!_isTrayMode) {
                      setState(() {
                        _isTrayMode = true;
                        _hint = 'Point camera at multiple fish on a tray';
                      });
                    }
                  },
                ),
              ],
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
                      onTap: () async {
                        await _startScanAndCapture(auto: false);
                      },
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

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.cyanAccent : Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withOpacity(selected ? 0.0 : 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Small RGBA holder
class _RgbaImage {
  final Uint8List rgba;
  final int w, h;
  _RgbaImage(this.rgba, this.w, this.h);
}
