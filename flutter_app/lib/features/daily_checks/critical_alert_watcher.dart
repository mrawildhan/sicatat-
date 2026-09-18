import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/sicatat_types.dart';
import 'check_reminders.dart';

/// Phone notifications for critical temperatures, without email.
///
/// The server records every critical value in `temperature_alert` (the
/// dispatch-temperature-alerts cron, every 5 minutes). While SICATAT is open
/// on Android, this checks that table every few minutes and when the app
/// returns to the foreground, and notifies what is new. Row-level security
/// limits the rows to what the user reviews (foreman: own team, supervisor
/// COP: own site, supervisor SMG/admin: all), so crew see none.
///
/// It cannot notify while the app is closed; that would need push messaging
/// (Firebase), kept for later on the owner's request.
class CriticalAlertWatcher with WidgetsBindingObserver {
  CriticalAlertWatcher._();

  static final CriticalAlertWatcher instance = CriticalAlertWatcher._();

  static const Duration interval = Duration(minutes: 3);

  /// On a phone's first check only the last few hours are worth notifying.
  static const Duration _firstLookBack = Duration(hours: 6);
  static const String _lastSeenKey = 'critical_alert_last_seen';

  Timer? _timer;
  bool _checking = false;
  int _nextId = 5000;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// False in widget tests and unconfigured builds, where Supabase was never
  /// initialized.
  static bool get _supabaseReady {
    try {
      Supabase.instance.client;
      return true;
    } on Object {
      return false;
    }
  }

  void start() {
    if (!supported || _timer != null || !_supabaseReady) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => check());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    if (_checking || !supported || !_supabaseReady) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeen =
          DateTime.tryParse(prefs.getString(_lastSeenKey) ?? '') ??
          DateTime.now().toUtc().subtract(_firstLookBack);
      final Object rows = await client
          .from('temperature_alert')
          .select(
            'id,form_label,point_label,value,occurred_at,created_at,'
            'shift_label,team:team_id(name)',
          )
          .gt('created_at', lastSeen.toUtc().toIso8601String())
          .order('created_at', ascending: true)
          .limit(50);
      if (rows is! List || rows.isEmpty) return;
      final alerts = rows
          .map((row) => requireJsonMap(row, source: 'temperature alert'))
          .toList(growable: false);
      await CheckReminders.ensureInitialized();
      if (alerts.length > 3) {
        final highest = alerts
            .map((a) => (a['value']! as num).toDouble())
            .reduce((a, b) => a > b ? a : b);
        await _notify(
          'Suhu kritis: ${alerts.length} pembacaan baru',
          'Tertinggi ${_format(highest)} °C. Buka Suhu → Pemantauan & '
              'persetujuan untuk rinciannya.',
        );
      } else {
        for (final alert in alerts) {
          final team = alert['team'];
          await _notify(
            'Suhu kritis ${_format((alert['value']! as num).toDouble())} °C',
            '${alert.requiredString('point_label')} · '
                '${alert.requiredString('form_label')} · '
                '${team is Map ? team['name'] : 'Regu'} · '
                '${alert.optionalString('shift_label') ?? ''}',
          );
        }
      }
      await prefs.setString(
        _lastSeenKey,
        alerts.last.requiredString('created_at'),
      );
    } on Object catch (error) {
      debugPrint('Critical alert check failed: $error');
    } finally {
      _checking = false;
    }
  }

  Future<void> _notify(String title, String body) => CheckReminders.plugin.show(
    id: _nextId++,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'critical_temperature',
        'Suhu kritis',
        channelDescription: 'Pembacaan suhu yang mencapai batas kritis di regu atau lokasi Anda',
        importance: Importance.max,
        priority: Priority.max,
        // Shows the whole point name when the notification is expanded.
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
  );

  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
