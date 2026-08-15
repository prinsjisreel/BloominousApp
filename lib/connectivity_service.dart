import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityService {
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  ConnectivityService() {
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _controller.add(_getStatusFromResult(results));
    });
  }

  ConnectivityStatus _getStatusFromResult(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return ConnectivityStatus.offline;
    }
    return ConnectivityStatus.online;
  }

  Future<bool> get isOnline async {
    final result = await Connectivity().checkConnectivity();
    return _getStatusFromResult(result) == ConnectivityStatus.online;
  }
}

final connectivityService = ConnectivityService();
