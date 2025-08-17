// lib/widgets/biometric_gate.dart
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import '../services/biometrics_service.dart';

/// Wrap your HomePage with this to require biometrics on launch / resume.
class BiometricGate extends StatefulWidget {
  const BiometricGate({
    super.key,
    required this.child,
    this.lockAfter = const Duration(minutes: 2), // lock when app returns after this long
    this.blurWhileLocked = true,
  });

  final Widget child;
  final Duration lockAfter;
  final bool blurWhileLocked;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> with WidgetsBindingObserver {
  final _bio = BiometricsService();
  bool _locked = false;
  bool _checking = true; // initial check
  DateTime? _pausedAt;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefAndMaybeLockOnLaunch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadPrefAndMaybeLockOnLaunch() async {
    // read Firestore toggle
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        _biometricsEnabled = (snap.data()?['biometricsEnabled'] ?? false) as bool;
      } catch (_) {}
    }

    // probe device
    final supported = await _bio.isDeviceSupported();
    final types = await _bio.getAvailableBiometrics();
    _biometricsAvailable = supported && types.isNotEmpty;

    // If enabled & available -> lock immediately on first frame
    if (_biometricsEnabled && _biometricsAvailable) {
      setState(() {
        _locked = true;
        _checking = false;
      });
      // wait a tick so overlay builds, then prompt
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
    } else {
      setState(() => _checking = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_biometricsEnabled || !_biometricsAvailable) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      if (away >= widget.lockAfter) {
        setState(() => _locked = true);
        // prompt after overlay is visible
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
      }
    }
  }

  Future<void> _tryUnlock() async {
    if (!_locked) return;

    // First: biometric-only
    var (ok, msg) = await _bio.authenticate(
      allowDeviceCredential: false,
      reason: 'Unlock FishFresh',
    );

    // If failed on Android, offer device credential fallback
    if (!ok && Theme.of(context).platform == TargetPlatform.android) {
      (ok, msg) = await _bio.authenticate(
        allowDeviceCredential: true,
        reason: 'Confirm your identity',
      );
    }

    if (ok) {
      if (!mounted) return;
      setState(() => _locked = false);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Authentication failed or canceled.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_locked) return widget.child;

    // Locked overlay UI
    final overlay = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111A18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23302D)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 36, color: Colors.white),
              const SizedBox(height: 12),
              const Text('Locked', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Unlock with your biometrics to continue.',
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _tryUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF33D9A6),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.blurWhileLocked)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
          )
        else
          Container(color: Colors.black.withOpacity(0.6)),
        overlay,
      ],
    );
  }
}
