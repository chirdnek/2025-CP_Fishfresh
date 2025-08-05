// ignore_for_file: unused_import, depend_on_referenced_packages, deprecated_member_use, use_super_parameters, avoid_print

import 'dart:async';
import 'dart:io';

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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomePage extends StatefulWidget {
  final String? localImagePath;
  const HomePage({Key? key, this.localImagePath}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

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

  void _scanFish() async {
    final picker = ImagePicker();
    await picker.pickImage(source: ImageSource.camera);
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