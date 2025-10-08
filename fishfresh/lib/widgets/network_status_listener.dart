import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/network_monitor.dart';
import '../main.dart'
    show rootScaffoldMessengerKey, flutterLocalNotificationsPlugin, networkChannel;

class NetworkStatusListener extends StatefulWidget {
  final Widget child;
  const NetworkStatusListener({super.key, required this.child});

  @override
  State<NetworkStatusListener> createState() => _NetworkStatusListenerState();
}

class _NetworkStatusListenerState extends State<NetworkStatusListener>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  StreamSubscription? _sub;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sub = NetworkMonitor.instance.stream.listen((status) {
      if (status == NetworkStatus.disconnected) {
        _showToast(
          message: '⚠️ No internet connection',
          color: Colors.orange.shade700,
          duration: const Duration(seconds: 3),
        );
        _maybeNotify();
      } else {
        _showToast(
          message: '✅ Back online',
          color: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        );
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

  /// Show a sliding toast from the top
  void _showToast({
    required String message,
    required Color color,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.of(rootScaffoldMessengerKey.currentContext!);
    late OverlayEntry entry;
    late AnimationController controller;

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );

    final animation = Tween<Offset>(
      begin: const Offset(0, -1), // offscreen
      end: Offset.zero,           // slide into view
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: SlideTransition(
          position: animation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    controller.forward();

    Future.delayed(duration, () async {
      await controller.reverse();
      entry.remove();
      controller.dispose();
    });
  }

  /// Notify only when offline (and app is backgrounded)
  Future<void> _maybeNotify() async {
    if (_lifecycle != AppLifecycleState.resumed) {
      await flutterLocalNotificationsPlugin.show(
        9001,
        'You are offline',
        'FishFresh lost internet connection.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            networkChannel.id,
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

  @override
  Widget build(BuildContext context) => widget.child;
}
