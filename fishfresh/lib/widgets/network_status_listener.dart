import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // <-- add this
import '../services/network_monitor.dart';
import '../main.dart'
    show rootScaffoldMessengerKey, flutterLocalNotificationsPlugin, networkChannel; // <-- use networkChannel

class NetworkStatusListener extends StatefulWidget {
  final Widget child;
  const NetworkStatusListener({super.key, required this.child});

  @override
  State<NetworkStatusListener> createState() => _NetworkStatusListenerState();
}

class _NetworkStatusListenerState extends State<NetworkStatusListener>
    with WidgetsBindingObserver {
  StreamSubscription? _sub;
  bool _bannerShown = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sub = NetworkMonitor.instance.stream.listen((status) {
      if (status == NetworkStatus.disconnected) {
        _showOfflineBanner();
        _maybeNotify(); // alarm-like notification if app not foreground
      } else {
        _hideBanner();
        _notifyRestored();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  void _showOfflineBanner() {
    if (_bannerShown) return;
    _bannerShown = true;
    rootScaffoldMessengerKey.currentState?.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.red.shade700,
        content: const Text(
          'No internet connection. Some features may not work.',
          style: TextStyle(color: Colors.white),
        ),
        leading: const Icon(Icons.wifi_off, color: Colors.white),
        actions: [
          TextButton(
            onPressed: () async {
              // Manually re-check:
              _hideBanner();
              _showOfflineBanner();
            },
            child: const Text('RETRY', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _hideBanner,
            child: const Text('DISMISS', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _hideBanner() {
    if (!_bannerShown) return;
    _bannerShown = false;
    rootScaffoldMessengerKey.currentState?.clearMaterialBanners();
  }

  Future<void> _maybeNotify() async {
    // Only “alarm” if not foreground
    if (_lifecycle != AppLifecycleState.resumed) {
      await flutterLocalNotificationsPlugin.show(
        9001,
        'You are offline',
        'FishFresh lost internet connection.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            networkChannel.id,          // <-- use public channel
            networkChannel.name,
            channelDescription: networkChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    }
  }

  Future<void> _notifyRestored() async {
    // Optional: notify once internet is back (no sound)
    await flutterLocalNotificationsPlugin.show(
      9002,
      'Back online',
      'Internet connection restored.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          networkChannel.id,
          networkChannel.name,
          channelDescription: networkChannel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
