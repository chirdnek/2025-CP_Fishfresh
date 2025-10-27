// lib/screens/home.dart
// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use, use_super_parameters, avoid_print, library_private_types_in_public_api, use_build_context_synchronously, unused_element_parameter, unused_element, sort_child_properties_last, duplicate_import, unnecessary_import, unused_local_variable, unused_field, curly_braces_in_flow_control_structures, avoid_single_cascade_in_expression_statements, unnecessary_null_comparison

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:fishfresh/widgets/biometric_gate.dart';
import 'faq_screen.dart';
import 'profile_settings_screen.dart';
import 'fish_result_screen.dart';
import 'fish_scan_camera.dart';
import 'package:fishfresh/screens/history.dart';
import 'almanac_screen.dart';

// ✅ multi-model runtime
import '../services/fish_runtime.dart';
import '../services/model_registry.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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


  // ✅ runtime lives here (manages exactly one model at a time)
  final FishRuntime _runtime = FishRuntime();
  bool _runtimeReady = false;

  // Default model (change as desired)
  ModelDef _activeModel = ModelRegistry.efficient; // or .mobilenet / .resnet

  @override
  void initState() {
    super.initState();
    _localImagePath = widget.localImagePath;
    _scrollController = ScrollController()..addListener(_updateDateLabelOnScroll);
    _fetchUserData();
    _loadGalleryImages();
    _initializeFirebaseMessaging();
  
    _initRuntime(); // warm up selected model
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hideDateTimer?.cancel();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _initRuntime() async {
    setState(() => _runtimeReady = false);
    try {
      await _runtime.load(_activeModel);
      if (!mounted) return;
      setState(() => _runtimeReady = true);
    } catch (e, st) {
      debugPrint('[FishRuntime] init error: $e\n$st');
      if (!mounted) return;
      setState(() => _runtimeReady = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model load failed: $e')),
      );
    }
  }

  Future<void> _switchModel(ModelDef def) async {
    setState(() {
      _runtimeReady = false;
      _activeModel = def;
    });
    try {
      await _runtime.load(def);
      if (!mounted) return;
      setState(() => _runtimeReady = true);
    } catch (e, st) {
      debugPrint('[FishRuntime] switch error: $e\n$st');
      if (!mounted) return;
      setState(() => _runtimeReady = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switching model failed: $e')),
      );
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _fetchUserData();
    await _loadGalleryImages();
  }

  // Single-image helper (still kept for fallback paths)
  Future<void> _runPrediction(String imagePath) async {
    try {
      if (!_runtime.ready) {
        await _initRuntime();
      }
      if (!_runtime.ready) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model not ready')),
        );
        return;
      }

      final pred = await _runtime.predictWithTiming(imagePath);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            frontImagePath: imagePath,
            backImagePath: imagePath, // fallback to show two tiles
            species: (pred['predicted_species'] ?? '') as String,
            freshnessLabel: (pred['predicted_freshness'] ?? '') as String,
            result: pred,
            modelName: _activeModel.name,
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
Future<void> _runPredictionPair(String frontPath, String backPath) async {
  try {
    if (!_runtime.ready) await _initRuntime();

    Map<String, dynamic> pred;
    try {
      pred = await _runtime.model.predictPair(frontPath, backPath);
    } catch (_) {
      pred = await _runtime.predictWithTiming(frontPath);
    }

    // Save to Firestore (same as camera flow)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docRef = FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("scanHistory")
          .doc();

      await docRef.set({
        "fishId": docRef.id,
        "species": pred["predicted_species"],
        "freshness": pred["predicted_freshness"],
        "timestamp": FieldValue.serverTimestamp(),
        "frontImagePath": frontPath,
        "backImagePath": backPath,
        "modelName": _activeModel.name,     // 👈 also store which model was used
        "userId": user.uid,
      });
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FishResultScreen(
          frontImagePath: frontPath,
          backImagePath: backPath,
          species: (pred["predicted_species"] ?? '') as String,
          freshnessLabel: (pred["predicted_freshness"] ?? '') as String,
          result: pred,
          modelName: _activeModel.name,
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


bool _isPicking = false;

void _toast(String msg) {
  if (!mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}

/// Open the system picker, but **enforce exactly two**.
/// If user selects more than two, we either trim (with consent) or
/// fall back to explicit FRONT → BACK picking.
Future<void> _pickTwoPhotosStrict() async {
  if (_isPicking) return;
  _isPicking = true;

  try {
    final picker = ImagePicker();

    _toast('Select exactly TWO photos: FRONT then BACK.');
    final multi = await picker.pickMultiImage(
      imageQuality: 95,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    // Cancelled
    if (multi == null || multi.isEmpty) return;

    // ✅ Exactly 2 → use in order (first = FRONT, second = BACK)
    if (multi.length == 2) {
      await _runPredictionPair(multi[0].path, multi[1].path);
      return;
    }

    // ❗ Only one → explicitly pick the BACK next
    if (multi.length == 1) {
      _toast('Now select the BACK image.');
      final back = await picker.pickImage(source: ImageSource.gallery);
      if (back == null) return;
      await _runPredictionPair(multi[0].path, back.path);
      return;
    }

    // ❌ More than 2 → ask the user what to do
    final useFirstTwo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select only two'),
        content: Text('You selected ${multi.length} photos. '
            'Use the first two as FRONT and BACK, or re-pick?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Re-pick'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use first two'),
          ),
        ],
      ),
    );

    if (useFirstTwo == true) {
      await _runPredictionPair(multi[0].path, multi[1].path);
      return;
    }

    // Re-pick sequentially (explicit FRONT → BACK)
    final front = await picker.pickImage(source: ImageSource.gallery);
    if (front == null) return;
    _toast('Great. Now select the BACK image.');
    final back = await picker.pickImage(source: ImageSource.gallery);
    if (back == null) return;

    await _runPredictionPair(front.path, back.path);
  } finally {
    _isPicking = false;
  }
}


Future<void> _pickTwoFromSystemGallery() async {
  final picker = ImagePicker();

  // Try multi-select first (best UX on Android 13+ / iOS 14+)
  _toast('Select exactly TWO photos: FRONT then BACK.');
  final multi = await picker.pickMultiImage(
    imageQuality: 95,
    maxWidth: 2048,
    maxHeight: 2048,
  );

  // User canceled
  if (multi == null || multi.isEmpty) return;

  // ✅ Exactly two selected → use them in the order the picker returns
  if (multi.length == 2) {
    final front = multi[0].path;
    final back  = multi[1].path;
    await _runPredictionPair(front, back);
    return;
  }

  // ❌ More than two → ask them to try again (don’t guess)
  if (multi.length > 2) {
    _toast('Please select exactly TWO photos. You picked ${multi.length}. Try again.');
    // reopen picker sequentially so order is explicit
    final front = await picker.pickImage(source: ImageSource.gallery);
    if (front == null) return;

    _toast('Great. Now select the BACK image.');
    final back = await picker.pickImage(source: ImageSource.gallery);
    if (back == null) return;

    await _runPredictionPair(front.path, back.path);
    return;
  }

  // ❗ Only one selected → prompt for BACK image explicitly
  final first = multi.first.path;
  _toast('Now select the BACK image.');
  final back = await picker.pickImage(source: ImageSource.gallery);
  if (back == null) return;

  await _runPredictionPair(first, back.path);
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
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);

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

    final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) {
      if (!mounted) return;
      setState(() {
        _galleryImages
          ..clear();
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

  void _updateDateLabelOnScroll() {
    if (!_scrollController.hasClients || _galleryImages.isEmpty) return;
    const itemHeight = 130;
    final index = (_scrollController.offset / itemHeight).floor();
    if (index >= 0 && index < _galleryImages.length) {
      final formatted = DateFormat("MMMM yyyy").format(_galleryImages[index].createDateTime);
      setState(() {
        _currentDateLabel = formatted;
        _showDateLabel = true;
      });
      _hideDateTimer?.cancel();
      _hideDateTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showDateLabel = false);
      });
    }
  }

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

      final result = await Navigator.push<Map<String, String?>>(
        context,
        MaterialPageRoute(builder: (_) => FishScanCamera(cameras: _cachedCameras!)),
      );

      if (result == null || result['front'] == null) return;

      final frontPath = result['front']!;
      final backPath = result['back'] ?? frontPath; // ensure we always have two

      if (!_runtime.ready) {
        await _initRuntime();
      }
      if (!_runtime.ready) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model not ready')),
        );
        return;
      }

      // Try pair prediction; fallback handled inside
      Map<String, dynamic> pred;
      try {
        pred = await _runtime.model.predictPair(frontPath, backPath);
      } catch (_) {
        pred = await _runtime.predictWithTiming(frontPath);
      }
      if (!mounted) return;

      // Save to Firestore under current user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .collection("scanHistory")
            .doc();

        await docRef.set({
          "fishId": docRef.id,
          "species": pred["predicted_species"],
          "freshness": pred["predicted_freshness"],
          "timestamp": FieldValue.serverTimestamp(),
          "frontImagePath": frontPath,
          "backImagePath": backPath,
          "userId": user.uid,
        });
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            frontImagePath: frontPath,
            backImagePath: backPath,
            species: (pred["predicted_species"] ?? '') as String,
            freshnessLabel: (pred["predicted_freshness"] ?? '') as String,
            result: pred,
            modelName: _activeModel.name,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Scan error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    }
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // FAQ button
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen()));
              },
            ),

            // Almanac logo button
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => FishAlmanacPage()));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Image.asset(
                  "assets/images/logo1.png",
                  height: 32,
                  width: 32,
                ),
              ),
            ),
          ],
        ),

        // Profile button
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
          ),
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
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Hi ${_firstName ?? 'User'}!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
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
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
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
                    child: Text('No images found.', style: TextStyle(color: Colors.grey)),
                  )
                : Stack(
                    children: [
                      Scrollbar(
                        thumbVisibility: true,
                        controller: _scrollController,
                        child: GridView.builder(
                          controller: _scrollController,
                          itemCount: _galleryImages.length + 1,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, index) {
                            // ── Top-left tile: opens OS picker to select TWO photos ──
                            if (index == 0) {
                              return GestureDetector(
                                onTap: _pickTwoFromSystemGallery,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.photo_library,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              );
                            }

                            // ── All other tiles are previews ONLY (scrollable, not tappable) ──
                            final asset = _galleryImages[index - 1];
                            return FutureBuilder<File?>(
                              future: asset.file,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  );
                                }
                                final file = snapshot.data!;
                                return AbsorbPointer( // ← block taps; still scrolls
                                  absorbing: true,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // ── Date label while scrolling ──
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Home button
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedNavIndex = 0);
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 0 ? Colors.black : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.home,
                        color: _selectedNavIndex == 0 ? Colors.white : Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                  // History button
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedNavIndex = 1);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 1 ? Colors.black : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.history,
                        color: _selectedNavIndex == 1 ? Colors.white : Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Scan button (disabled if model not ready)
            GestureDetector(
              onTap: _runtimeReady ? _scanFish : null,
              child: Opacity(
                opacity: _runtimeReady ? 1.0 : 0.5,
                child: Container(
                  height: 55,
                  width: 55,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = index),
      child: Container(
        height: 45,
        width: 45,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.black,
          size: 28,
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
              child: Image.asset(
                'assets/images/fish_koi.png',
                width: 250,
                fit: BoxFit.contain,
              ),
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


