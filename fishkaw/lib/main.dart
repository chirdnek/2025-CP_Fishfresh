import 'package:flutter/material.dart';
import 'screens/login.dart';  // 👈 Import the screen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fishkaw',
      home: const LoginScreen(),  // 👈 Set as starting screen
    );
  }
}
