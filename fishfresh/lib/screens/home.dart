// lib/screens/home.dart
// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use, use_super_parameters, avoid_print, library_private_types_in_public_api, use_build_context_synchronously, unused_element_parameter, unused_element, sort_child_properties_last, duplicate_import, unnecessary_import, unused_local_variable, unused_field, curly_braces_in_flow_control_structures, avoid_single_cascade_in_expression_statements, unnecessary_null_comparison, prefer_final_fields, no_leading_underscores_for_local_identifiers, prefer_conditional_assignment, prefer_is_empty

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart'; // image cache caps
import 'package:flutter/foundation.dart'; // compute()
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:image/image.dart' as img; // <-- for downscaling
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:fishfresh/widgets/biometric_gate.dart';
import 'faq_screen.dart';
import 'profile_settings_screen.dart';
import 'fish_result_screen.dart';
import 'fish_scan_camera.dart';
import 'package:fishfresh/screens/history.dart';
import 'almanac_screen.dart';

// 👇 NEW: external gallery picker screen
import 'gallery.dart';

// === Single-model import (used for gallery-only prediction) ===
import '../services/fish_model.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/* ───────────────────────── IMAGE DOWNSCALE (ISOLATE) ───────────────────────── */
// Top-level entry for compute(). Returns output path (or original on failure).
String _resizeEntry(Map<String, dynamic> args) {
  final String src = args['src'] as String;
  final int maxDim = args['maxDim'] as int;
  final String outPath = args['out'] as String;

  try {
    final bytes = File(src).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return src;

    final w = decoded.width, h = decoded.height;
    if (w <= maxDim && h <= maxDim) return src;

    // keep aspect ratio; limit longest side to maxDim
    final bool wide = w >= h;
    final resized = img.copyResize(
      decoded,
      width: wide ? maxDim : null,
      height: wide ? null : maxDim,
      interpolation: img.Interpolation.average,
    );

    final jpg = img.encodeJpg(resized, quality: 85);
    File(outPath).writeAsBytesSync(jpg, flush: true);
    return outPath;
  } catch (_) {
    return src;
  }
}

Future<String> _downscaleIfNeeded(String srcPath, {int maxDim = 1024}) async {
  final tmpDir = await getTemporaryDirectory();
  final outPath = p.join(
    tmpDir.path,
    'ff_tmp_${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(srcPath)}.jpg',
  );
  return compute(_resizeEntry, {'src': srcPath, 'maxDim': maxDim, 'out': outPath});
}

/* ───────────────────────── HOME SCREEN ───────────────────────── */
class HomePage extends StatefulWidget {
  final String? localImagePath;
  const HomePage({Key? key, this.localImagePath}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    // ✅ keep image cache in check (helps stability on low-RAM)
    PaintingBinding.instance.imageCache.maximumSize = 150;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // ~50MB

    return MaterialApp(
      title: 'FishFresh',
      debugShowCheckedModeBanner: false,
      home: const BiometricGate(
        child: HomePage(),
        lockAfter: Duration(minutes: 2),
      ),
    );
  }
}

// Cached cameras (file-level)
List<CameraDescription>? _cachedCameras;

class _HomePageState extends State<HomePage> {
  String? _localImagePath;
  String? _firstName = 'User';
  bool _isLoading = true;
  int _selectedNavIndex = 0;

  final List<AssetEntity> _galleryImages = [];
  late ScrollController _scrollController;
  Timer? _hideDateTimer;
  String? _currentDateLabel;
  bool _showDateLabel = false;

  // === Single model instance here (for gallery-only prediction) ===
  final FishModel _fishModel = FishModel();
  bool _modelReady = false;

  // UI helpers
  bool _isPicking = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _localImagePath = widget.localImagePath;
    _scrollController = ScrollController()..addListener(_updateDateLabelOnScroll);
    _fetchUserData();
    _loadGalleryImages();
    _initializeFirebaseMessaging();
    _getFCMToken();

    // warm up model (once) – used only for gallery predictions
    () async {
      await _fishModel.ensureInited();
      if (mounted) setState(() => _modelReady = true);
    }();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hideDateTimer?.cancel();
    _fishModel.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _fetchUserData();
    await _loadGalleryImages();
  }

  void _getFCMToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint("🔑 FCM Token: $token");
  }

  // ---------- confidence helpers ----------
  double _norm01(num v) => v.toDouble() > 1.0 ? v.toDouble() / 100.0 : v.toDouble();

  Map<String, double>? _asDoubleMap(dynamic m) {
    if (m is Map) {
      return m.map((k, v) => MapEntry(
            k.toString(),
            (v is num) ? _norm01(v) : (double.tryParse(v.toString()) ?? 0.0),
          ));
    }
    return null;
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();

      if (!mounted) return;
      setState(() {
        _firstName = data?['firstName'] ?? 'User';
        _localImagePath = data?['localImagePath'];
      });
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    }
  }

  void _initializeFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;
    final settings =
        await messaging.requestPermission(alert: true, badge: true, sound: true);

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final android = message.notification?.android;

        if (notification != null && android != null) {
          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'high_importance_channel',
                'High Importance Notifications',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadGalleryImages() async {
    final permissionState = await PhotoManager.requestPermissionExtend();
    if (!permissionState.isAuth) {
      PhotoManager.openSetting();
      return;
    }

    final albums =
        await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) {
      if (!mounted) return;
      setState(() {
        _galleryImages.clear();
        _isLoading = false;
      });
      return;
    }

    final recentMedia = await albums.first.getAssetListPaged(page: 0, size: 60);
    if (!mounted) return;
    setState(() {
      _galleryImages
        ..clear()
        ..addAll(recentMedia);
      _isLoading = false;
    });
  }

  // ✅ throttle: only setState if label actually changes
  void _updateDateLabelOnScroll() {
    if (!_scrollController.hasClients || _galleryImages.isEmpty) return;
    const itemHeight = 130;
    final index = (_scrollController.offset / itemHeight).floor();
    if (index < 0 || index >= _galleryImages.length) return;

    final newLabel =
        DateFormat("MMMM yyyy").format(_galleryImages[index].createDateTime);
    if (newLabel == _currentDateLabel) return;

    setState(() {
      _currentDateLabel = newLabel;
      _showDateLabel = true;
    });
    _hideDateTimer?.cancel();
    _hideDateTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showDateLabel = false);
    });
  }

  // ======== SINGLE prediction (gallery) – one photo only ========
  Future<void> _runPredictionSingle(String imagePath) async {
    try {
      if (!_modelReady) {
        await _fishModel.ensureInited();
        _modelReady = true;
      }

      final dsPath = await _downscaleIfNeeded(imagePath, maxDim: 1024);

      final sw = Stopwatch()..start();
      final pred = await _fishModel.predict(dsPath);
      sw.stop();

      String species   = (pred["predicted_species"] ?? "Unknown").toString();
      String freshness = (pred["predicted_freshness"] ?? "Unknown").toString();

      double? confidence;
      if (pred["confidence"] is num) {
        confidence = _norm01(pred["confidence"] as num);
      } else {
        // if future versions add species_scores etc.
        final speciesScores = _asDoubleMap(pred["species_scores"]);
        if (speciesScores != null && speciesScores.isNotEmpty) {
          confidence = speciesScores[species] ??
              speciesScores[species.toLowerCase()] ??
              speciesScores.values.reduce(max);
        }
      }

      confidence ??= 0.0;
      confidence = confidence.clamp(0.0, 1.0);

      // Save best-effort (non-blocking)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .collection("scanHistory")
            .doc();
        docRef.set({
          "fishId": docRef.id,
          "species": species,
          "freshness": freshness,
          "confidence": confidence,
          "timestamp": FieldValue.serverTimestamp(),
          "frontImagePath": dsPath,
          "backImagePath": null,
          "userId": user.uid,
        });
      }

      if (!mounted) return;

      // Pack full result for FishResultScreen (it can show summary info)
      final packed = <String, dynamic>{
        ...pred,
        "confidence": confidence,
        "latency_ms": sw.elapsedMilliseconds,
        "species": species,
        "freshness": freshness,
      };

      debugPrint(
        "➡️ [Gallery] $species | $freshness | ${(confidence * 100).toStringAsFixed(1)}%",
      );

      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: dsPath,
            species: species,
            freshnessLabel: freshness,
            result: packed,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Prediction error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Prediction failed: $e")),
      );
    }
  }

  // ======== Full-screen gallery picker (select exactly 1 image) ========
  Future<void> _openFullGallerySelector() async {
    final res = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
    if (res == null) return;
    await _runPredictionSingle(res);
  }

  // ======== Camera scan (single-shot) – YOLO+MobileNet handled inside FishScanCamera ========
  Future<void> _scanFish() async {
    try {
      _cachedCameras ??= await availableCameras();
      if (_cachedCameras == null || _cachedCameras!.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cameras available')),
        );
        return;
      }

      // We no longer wait for any result map; pipeline + result screen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FishScanCamera(cameras: _cachedCameras!)),
      );
    } catch (e) {
      debugPrint("❌ Scan error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    }
  }

  // ======== UI pieces ========
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen()));
              },
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => FishAlmanacPage()));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Image.asset("assets/images/logo1.png", height: 32, width: 32),
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
          child: CircleAvatar(
            radius: 20,
            backgroundImage: (_localImagePath != null)
                ? (_localImagePath!.startsWith('assets/')
                    ? AssetImage(_localImagePath!)
                    : FileImage(File(_localImagePath!))) as ImageProvider
                : const AssetImage('assets/images/avatar.jpg'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2BFFC4), Colors.white],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          child: const Text(
            'Fish Fresh',
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Hi ${_firstName ?? 'User'}!',
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 250,
          child: Text(
            'This app helps you check the freshness of fish in seconds. Simply snap a photo, and our AI analyzes it.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildRecents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recents',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(12),
          ),
          height: 370,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : (_galleryImages.isEmpty)
                  ? const Center(
                      child: Text('No images found.', style: TextStyle(color: Colors.grey)))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          // === GRID ===
                          GridView.builder(
                            controller: _scrollController,
                            itemCount: _galleryImages.length + 1,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                            itemBuilder: (context, index) {
                              // first tile = open picker
                              if (index == 0) {
                                return GestureDetector(
                                  onTap: _openFullGallerySelector,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.photo_library,
                                        color: Colors.white, size: 40),
                                  ),
                                );
                              }

                              final asset = _galleryImages[index - 1];
                              // ✅ thumbnail provider (fast + cached), tiles non-clickable
                              return AbsorbPointer(
                                absorbing: true,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image(
                                    image: AssetEntityImageProvider(
                                      asset,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize(300, 300),
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),

                          // === DATE LABEL ===
                          if (_showDateLabel && _currentDateLabel != null)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _currentDateLabel!,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 25, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              height: 55,
              width: 130,
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Home
                  GestureDetector(
                    onTap: () => setState(() => _selectedNavIndex = 0),
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 0 ? Colors.black : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.home,
                          color: _selectedNavIndex == 0 ? Colors.white : Colors.black, size: 28),
                    ),
                  ),
                  // History
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedNavIndex = 1);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const HistoryPage()));
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 1 ? Colors.black : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.history,
                          color: _selectedNavIndex == 1 ? Colors.white : Colors.black, size: 28),
                    ),
                  ),
                ],
              ),
            ),
            // Scan (always enabled, camera handles its own model init)
            GestureDetector(
              onTap: _scanFish,
              child: Container(
                height: 55,
                width: 55,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.black, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 3, 1, 1),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: -50,
              child: Image.asset('assets/images/fish_koi.png',
                  width: 250, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildTopBar(),
                      const SizedBox(height: 20),
                      _buildHeader(),
                      const SizedBox(height: 30),
                      _buildRecents(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
            _buildBottomNavBar(),
          ],
        ),
      ),
    );
  }
}
