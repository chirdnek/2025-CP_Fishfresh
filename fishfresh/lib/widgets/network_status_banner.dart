import 'package:flutter/material.dart';
import '../services/network_monitor.dart';

class NetworkStatusBanner extends StatelessWidget {
  final Widget child;
  final bool blockInteractionsWhenOffline; // optional
  const NetworkStatusBanner({
    super.key,
    required this.child,
    this.blockInteractionsWhenOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NetworkStatus>(
      stream: NetworkMonitor.instance.stream,
      initialData: NetworkStatus.connected,
      builder: (context, snap) {
        final offline = snap.data == NetworkStatus.disconnected;

        return Stack(
          children: [
            // App content (optionally blocked when offline)
            if (blockInteractionsWhenOffline)
              AbsorbPointer(absorbing: offline, child: child)
            else
              child,

            // Sticky banner
            if (offline)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                right: 12,
                child: _BannerCard(
                  background: const Color.fromARGB(255, 16, 55, 23),
                  icon: Icons.wifi_off_rounded,
                  text: 'No internet connection',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  final Color background;
  final IconData icon;
  final String text;
  const _BannerCard({
    required this.background,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            // a tiny spinner to imply “waiting”
            const SizedBox(width: 8),
            const SizedBox(
              height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
