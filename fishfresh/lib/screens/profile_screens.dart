// ignore_for_file: unused_element, deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/image_service.dart';
import 'package:fishfresh/screens/home.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _localImagePath;
  String? _selectedGender;
  String? _firstName;
  String? _lastName;
  DateTime? _birthday;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _pickAndUploadImage() async {
    final path = await ImageService.pickAndSaveImageLocally();
    if (path != null) {
      setState(() {
        _localImagePath = path;
      });
    }
  }

  Future<void> _loadProfileData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();

      if (data != null) {
        setState(() {
          _firstName = data['firstName'] ?? '';
          _lastName = data['lastName'] ?? '';
          _selectedGender = data['gender'] ?? '';
          // image from Firestore
          _localImagePath = data['localImagePath'];
          if (data['birthday'] != null) {
            _birthday = (data['birthday'] as Timestamp).toDate();
            _birthdayController.text = DateFormat.yMMMMd().format(_birthday!);
          }
          _firstNameController.text = _firstName!;
          _lastNameController.text = _lastName!;
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    final user = _auth.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'gender': _selectedGender,
          'birthday': _birthday != null ? Timestamp.fromDate(_birthday!) : null,
          'localImagePath': _localImagePath, // use the existing image path
        },
      );

      setState(() {
        _firstName = _firstNameController.text.trim();
        _lastName = _lastNameController.text.trim();
      });

      // ✅ Navigate to HomePage and pass the already saved _localImagePath
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(localImagePath: _localImagePath),
        ),
      );
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 18);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );
    if (picked != null) {
      setState(() {
        _birthday = picked;
        _birthdayController.text = DateFormat.yMMMMd().format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardBackgroundColor = Color(0xFF1C1C1E);
    const accentColor = Color(0xFF41C89B);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                Transform.translate(
                  offset: const Offset(0, -10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: cardBackgroundColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _buildProfileForm(accentColor),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 220,
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
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Personalize your info',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                  ],
                ),
                _buildTopIcons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileForm(Color accentColor) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundImage: _localImagePath != null
                  ? FileImage(File(_localImagePath!))
                  : const AssetImage('assets/images/avatar.jpg')
                        as ImageProvider,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _pickAndUploadImage,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${_firstName ?? ''} ${_lastName ?? ''}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        _buildTextField(_firstNameController),
        const SizedBox(height: 16),
        _buildTextField(_lastNameController),
        const SizedBox(height: 16),
        _buildDropdownField(),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _pickBirthday,
          child: AbsorbPointer(
            child: _buildTextField(
              _birthdayController,
              isEditable: false,
              hintText: 'Select Birthday',
            ),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _updateProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Update Profile',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyTextField(String value) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

Widget _buildTextField(
  TextEditingController controller, {
  bool isEditable = true,
  String? hintText,
}) {
  return TextFormField(
    controller: controller,
    enabled: isEditable,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF2C2C2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

Widget _buildDropdownField() {
  final genderOptions = ['Female', 'Male', 'Other'];

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16.0),
    decoration: BoxDecoration(
      color: const Color(0xFF2C2C2E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: genderOptions.contains(_selectedGender) ? _selectedGender : null,
        hint: const Text(
          'Select Gender',
          style: TextStyle(color: Colors.white70),
        ),
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
        dropdownColor: const Color(0xFF2C2C2E),
        style: const TextStyle(color: Colors.white, fontSize: 16),
        onChanged: (String? newValue) {
          setState(() {
            _selectedGender = newValue;
          });
        },
        items: genderOptions.map((value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
      ),
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
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
