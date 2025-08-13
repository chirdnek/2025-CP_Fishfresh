// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use, use_super_parameters, avoid_print, library_private_types_in_public_api, use_build_context_synchronously, unused_element_parameter

import 'dart:async';
import 'dart:io';

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

import 'faq_screen.dart';
import 'profile_settings_screen.dart';

import 'dart:ui';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomePage extends StatefulWidget {
  final String? localImagePath;
  const HomePage({Key? key, this.localImagePath}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}








/// Full, fixed FishScanCamera
class FishScanCamera extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FishScanCamera({super.key, required this.cameras});

  @override
  State<FishScanCamera> createState() => _FishScanCameraState();
}

class _FishScanCameraState extends State<FishScanCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isFlashOn = false;
  bool _scanning = false;
  double _scanLineY = 0.0;
  int _step = 0; // 0 = front, 1 = back
  String? _frontImagePath;
  String? _backImagePath;
  bool _initializing = true;

  // zoom
  double _zoomLevel = 1.0;
  double _maxZoom = 1.0;
  int _currentCameraIndex = 0;

  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera(index: 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(index: _currentCameraIndex);
    }
  }

  Future<void> _initCamera({required int index}) async {
    try {
      if (widget.cameras.isEmpty) throw Exception('No cameras available');
      _initializing = true;
      setState(() {});
      _controller?.dispose();
      _currentCameraIndex = index;
      final cam = widget.cameras[index];
      _controller = CameraController(cam, ResolutionPreset.high, enableAudio: false);
      await _controller!.initialize();
      // default flash off
      await _controller!.setFlashMode(FlashMode.off);
      // zoom limits
      try {
        _maxZoom = await _controller!.getMaxZoomLevel();
      } catch (_) {
        _maxZoom = 1.0;
      }
      _zoomLevel = 1.0;
    } catch (e) {
      debugPrint('Camera init error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera init failed: $e')));
    } finally {
      _initializing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _isFlashOn = !_isFlashOn;
    try {
      await _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      debugPrint('Flash toggle error: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final newIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    await _initCamera(index: newIndex);
  }

  void _startScanAndCapture() {
    if (_controller == null || !_controller!.value.isInitialized || _scanning) return;

    setState(() {
      _scanning = true;
      _scanLineY = 0;
    });

    // animate scan line down once (smooth)
    _scanTimer?.cancel();
    final screenHeight = MediaQuery.of(context).size.height;
    const stepMs = 12;
    final stepPx = 6.0;
    _scanTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _scanLineY += stepPx;
        // when line reaches near bottom capture and stop
        if (_scanLineY >= screenHeight - 100) {
          _scanning = false;
          t.cancel();
          _capturePictureAfterScan();
        }
      });
    });
  }

  Future<void> _capturePictureAfterScan() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;
      final XFile file = await _controller!.takePicture();

      if (_step == 0) {
        _frontImagePath = file.path;
        _step = 1;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Front captured — now capture the BACK')),
          );
          setState(() {});
        }
      } else {
        _backImagePath = file.path;
        if (mounted) {
          Navigator.of(context).pop(<String, String?>{
            'front': _frontImagePath,
            'back': _backImagePath,
          });
        }
      }
    } catch (e) {
      debugPrint('Capture failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(child: Text('Camera not available', style: TextStyle(color: Colors.white))),
      );
    }

    final size = MediaQuery.of(context).size;

    // compute scale so preview covers the whole screen (no black bars)
    final previewSize = _controller!.value.previewSize!;
    final previewRatio = previewSize.height / previewSize.width;
    final deviceRatio = size.width / size.height;
    final scale = previewRatio / deviceRatio;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // camera preview filling screen (cropped if needed)
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: scale,
                child: Center(child: CameraPreview(_controller!)),
              ),
            ),
          ),

          // top controls: close, flash, switch camera
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close
                _TopCircleButton(
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Row(
                  children: [
                    // flash
                    _TopCircleButton(
                      icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: _isFlashOn ? Colors.yellowAccent : Colors.white,
                      onPressed: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    // switch camera
                    _TopCircleButton(icon: Icons.cameraswitch, onPressed: _switchCamera),
                  ],
                ),
              ],
            ),
          ),

          // step helper (small floating label)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _step == 0 ? 'Step 1 — Capture FRONT of fish' : 'Step 2 — Capture BACK of fish',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),

          // blur + scan line shown only while scanning
          if (_scanning) ...[
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(color: Colors.black.withOpacity(0.15)),
              ),
            ),
            Positioned(
              top: _scanLineY,
              left: 0,
              right: 0,
              child: Container(height: 3, color: Colors.cyanAccent.withOpacity(0.95)),
            ),
          ],

          // zoom slider on right (vertical)
          Positioned(
            right: 6,
            top: size.height * 0.25,
            bottom: size.height * 0.25,
            child: RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: size.height * 0.4,
                child: Slider(
                  min: 1.0,
                  max: _maxZoom < 1.0 ? 1.0 : _maxZoom,
                  value: _zoomLevel.clamp(1.0, _maxZoom),
                  onChanged: (v) async {
                    _zoomLevel = v;
                    try {
                      await _controller!.setZoomLevel(v);
                    } catch (e) {
                      debugPrint('Zoom set error: $e');
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
          ),

          // bottom capture button (scan)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // mini status: front/back indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _smallStatusDot(active: _step == 0),
                    const SizedBox(width: 8),
                    const Text('Front'),
                    const SizedBox(width: 16),
                    _smallStatusDot(active: _step == 1),
                    const SizedBox(width: 8),
                    const Text('Back'),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _startScanAndCapture,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
                    ),
                    child: const Icon(Icons.qr_code_scanner, size: 38, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallStatusDot({required bool active}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: active ? Colors.greenAccent : Colors.white24,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
    );
  }
}

/// small circular top button used above
class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  const _TopCircleButton({required this.icon, required this.onPressed, this.color = Colors.white, super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}


























/// -------------------- Home Page state --------------------
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

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await _fetchUserData();
    await _loadGalleryImages();
  }

  @override
  void initState() {
    super.initState();
    _localImagePath = widget.localImagePath;
    _scrollController = ScrollController()..addListener(_updateDateLabelOnScroll);
    _fetchUserData();
    _loadGalleryImages();
    _initializeFirebaseMessaging();
    getFCMToken();
  }

  void getFCMToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    print("🔑 FCM Token: $token");
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();

      setState(() {
        _firstName = data?['firstName'] ?? 'User';
        _localImagePath = data?['localImagePath'];
      });
    } catch (e) {
      print("Error fetching user data: $e");
    }
  }

  void _initializeFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

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
    if (permissionState.isAuth) {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
      final recentMedia = await albums.first.getAssetListPaged(page: 0, size: 60);
      setState(() {
        _galleryImages.addAll(recentMedia);
        _isLoading = false;
      });
    } else {
      PhotoManager.openSetting();
    }
  }

  void _updateDateLabelOnScroll() {
    if (!_scrollController.hasClients || _galleryImages.isEmpty) return;
    final itemHeight = 130;
    final index = (_scrollController.offset / itemHeight).floor();
    if (index >= 0 && index < _galleryImages.length) {
      final formatted = DateFormat("MMMM yyyy").format(_galleryImages[index].createDateTime);
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
      final cameras = await availableCameras();
      final result = await Navigator.push<Map<String, String?>>(
        context,
        MaterialPageRoute(builder: (_) => FishScanCamera(cameras: cameras)),
      );

      if (result != null) {
        debugPrint("Front fish image: ${result['front']}");
        debugPrint("Back fish image: ${result['back']}");

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Images captured')),
        );
      }
    } catch (e) {
      debugPrint('Open camera error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open camera: $e')),
      );
    }
  }
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.help_outline, color: Colors.white),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen()));
          },
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundImage: (_localImagePath != null && File(_localImagePath!).existsSync())
                ? FileImage(File(_localImagePath!))
                : const AssetImage('assets/images/avatar.jpg') as ImageProvider,
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
        const Text('Recents',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                                    await picker.pickImage(source: ImageSource.gallery);
                                  },
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
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image(
                                  image: AssetEntityImageProvider(asset,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize.square(200)),
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                        ),
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
                  _buildNavIcon(Icons.home, 0),
                  _buildNavIcon(Icons.history, 1),
                ],
              ),
            ),
            GestureDetector(
              onTap: _scanFish,
              child: Container(
                height: 55,
                width: 55,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 30),
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
        child: Icon(icon, color: isSelected ? Colors.white : Colors.black, size: 28),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hideDateTimer?.cancel();
    super.dispose();
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
              child: Image.asset('assets/images/fish_koi.png', width: 250, fit: BoxFit.contain),
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
                      const SizedBox(height: 100), // ensures scroll works even with short content
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
