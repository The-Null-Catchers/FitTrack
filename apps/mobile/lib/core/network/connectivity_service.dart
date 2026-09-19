import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Device connectivity, as a stream the app can react to.
///
/// This reports whether a network *interface* is up, which is not the same as
/// the API being reachable. It is used to decide when to attempt a sync, never
/// to decide whether a write succeeded — that is settled by the request itself.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
      .map(_isOnline)
      .distinct();

  Future<bool> get isOnline async => _isOnline(await _connectivity.checkConnectivity());

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult result) => result != ConnectivityResult.none);
}
