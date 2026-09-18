import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/app_user.dart';
import 'check_schedule.dart';

/// Android notifications 10 minutes before each Hydraulic Feeder check of
/// the user's team, for the next 7 days of its roster. Rescheduled whenever
/// the dashboard opens, so a roster or team change is picked up. Does
/// nothing on the website.
abstract final class CheckReminders {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static DateTime? _lastScheduled;

  static const Duration lead = Duration(minutes: 10);

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> refresh(AppUser? user) async {
    if (!supported || user == null) return;
    // Crew and foremen belong to a team on the roster.
    if (user.role != UserRole.crew && user.role != UserRole.foreman) return;
    // Once per hour is plenty; the dashboard is opened often.
    final last = _lastScheduled;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 1)) {
      return;
    }
    try {
      final roster = await loadRosterForTeam(user.teamId);
      if (roster == null) return;
      await ensureInitialized();
      final checks = upcomingChecks(
        roster.$1,
        roster.$2,
        from: DateTime.now().add(lead),
      );
      // Only the scheduled reminders; critical-temperature notifications
      // already on screen stay.
      await _plugin.cancelAllPendingNotifications();
      var id = 1000;
      for (final check in checks) {
        final at = check.dueAt.subtract(lead);
        await _plugin.zonedSchedule(
          id: id++,
          // An absolute instant: the device clock decides the local time.
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          title:
              'Hydraulic Feeder · ${check.slot.label} pukul ${check.slot.plannedTime}',
          body:
              '10 menit lagi. Isi Daily Check Sheet Hydraulic Feeder '
              '${check.shiftCode == 'PAGI' ? 'Shift Pagi' : 'Shift Malam'} di SICATAT.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'check_reminders',
              'Pengingat jam pengecekan',
              channelDescription:
                  'Pengingat sebelum jadwal pengecekan Hydraulic Feeder',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // Inexact alarms need no extra permission; a few minutes' drift is
          // fine for a 10-minute heads-up.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      _lastScheduled = DateTime.now();
    } on Object catch (error) {
      debugPrint('Check reminders not scheduled: $error');
    }
  }

  static Future<void> cancelAll() async {
    if (!supported || !_initialized) return;
    _lastScheduled = null;
    await _plugin.cancelAll();
  }

  /// The shared plugin, also used by [CriticalAlertWatcher].
  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }
}
