import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

enum NetworkStatus { connected, disconnected }

class NetworkMonitor {
  NetworkMonitor._();
  static final NetworkMonitor instance = NetworkMonitor._();

  final _controller = StreamController<NetworkStatus>.broadcast();
  Stream<NetworkStatus> get stream => _controller.stream;

  StreamSubscription? _connSub;
  StreamSubscription? _netSub;
  Timer? _debounce;
  bool _lastOnline = true; // assume online at start

  Future<void> start() async {
    // Initial check
    final hasNet = await InternetConnection().hasInternetAccess;
    _emit(hasNet);

    // Listen to connectivity changes (wifi/cell/none)
    _connSub = Connectivity().onConnectivityChanged.listen((_) async {
      _scheduleCheck();
    });

    // Also listen to real internet changes
    _netSub = InternetConnection().onStatusChange.listen((status) {
      _emit(status == InternetStatus.connected);
    });
  }

  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final hasNet = await InternetConnection().hasInternetAccess;
      _emit(hasNet);
    });
  }

  void _emit(bool online) {
    if (_lastOnline != online) {
      _lastOnline = online;
      _controller.add(online ? NetworkStatus.connected : NetworkStatus.disconnected);
    }
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    await _netSub?.cancel();
    _debounce?.cancel();
    await _controller.close();
  }
}
