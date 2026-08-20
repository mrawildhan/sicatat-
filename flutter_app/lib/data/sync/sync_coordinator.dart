import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_service.dart';

/// Retries the local outbox when connectivity returns and at a safe interval.
///
/// A failed request stays in SQLite. Connectivity only indicates that a network
/// is available; [SyncService] remains the authority for accepting or retaining
/// each queued operation.
class SyncCoordinator {
  SyncCoordinator(this._syncService, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final SyncService _syncService;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (_hasNetwork(results)) unawaited(_syncIfOnline());
    });
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_syncIfOnline()),
    );
    unawaited(_syncIfOnline());
  }

  Future<void> _syncIfOnline() async {
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();
      if (_hasNetwork(results)) await _syncService.syncPending();
    } on Object {
      // The queue remains intact. A later connectivity event or timed retry
      // will attempt it again.
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) => results.any(
    (ConnectivityResult result) => result != ConnectivityResult.none,
  );

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _connectivitySubscription?.cancel();
    _retryTimer = null;
    _connectivitySubscription = null;
    _started = false;
  }
}
