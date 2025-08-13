// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fishfresh/screens/profile_screens.dart';
import 'package:fishfresh/screens/login.dart';
import 'package:local_auth/local_auth.dart';
import 'package:fishfresh/services/biometrics_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  /// Biometrics toggle state
  bool _isBiometricsEnabled = false;

  String _firstName = '';
  String _lastName = '';
  String? _localImagePath;

  final _bio = BiometricsService();
  bool _isSupported = false;
  List<BiometricType> _availableTypes = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _fetchUserName();
    await _loadBiometricsState();
    await _probeDeviceBiometrics();
  }

  Future<void> _fetchUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      final data = doc.data();
      setState(() {
        _firstName = data?['firstName'] ?? '';
        _lastName = data?['lastName'] ?? '';
        _localImagePath = data?['localImagePath'];
      });
    } catch (e) {
      debugPrint("Error fetching name: $e");
    }
  }

  Future<void> _probeDeviceBiometrics() async {
    final supported = await _bio.isDeviceSupported();
    final types = await _bio.getAvailableBiometrics();
    setState(() {
      _isSupported = supported;
      _availableTypes = types;
    });
  }

  Future<void> _loadBiometricsState() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snap.data();
      setState(() {
        _isBiometricsEnabled = (data?['biometricsEnabled'] ?? false) as bool;
      });
    } catch (e) {
      debugPrint('loadBiometricsState: $e');
    }
  }

  Future<void> _saveBiometricsState(bool enabled) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'biometricsEnabled': enabled,
        // store which types were available when toggled
        'biometricTypes': _availableTypes.map((e) => e.name).toList(),
        'biometricsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveBiometricsState: $e');
    }
  }

  String _biometricLabel() {
    final t = _availableTypes.toSet();
    if (t.contains(BiometricType.face)) return 'Face ID';
    if (t.contains(BiometricType.iris)) return 'Iris';
    if (t.contains(BiometricType.fingerprint)) {
      return Platform.isIOS ? 'Touch ID' : 'Fingerprint';
    }
    return 'Biometrics';
  }

  Future<void> _onToggleBiometrics(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (!_isSupported || _availableTypes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometrics not available on this device.')),
        );
        return;
      }

      if (value) {
        // 1) Try biometric-only
        var (ok, msg) = await _bio.authenticate(
          allowDeviceCredential: false,
          reason: 'Enable ${_biometricLabel()} for security',
        );

        // 2) If failed on Android, allow device credential fallback
        if (!ok && Theme.of(context).platform == TargetPlatform.android) {
          (ok, msg) = await _bio.authenticate(
            allowDeviceCredential: true,
            reason: 'Confirm your identity',
          );
        }

        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(msg ?? '${_biometricLabel()} authentication failed or canceled.'),
            ),
          );
          return;
        }

        await _saveBiometricsState(true);
        setState(() => _isBiometricsEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_biometricLabel()} enabled.')),
        );
      } else {
        final shouldDisable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Disable biometrics?'),
            content: const Text('You will no longer be asked to use biometrics.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Disable')),
            ],
          ),
        );
        if (shouldDisable != true) return;

        await _saveBiometricsState(false);
        setState(() => _isBiometricsEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometrics disabled.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testBiometrics() async {
    if (!_isBiometricsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable biometrics first.')),
      );
      return;
    }
    final (success, msg) =
        await _bio.authenticate(allowDeviceCredential: false, reason: 'Authenticate');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            success ? 'Authentication success.' : (msg ?? 'Authentication failed or canceled.')),
      ),
    );
  }

  /// Full sign-out (Google + Firebase) so the Google account chooser shows next time.
  Future<void> _fullSignOut() async {
    final auth = FirebaseAuth.instance;

    final providers =
        auth.currentUser?.providerData.map((p) => p.providerId).toList() ?? [];
    if (providers.contains('google.com')) {
      final google = GoogleSignIn();
      try {
        await google.disconnect(); // revoke consent if possible
      } catch (_) {}
      try {
        await google.signOut(); // clear cached account
      } catch (_) {}
    }

    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF000000);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                Transform.translate(
                  offset: const Offset(0, -40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileCard(),
                        const SizedBox(height: 24),
                        _buildSettingsList(),
                        const SizedBox(height: 24),
                        _buildLegalSection(),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
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
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                _buildTopIcons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopIcons() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.question_mark_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundImage: _localImagePath != null
                    ? FileImage(File(_localImagePath!))
                    : const AssetImage('assets/images/avatar.jpg') as ImageProvider,
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A5A4A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundImage: _localImagePath != null
                ? FileImage(File(_localImagePath!))
                : const AssetImage('assets/images/avatar.jpg') as ImageProvider,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '$_firstName $_lastName',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            child: const Icon(Icons.edit, color: Colors.white70, size: 22),
          ),
        ],
      ),
    );
  }

  /// FIXED: balanced braces/parentheses and working logout
  Widget _buildSettingsList() {
    final biometricsTitle = _biometricLabel();
    final sub = !_isSupported || _availableTypes.isEmpty
        ? 'Biometrics not available'
        : _isBiometricsEnabled
            ? 'Enabled • $biometricsTitle'
            : 'Use $biometricsTitle to secure the app';

    return Column(
      children: [
        // Biometrics with working toggle
        _settingItem(
          icon: Icons.lock_outline_rounded,
          title: biometricsTitle,
          subtitle: sub,
          trailing: Switch(
            value: _isBiometricsEnabled,
            onChanged: (_isSupported && _availableTypes.isNotEmpty && !_busy)
                ? _onToggleBiometrics
                : null,
            activeTrackColor: const Color(0xFF28C18E),
            activeColor: Colors.white,
            inactiveTrackColor: Colors.grey[800],
            inactiveThumbColor: Colors.grey[400],
          ),
          onTap: () async {
            if (!_isSupported || _availableTypes.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Biometrics not available on this device.')),
              );
              return;
            }
            if (_isBiometricsEnabled) {
              await _testBiometrics();
            }
          },
        ),

        // Helper row to quickly test/enable
        if (_isSupported && _availableTypes.isNotEmpty)
          _settingItem(
            icon: Icons.verified_user_outlined,
            title: _isBiometricsEnabled ? 'Test now' : 'Set up biometrics',
            subtitle: _isBiometricsEnabled
                ? 'Make sure your ${_biometricLabel()} works'
                : 'Enable the switch above to turn on ${_biometricLabel()}',
            onTap: () async {
              if (_isBiometricsEnabled) {
                await _testBiometrics();
              } else {
                await _onToggleBiometrics(true);
              }
            },
          ),

        _settingItem(
          icon: Icons.shield_outlined,
          title: 'Two-Factor Authentication',
          subtitle: 'Further secure your account for safety',
        ),

        // Logout (clears Google too)
        _settingItem(
          icon: Icons.logout,
          title: 'Log out',
          subtitle: 'Securely sign out of your account',
          onTap: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Log Out'),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            );

            if (shouldLogout == true) {
              try {
                await _fullSignOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Logout failed: $e')),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Text(
            'Legal',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
        _settingItem(title: 'Terms of Use', hasIcon: false),
        _settingItem(title: 'More', hasIcon: false, hasArrow: false),
        _settingItem(title: 'About us', hasIcon: false),
        _settingItem(title: 'Privacy policy', hasIcon: false),
        _settingItem(
          icon: Icons.delete_forever,
          title: 'Delete Account',
          subtitle: 'Permanently remove your account',
          onTap: () async {
            final confirmDelete = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Account'),
                content: const Text(
                  'This action is permanent and cannot be undone.\n\nAre you sure you want to delete your account?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );

            if (confirmDelete == true) {
              try {
                final user = FirebaseAuth.instance.currentUser;
                final uid = user?.uid;

                if (user != null && uid != null) {
                  await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                  await user.delete();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                debugPrint('Account deletion error: $e');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete account: $e')),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _settingItem({
    required String title,
    String? subtitle,
    IconData? icon,
    Widget? trailing,
    VoidCallback? onTap,
    bool hasIcon = true,
    bool hasArrow = true,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: hasIcon ? Icon(icon, color: Colors.grey[400]) : null,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12))
          : null,
      trailing: trailing ??
          (hasArrow ? Icon(Icons.chevron_right, color: Colors.grey[600]) : null),
    );
  }
}
