import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../theme/app_theme.dart';

typedef ReachabilityProbe = Future<bool> Function();

/// Prevents use of the app unless the configured Supabase project is reachable.
///
/// Connectivity type by itself is not trusted: Wi-Fi can be connected without
/// internet access. A small authenticated request confirms that the actual
/// backend used for sheet sync is available.
class OnlineOnlyGate extends StatefulWidget {
  const OnlineOnlyGate({
    required this.child,
    this.probe,
    this.connectivity,
    super.key,
  });

  final Widget child;
  final ReachabilityProbe? probe;
  final Connectivity? connectivity;

  @override
  State<OnlineOnlyGate> createState() => _OnlineOnlyGateState();
}

class _OnlineOnlyGateState extends State<OnlineOnlyGate> {
  late final Connectivity _connectivity;
  late final ReachabilityProbe _probe;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;
  bool _checking = true;
  bool _online = false;
  bool _probeInProgress = false;
  int _consecutiveProbeFailures = 0;

  @override
  void initState() {
    super.initState();
    _connectivity = widget.connectivity ?? Connectivity();
    _probe = widget.probe ?? _isSupabaseReachable;
    _subscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (_hasNetwork(results)) {
        // Connectivity events can fire several times while Android switches
        // between mobile data and Wi-Fi. Check quietly so a short handover
        // never covers a form the crew is currently completing.
        unawaited(_check(showChecking: !_online));
      } else {
        _consecutiveProbeFailures = 0;
        _setConnection(online: false, checking: false);
      }
    });
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _check(showChecking: false),
    );
    unawaited(_check(showChecking: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _check({bool showChecking = false}) async {
    if (_probeInProgress) return;
    _probeInProgress = true;
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();
      if (!_hasNetwork(results)) {
        _consecutiveProbeFailures = 0;
        _setConnection(online: false, checking: false);
        return;
      }
      if (showChecking && !_online) {
        _setConnection(online: false, checking: true);
      }
      final bool reachable = await _probe();
      if (reachable) {
        _consecutiveProbeFailures = 0;
        _setConnection(online: true, checking: false);
      } else {
        _consecutiveProbeFailures += 1;
        // A single failed probe is common during a mobile-network handover.
        // Preserve the working screen unless this is initial startup or three
        // consecutive backend probes fail.
        if (!_online || _consecutiveProbeFailures >= 3) {
          _setConnection(online: false, checking: false);
        }
      }
    } on Object {
      _consecutiveProbeFailures += 1;
      if (!_online || _consecutiveProbeFailures >= 3) {
        _setConnection(online: false, checking: false);
      }
    } finally {
      _probeInProgress = false;
    }
  }

  void _setConnection({required bool online, required bool checking}) {
    if (!mounted) return;
    setState(() {
      _online = online;
      _checking = checking;
    });
  }

  bool _hasNetwork(List<ConnectivityResult> results) => results.any(
    (ConnectivityResult result) => result != ConnectivityResult.none,
  );

  Future<bool> _isSupabaseReachable() async {
    if (!AppConfig.isSupabaseConfigured) return false;
    try {
      final Uri endpoint = Uri.parse(
        '${AppConfig.supabaseUrl}/rest/v1/app_version?select=platform&limit=1',
      );
      final http.Response response = await http
          .get(
            endpoint,
            headers: <String, String>{
              'accept': 'application/json',
              'apikey': AppConfig.supabaseAnonKey,
              'authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
            },
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      widget.child,
      if (!_online) _OfflineOverlay(checking: _checking, onRetry: _check),
    ],
  );
}

class _OfflineOverlay extends StatelessWidget {
  const _OfflineOverlay({required this.checking, required this.onRetry});

  final bool checking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 60,
                color: AppColors.green,
              ),
              const SizedBox(height: 18),
              Text(
                checking
                    ? 'Checking connection'
                    : 'Internet connection required',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'sicatat is online-only. Connect to the internet so every field entry can be sent safely to the server.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: checking ? null : onRetry,
                icon: checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(checking ? 'Checking…' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
