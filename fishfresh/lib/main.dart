// ignore_for_file: unused_import, avoid_print, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:fishfresh/screens/splash_screen.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/loading_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

import 'services/push_notification_service.dart';
import 'services/storage_service.dart';

// NEW: network monitor + listener
import 'services/network_monitor.dart';
import 'widgets/network_status_listener.dart';

// GLOBALS (make these top-level so other files can import them)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Public channel so other files (listener) can import it
const AndroidNotificationChannel networkChannel = AndroidNotificationChannel(
  'network_status',
  'Network Status',
  description: 'Alerts when internet connection is lost or restored',
  importance: Importance.high,
  playSound: true,
);

// Firebase Messaging background handler must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // FCM background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ----- Local notifications init (Android + iOS) -----
  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initIOS = DarwinInitializationSettings(
    requestAlertPermission: false, // we'll request explicitly below
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const InitializationSettings initSettings = InitializationSettings(
    android: initAndroid,
    iOS: initIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Create Android channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(networkChannel);

  // iOS notification permissions (for local notifs)
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, sound: true, badge: false);

  // Your existing push notification setup
  await PushNotificationService().initialize();

  // Start network monitor (so listener can receive events)
  await NetworkMonitor.instance.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FishFresh',
      theme: ThemeData.dark(),
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      home: const InitialScreen(),
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomePage(),
      },
      // Wrap the whole app so banners/alerts can show anywhere
      builder: (context, child) => NetworkStatusListener(child: child!),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final seen = await _storageService.hasSeenOnboarding();

    if (!seen) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/onboarding');
    } else {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const SplashScreen(); // User is signed in
        } else {
          return const LoginScreen(); // User is not signed in
        }
      },
    );
  }
}
