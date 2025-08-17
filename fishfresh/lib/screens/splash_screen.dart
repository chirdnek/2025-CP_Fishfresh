// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/biometrics_service.dart';
import '../services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Logo scale animation
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;

  // Text slide + fade animation
  late final AnimationController _textCtrl;
  late final Animation<Offset> _textOffset;
  late final Animation<double> _textFade;

  final _bio = BiometricsService();

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textOffset = Tween<Offset>(
      begin: const Offset(1.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    // Sequence: pause → logo pop → pause → text slide → navigate
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _logoCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _textCtrl.forward();
      if (!mounted) return;
      _goNext();
    });
  }

  Future<void> _goNext() async {
    final storage = StorageService();
    final seen = await storage.hasSeenOnboarding();
    if (!seen) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/onboarding');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    bool needsBiometrics = false;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      needsBiometrics = (snap.data()?['biometricsEnabled'] ?? false) as bool;
    } catch (_) {}

    if (needsBiometrics) {
      final (ok, _) = await _bio.authenticate(
        allowDeviceCredential: true,
        reason: 'Unlock FishFresh',
      );
      debugPrint('Biometric result: $ok');
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Make the logo nice and big but still responsive
    final screenW = MediaQuery.of(context).size.width;
    final rawSize = screenW * 0.30; // 42% of width
    // ignore: unnecessary_cast
    final logoSize = (rawSize.clamp(110.0, 170.0)) as double; // keep within sane bounds

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: Image.asset(
                  'assets/images/logo1.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8), // closer spacing

              FadeTransition(
                opacity: _textFade,
                child: SlideTransition(
                  position: _textOffset,
                  child: const Text(
                    'FishFresh',
                    style: TextStyle(
                      fontSize: 38,              // a bit larger for presence
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
