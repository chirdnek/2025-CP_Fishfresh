// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_button/sign_in_button.dart';

import 'signup.dart';
import 'package:fishfresh/screens/home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool passwordVisible = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  // === Helper: upsert user doc with first/last/email/photo ===
  Future<void> _ensureUserDoc(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await docRef.get();

    // Derive names from displayName or email as fallback
    final display = (user.displayName ?? '').trim();
    final parts = display.isEmpty ? <String>[] : display.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : (user.email?.split('@').first ?? 'User');
    final last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final existing = (snap.data() ?? <String, dynamic>{});
    final patch = <String, dynamic>{};

    if (!snap.exists || (existing['firstName'] ?? '').toString().isEmpty) {
      patch['firstName'] = first;
    }
    if (!snap.exists || (existing['lastName'] ?? '').toString().isEmpty) {
      patch['lastName'] = last;
    }
    if (!snap.exists || (existing['email'] ?? '').toString().isEmpty) {
      patch['email'] = user.email;
    }
    if (!snap.exists || (existing['photoUrl'] ?? '').toString().isEmpty) {
      patch['photoUrl'] = user.photoURL;
    }
    if (!snap.exists) {
      patch['localImagePath'] = null;
      patch['createdAt'] = FieldValue.serverTimestamp();
    }

    if (patch.isNotEmpty) {
      await docRef.set(patch, SetOptions(merge: true));
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _showErrorDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Login Error'),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      return _showErrorDialog('Please enter both email and password.');
    }
    if (!_isValidEmail(email)) {
      return _showErrorDialog('Please enter a valid email address.');
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _ensureUserDoc(u); // <-- ensure names exist
      _goHome();
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with that email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password.';
          break;
        default:
          errorMessage = e.message ?? 'Login failed.';
      }
      _showErrorDialog(errorMessage);
    } catch (e) {
      _showErrorDialog('An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      // Force the account chooser by disconnecting any cached session.
      final gs = GoogleSignIn();
      try {
        await gs.disconnect(); // revoke previous consent if any
      } catch (_) {}
      await gs.signOut(); // sign out cached account

      // Trigger chooser
      final GoogleSignInAccount? gUser = await gs.signIn();
      if (gUser == null) return; // user cancelled

      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-null', message: 'No user returned from Google sign-in.');
      }

      await _ensureUserDoc(user); // <-- upsert Firestore names
      _goHome();
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          msg = 'This email is already used with another sign-in method.';
          break;
        case 'invalid-credential':
          msg = 'Your Google credential is invalid or expired. Try again.';
          break;
        case 'operation-not-allowed':
          msg = 'Google sign-in is disabled in Firebase.';
          break;
        default:
          msg = e.message ?? 'Google sign-in failed.';
      }
      _showErrorDialog(msg);
    } catch (e) {
      _showErrorDialog('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGoogleLoading;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/fish_bg.jpg', fit: BoxFit.cover),
          Container(color: const Color.fromRGBO(0, 180, 120, 0.40)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  const Text(
                    'FishFresh',
                    style: TextStyle(
                      fontSize: 40,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Know Your Catch — Fresh or Not?',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  _buildTextField(
                    controller: emailController,
                    hintText: 'Email',
                    icon: Icons.email,
                    obscureText: false,
                  ),
                  const SizedBox(height: 20),

                  _buildTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    icon: Icons.lock,
                    obscureText: !passwordVisible,
                    suffixIcon: IconButton(
                      icon: Icon(passwordVisible ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => passwordVisible = !passwordVisible),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: password reset
                      },
                      child: const Text('Forgot Password?', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Email/Password login
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: busy ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // OR separator
                  Row(
                    children: const [
                      Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('OR', style: TextStyle(color: Colors.white70)),
                      ),
                      Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Official Google button (with logo)
                  SizedBox(
                    width: double.infinity,
                    child:SignInButton(
  Buttons.google,
  text: _isGoogleLoading ? 'Signing in…' : 'Continue with Google',
  onPressed: () async {
    if (_isLoading || _isGoogleLoading) return; // guard instead of null
    await _signInWithGoogle();
  },
)
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                        child: const Text('Sign Up here',
                            style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
