// lib/main.dart
// ignore_for_file: avoid_print, unused_import

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'screens/splash_screen.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/onboarding/onboarding_screen.dart';

import 'services/push_notification_service.dart';
import 'services/storage_service.dart';

// NEW: network monitor + listener
import 'services/network_monitor.dart';
import 'widgets/network_status_listener.dart';

// GLOBALS
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const AndroidNotificationChannel networkChannel = AndroidNotificationChannel(
  'network_status',
  'Network Status',
  description: 'Alerts when internet connection is lost or restored',
  importance: Importance.high,
  playSound: true,
);

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
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid, iOS: initIOS);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Android channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(networkChannel);

  // iOS local notif perms
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, sound: true, badge: false);

  // Push + network
  await PushNotificationService().initialize();
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
      builder: (context, child) => NetworkStatusListener(child: child!),

      // ⬇️ Show Splash immediately; SplashDirector decides where to go while it animates
      home: const SplashDirector(),
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}

// --- Route director: decide in the background while splash animates ---
class SplashDirector extends StatefulWidget {
  const SplashDirector({super.key});
  @override
  State<SplashDirector> createState() => _SplashDirectorState();
}

class _SplashDirectorState extends State<SplashDirector> {
  late final Future<String> _routeFuture;

  @override
  void initState() {
    super.initState();
    _routeFuture = _decideRoute(); // start immediately
  }

  Future<String> _decideRoute() async {
    // 1) Onboarding
    final seen = await StorageService().hasSeenOnboarding();
    if (!seen) return '/onboarding';

    // 2) Try to restore Firebase user quickly
    final user = await _restoreUser();
    if (user != null) return '/home';

    // 3) Try silent Google re-login to avoid manual login
    final googleUser = await _tryGoogleSilentLogin();
    if (googleUser != null) return '/home';

    // 4) No session
    return '/login';
  }

  Future<User?> _restoreUser() async {
    final auth = FirebaseAuth.instance;
    var u = auth.currentUser;
    if (u != null) return u;

    try {
      u = await auth
          .userChanges()
          .firstWhere((x) => x != null)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      // ignore
    }
    return u ?? auth.currentUser;
  }

  Future<User?> _tryGoogleSilentLogin() async {
    try {
      final google = GoogleSignIn();
      final account = await google.signInSilently(suppressErrors: true);
      if (account == null) return null;

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return userCred.user;
    } catch (_) {
      return null;
    }
  }

  void _finishAndGo() async {
    final routeName = await _routeFuture; // already computing in parallel
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    // Show the animated Splash now; when it finishes, we route using the result
    return SplashScreen(onFinished: _finishAndGo);
  }
}
