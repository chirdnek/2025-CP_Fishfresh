// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fishfresh/screens/profile_screens.dart';
import 'dart:io';
import 'package:fishfresh/screens/login.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _isFaceIdEnabled = true;
  String _firstName = '';
  String _lastName = '';
  String? _localImagePath;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

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

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF000000);

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
                    : const AssetImage('assets/images/avatar.jpg')
                          as ImageProvider,
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
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
                : const AssetImage('assets/images/avatar.jpg')
                      as ImageProvider,
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

  Widget _buildSettingsList() {
    return Column(
      children: [
        _settingItem(
          icon: Icons.lock_outline_rounded,
          title: 'Face ID / Touch ID',
          subtitle: 'Manage your device security',
          trailing: Switch(
            value: _isFaceIdEnabled,
            onChanged: (value) {
              setState(() {
                _isFaceIdEnabled = value;
              });
            },
            activeTrackColor: const Color(0xFF28C18E),
            activeColor: Colors.white,
            inactiveTrackColor: Colors.grey[800],
            inactiveThumbColor: Colors.grey[400],
          ),
        ),
        _settingItem(
          icon: Icons.shield_outlined,
          title: 'Two-Factor Authentication',
          subtitle: 'Further secure your account for safety',
        ),
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
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Logout failed: ${e.toString()}')),
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
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );

          if (confirmDelete == true) {
            try {
              final user = FirebaseAuth.instance.currentUser;
              final uid = user?.uid;

              if (user != null && uid != null) {
                // Delete user document from Firestore
                await FirebaseFirestore.instance.collection('users').doc(uid).delete();

                // Delete Firebase Auth account
                await user.delete();

                // Navigate to login screen
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            } catch (e) {
              debugPrint('Account deletion error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to delete account: ${e.toString()}')),
              );
            }
          }
        },
      ),
    ],
  );
}
    
    
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
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            )
          : null,
      trailing:
          trailing ??
          (hasArrow
              ? Icon(Icons.chevron_right, color: Colors.grey[600])
              : null),
    );
  }

