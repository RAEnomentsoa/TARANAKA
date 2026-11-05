import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkKind { none, wifi, mobile, other }

/// Network state, so the sync starts by itself when the network comes back
/// and honours "Wi-Fi uniquement" (spec §9).
abstract interface class NetworkStatus {
  Future<NetworkKind> current();
  Stream<NetworkKind> get changes;
}

class DeviceNetworkStatus implements NetworkStatus {
  DeviceNetworkStatus([Connectivity? connectivity]) : _c = connectivity ?? Connectivity();
  final Connectivity _c;

  static NetworkKind _kind(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) {
      return NetworkKind.wifi;
    }
    if (r.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
    if (r.isEmpty || r.every((e) => e == ConnectivityResult.none)) return NetworkKind.none;
    return NetworkKind.other;
  }

  @override
  Future<NetworkKind> current() async => _kind(await _c.checkConnectivity());

  @override
  Stream<NetworkKind> get changes => _c.onConnectivityChanged.map(_kind);
}

/// For tests.
class FakeNetworkStatus implements NetworkStatus {
  FakeNetworkStatus([this.kind = NetworkKind.wifi]);
  NetworkKind kind;
  final _controller = StreamController<NetworkKind>.broadcast();

  void set(NetworkKind k) {
    kind = k;
    _controller.add(k);
  }

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _controller.stream;
}
