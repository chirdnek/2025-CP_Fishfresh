// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use, use_super_parameters, avoid_print, library_private_types_in_public_api, use_build_context_synchronously, unused_element_parameter, unused_element, sort_child_properties_last, duplicate_import, unnecessary_import, unused_local_variable, unused_field, curly_braces_in_flow_control_structures

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
import 'package:fishfresh/screens/fish_result_screen.dart';
import '../services/fish_model.dart';
import 'fish_scan_camera.dart';
import 'package:fishfresh/screens/history.dart';
import 'almanac_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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

/* ───────────────────────── HOME SCREEN ───────────────────────── */
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

  // ✅ model instance lives here
  final _fishModel = FishModel();
  bool _modelReady = false;

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _fetchUserData();
    await _loadGalleryImages();
  }

  Future<void> _runPrediction(String imagePath) async {
    try {
      if (!_modelReady) {
        await _fishModel.init();
        _modelReady = true;
      }

      final pred = await _fishModel.predict(imagePath);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: imagePath,
            species: pred["predicted_species"] as String,
            freshnessLabel: pred["predicted_freshness"] as String,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Prediction error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Prediction failed: $e")));
    }
  }

  @override
  void initState() {
    super.initState();
    _localImagePath = widget.localImagePath;
    _scrollController = ScrollController()
      ..addListener(_updateDateLabelOnScroll);
    _fetchUserData();
    _loadGalleryImages();
    _initializeFirebaseMessaging();
    getFCMToken();

    // warm up model
    () async {
      await _fishModel.init();
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

  void getFCMToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    debugPrint("🔑 FCM Token: $token");
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();

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
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

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

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    final recentMedia = await albums.first.getAssetListPaged(page: 0, size: 60);
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
      final formatted = DateFormat(
        "MMMM yyyy",
      ).format(_galleryImages[index].createDateTime);
      setState(() {
        _currentDateLabel = formatted;
        _showDateLabel = true;
      });
      _hideDateTimer?.cancel();
      _hideDateTimer = Timer(const Duration(seconds: 2), () {
        setState(() => _showDateLabel = false);
      });
    }
  }

  Future<void> _scanFish() async {
    try {
      _cachedCameras ??= await availableCameras();
      if (_cachedCameras == null || _cachedCameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No cameras available')));
        }
        return;
      }

      // Capture front + back images
      final result = await Navigator.push<Map<String, String?>>(
        context,
        MaterialPageRoute(
          builder: (_) => FishScanCamera(cameras: _cachedCameras!),
        ),
      );

      if (result == null || result['front'] == null || result['back'] == null) {
        return;
      }

      final frontPath = result['front']!;
      final backPath = result['back']!;

      // Init model if needed
      if (!_modelReady) {
        await _fishModel.init();
        _modelReady = true;
      }

      // Run prediction
      final pred = await _fishModel.predictPair(frontPath, backPath);

      if (!mounted) return;

      // ✅ Save to Firestore under current user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .collection("scanHistory")
            .doc(); // auto ID

        await docRef.set({
          "fishId": docRef.id,
          "species": pred["predicted_species"],
          "freshness": pred["predicted_freshness"],
          "timestamp": FieldValue.serverTimestamp(), // ✅ proper Timestamp
          "frontImagePath": frontPath, // local-only
          "backImagePath": backPath, // local-only
          "userId": user.uid,
        });
      }
      debugPrint("➡️ Navigating to FishResultScreen with $frontPath");
      // ✅ Navigate to FishResultScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishResultScreen(
            imagePath: frontPath,
            species: pred["predicted_species"] as String,
            freshnessLabel: pred["predicted_freshness"] as String,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Scan error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FAQScreen()),
              );
            },
          ),

          // Almanac logo button
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FishAlmanacPage()), // 👈 your almanac screen
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Image.asset(
                "assets/images/logo1.png", // 👈 replace with your almanac logo
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
                        : FileImage(File(_localImagePath!)))
                    as ImageProvider
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
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _galleryImages.isEmpty
              ? const Center(
                  child: Text(
                    'No images found.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Stack(
                  children: [
                    Scrollbar(
                      thumbVisibility: true,
                      controller: _scrollController,
                      child: GridView.builder(
                        controller: _scrollController,
                        itemCount: _galleryImages.length + 1,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return GestureDetector(
                              onTap: () async {
                                final picker = ImagePicker();
                                final picked = await picker.pickImage(
                                  source: ImageSource.gallery,
                                );
                                if (picked != null) {
                                  await _runPrediction(
                                    picked.path,
                                  ); // ✅ run model here
                                }
                              },
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
                              return GestureDetector(
                                onTap: () async {
                                  await _runPrediction(
                                    file.path,
                                  ); // ✅ run model when tapped
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(file, fit: BoxFit.cover),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (_showDateLabel && _currentDateLabel != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _currentDateLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
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
                      // stays on home
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 0
                            ? Colors.black
                            : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.home,
                        color: _selectedNavIndex == 0
                            ? Colors.white
                            : Colors.black,
                        size: 28,
                      ),
                    ),
                  ),

                  // History button
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedNavIndex = 1);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistoryPage(),
                        ), // 👈 your history.dart
                      );
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        color: _selectedNavIndex == 1
                            ? Colors.black
                            : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.history,
                        color: _selectedNavIndex == 1
                            ? Colors.white
                            : Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scan button
            GestureDetector(
              onTap: _scanFish,
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
