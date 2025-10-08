// ignore_for_file: use_build_context_synchronously

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fishfresh/screens/home.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  bool passwordVisible = false;
  bool confirmPasswordVisible = false;
  bool termsAccepted = false;

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool _isGoogleLoading = false;

  bool get _canSubmit => termsAccepted && !isLoading;

  // --- Simple legal texts (placeholder content) ---
  static const String _tosText = '''
1) Use FishFresh for informational purposes only.
2) You’re responsible for your account and device security.
3) Do not misuse, reverse-engineer, or resell the app.
4) We may update features and terms from time to time.
5) The app is provided "as is" without warranties to the extent permitted by law.
''';

  static const String _privacyText = '''
• We collect your name and email to create your account.
• We store timestamps and basic usage needed to operate the service.
• We do not sell your personal data.
• You can request deletion of your account and data.
• See in-app contact for questions regarding privacy.
''';

  // --- Reusable policy dialog ---
  Future<void> _showPolicyDialog(String title, String body) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r"^[\w\.-]+@[\w\.-]+\.\w{2,4}$").hasMatch(email);
  }

  bool _isStrongPassword(String password) {
    return RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[\W_]).{8,}$')
        .hasMatch(password);
  }

  // Upsert user document in Firestore (prefer typed names, fallback to Google profile)
  Future<void> _ensureUserDoc(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await docRef.get();
    final existing = (snap.data() ?? <String, dynamic>{});
    final patch = <String, dynamic>{};

    final typedFirst = firstNameController.text.trim();
    final typedLast = lastNameController.text.trim();

    final display = (user.displayName ?? '').trim();
    final parts = display.isEmpty ? <String>[] : display.split(RegExp(r'\s+'));
    final gFirst =
        parts.isNotEmpty ? parts.first : (user.email?.split('@').first ?? 'User');
    final gLast = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    if (!snap.exists || (existing['firstName'] ?? '').toString().isEmpty) {
      patch['firstName'] = typedFirst.isNotEmpty ? typedFirst : gFirst;
    }
    if (!snap.exists || (existing['lastName'] ?? '').toString().isEmpty) {
      patch['lastName'] = typedLast.isNotEmpty ? typedLast : gLast;
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

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  Future<void> _signUp() async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if ([firstName, lastName, email, password, confirmPassword].contains('')) {
      _showDialog('Missing Fields', 'Please fill all fields.');
      return;
    }

    if (!_isValidEmail(email)) {
      _showDialog('Invalid Email', 'Please enter a valid email address.');
      return;
    }

    if (password != confirmPassword) {
      _showDialog('Password Mismatch', 'Passwords do not match.');
      return;
    }

    if (!_isStrongPassword(password)) {
      _showDialog(
        'Weak Password',
        'Password must be at least 8 characters long,\ninclude 1 uppercase, 1 lowercase, 1 number, and 1 symbol.',
      );
      return;
    }

    if (!termsAccepted) {
      _showDialog('Accept Terms',
          'Please accept the Terms of Services and Privacy Policy to continue.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _showDialog('Success', 'Sign up successful!');
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message = 'Sign up failed';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already in use';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else if (e.code == 'weak-password') {
        message = 'Weak password';
      }
      _showDialog('Error', message);
    } catch (e) {
      _showDialog('Unexpected Error', '$e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Real Google sign-in (gated by termsAccepted)
  Future<void> _continueWithGoogle() async {
    if (_isGoogleLoading || isLoading) return;

    if (!termsAccepted) {
      await _showDialog(
        'Accept Terms',
        'Please accept the Terms of Services and Privacy Policy to continue.',
      );
      return;
    }

    setState(() => _isGoogleLoading = true);

    try {
      // Force account chooser
      final gs = GoogleSignIn();
      try {
        await gs.disconnect();
      } catch (_) {}
      await gs.signOut();

      final GoogleSignInAccount? gUser = await gs.signIn();
      if (gUser == null) return; // user cancelled

      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        throw FirebaseAuthException(
            code: 'user-null', message: 'No user returned from Google sign-in.');
      }

      await _ensureUserDoc(user);
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
      await _showDialog('Google Sign-in', msg);
    } catch (_) {
      await _showDialog(
          'Google Sign-in', 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _showDialog(String title, String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = isLoading || _isGoogleLoading;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/fish_bg.jpg', fit: BoxFit.cover),
          Container(color: const Color.fromRGBO(0, 180, 120, 0.20)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App title / tagline (unchanged theme)
                    const Center(
                      child: Column(
                        children: [
                          Text(
                            'FishFresh',
                            style: TextStyle(
                              fontSize: 40,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Know Your Catch — Fresh or Not?',
                            style:
                                TextStyle(fontSize: 16, color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // "Sign Up" like the screenshot
                    const Text(
                      'Sign Up',
                      style: TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // First & Last name side-by-side (like the picture)
                    Row(
                      children: [
                        Expanded(
                          child: _inputField(
                            'First Name',
                            Icons.person,
                            firstNameController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _inputField(
                            'Last Name',
                            Icons.person_outline,
                            lastNameController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Email
                    _inputField('Email address', Icons.email, emailController,
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 12),

                    // Password (single line like the picture; confirm stays below)
                    _passwordField(
                      controller: passwordController,
                      label: 'Password',
                      obscure: !passwordVisible,
                      toggle: () =>
                          setState(() => passwordVisible = !passwordVisible),
                      isVisible: passwordVisible,
                      icon: Icons.lock,
                    ),
                    const SizedBox(height: 12),

                    // Confirm password (kept for your validation)
                    _passwordField(
                      controller: confirmPasswordController,
                      label: 'Confirm Password',
                      obscure: !confirmPasswordVisible,
                      toggle: () => setState(() =>
                          confirmPasswordVisible = !confirmPasswordVisible),
                      isVisible: confirmPasswordVisible,
                      icon: Icons.lock_outline,
                    ),
                    const SizedBox(height: 8),

                    // Accept terms + links
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: termsAccepted,
                          onChanged: (v) => setState(() {
                            termsAccepted = v ?? false;
                          }),
                          activeColor: Colors.green,
                          checkColor: Colors.white,
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.white70),
                              children: [
                                const TextSpan(
                                    text: 'I agree the FishFresh '),
                                TextSpan(
                                  text: 'Terms of Services',
                                  style: const TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _showPolicyDialog(
                                        'Terms of Services', _tosText),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: const TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _showPolicyDialog(
                                        'Privacy Policy', _privacyText),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Primary Sign Up button (kept green to match theme)
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _signUp : null,
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>(
                                  (states) {
                            if (states.contains(WidgetState.disabled)) {
                              return Colors.green.withValues(alpha: 0.45);
                            }
                            return Colors.green;
                          }),
                          shape: const WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                          ),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Sign Up',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // OR divider like in the screenshot
                    Row(
                      children: const [
                        Expanded(
                            child: Divider(
                          thickness: 1,
                          color: Colors.white24,
                        )),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ),
                        Expanded(
                            child: Divider(
                          thickness: 1,
                          color: Colors.white24,
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Continue with Google (disabled until terms accepted)
                   SizedBox(
  height: 48,
  width: double.infinity,
  child: ElevatedButton(
    onPressed: busy ? null : _continueWithGoogle,
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color.fromARGB(255, 42, 39, 39)
                .withValues(alpha: 0.55);
          }
          return const Color.fromARGB(255, 239, 239, 239);
        },
      ),
      foregroundColor: const WidgetStatePropertyAll(
          Color.fromARGB(255, 4, 4, 4)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    child: _isGoogleLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/google_logo.png',
                height: 20,
                width: 20,
              ),
              const SizedBox(width: 8),
              const Text('Continue with Google',
                  style: TextStyle(fontSize: 16)),
            ],
          ),
  ),
),
                    const SizedBox(height: 16),

                    // Already registered? Sign In
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already registered? ',
                            style: TextStyle(color: Colors.white70)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Reusable inputs (kept same styles to stay on-theme) ==========
  Widget _inputField(String hint, IconData icon, TextEditingController controller,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.black),
      decoration: _buildInputDecoration(hint, icon),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    required bool isVisible,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.black),
      decoration: _buildInputDecoration(
        label,
        icon,
        suffix: IconButton(
          icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off),
          onPressed: toggle,
        ),
      ),
    );
  }

 InputDecoration _buildInputDecoration(String hint, IconData icon,
    {Widget? suffix}) {
  return InputDecoration(
    filled: true,
    fillColor: const Color.fromARGB(255, 255, 248, 248),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black54), // hint text blackish
    prefixIcon: Icon(icon, color: Colors.black),       // icon black
    suffixIcon: suffix != null
        ? IconTheme(
            data: const IconThemeData(color: Colors.black), 
            child: suffix,
          )
        : null,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

  }

