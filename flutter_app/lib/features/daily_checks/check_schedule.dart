import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/sicatat_types.dart';
import 'daily_check_forms.dart';

/// The 3-3-3 rotation stored in `roster_anchor`: from [start], team
/// order[0] works 3 days Pagi, then 3 days Malam, then 3 days off; order[1]
/// starts its Pagi block 3 days later and order[2] 6 days later. So on any
/// day the Pagi team is order[block] and the Malam team the one whose Pagi
/// block just ended, order[(block + 2) % 3].
class RosterAnchor {
  const RosterAnchor({required this.start, required this.order});

  final DateTime start;
  final List<String> order;

  String? teamCodeFor(DateTime date, String shiftCode) {
    if (order.length != 3) return null;
    final day = DateTime(date.year, date.month, date.day);
    final origin = DateTime(start.year, start.month, start.day);
    final offset = day.difference(origin).inDays;
    final block = (offset % 9 + 9) % 9 ~/ 3;
    return switch (shiftCode) {
      'PAGI' => order[block],
      'MALAM' => order[(block + 2) % 3],
      _ => null,
    };
  }
}

/// One Hydraulic Feeder check a team is expected to fill.
class ScheduledCheck {
  const ScheduledCheck({
    required this.sheetDate,
    required this.shiftCode,
    required this.slot,
    required this.dueAt,
  });

  /// The sheet's date; a night check after midnight belongs to the previous
  /// day's Shift Malam sheet.
  final DateTime sheetDate;
  final String shiftCode;
  final DailyCheckSlot slot;
  final DateTime dueAt;
}

/// The shift running at [now]: Pagi 07:00–19:00, Malam 19:00–07:00 (dated
/// by the evening it started).
(DateTime, String) currentShift(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (now.hour >= 7 && now.hour < 19) return (today, 'PAGI');
  if (now.hour >= 19) return (today, 'MALAM');
  return (today.subtract(const Duration(days: 1)), 'MALAM');
}

/// The Hydraulic Feeder checks of one shift, with their clock times.
List<ScheduledCheck> checksForShift(DateTime date, String shiftCode) {
  final day = DateTime(date.year, date.month, date.day);
  return <ScheduledCheck>[
    for (final slot in hydraulicFeederForm.slotsForShift(shiftCode))
      () {
        final parts = slot.plannedTime!.split(':');
        var due = DateTime(
          day.year,
          day.month,
          day.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        // 02:00 and 06:00 of a Shift Malam fall on the next calendar day.
        if (shiftCode == 'MALAM' && due.hour < 12) {
          due = due.add(const Duration(days: 1));
        }
        return ScheduledCheck(
          sheetDate: day,
          shiftCode: shiftCode,
          slot: slot,
          dueAt: due,
        );
      }(),
  ];
}

/// Hydraulic checks of [teamCode]'s shifts from [from] for [days] days.
List<ScheduledCheck> upcomingChecks(
  RosterAnchor anchor,
  String teamCode, {
  required DateTime from,
  int days = 7,
}) {
  final first = DateTime(from.year, from.month, from.day);
  final checks = <ScheduledCheck>[
    // Start a day early: last night's Shift Malam still runs this morning.
    for (var i = -1; i < days; i++)
      for (final shift in const <String>['PAGI', 'MALAM'])
        if (anchor.teamCodeFor(first.add(Duration(days: i)), shift) == teamCode)
          ...checksForShift(first.add(Duration(days: i)), shift),
  ].where((check) => !check.dueAt.isBefore(from)).toList();
  checks.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return checks;
}

/// Loads the active rotation and the signed-in user's team code.
Future<(RosterAnchor, String)?> loadRosterForTeam(String? teamId) async {
  if (teamId == null) return null;
  final client = Supabase.instance.client;
  final Object anchors = await client
      .from('roster_anchor')
      .select('tanggal_mula,urutan_regu')
      .eq('is_active', true)
      .order('tanggal_mula', ascending: false)
      .limit(1);
  final Object? team = await client
      .from('team')
      .select('code')
      .eq('id', teamId)
      .maybeSingle();
  if (anchors is! List || anchors.isEmpty || team == null) return null;
  final row = requireJsonMap(anchors.first, source: 'roster anchor');
  final order = (row['urutan_regu'] as List?)
      ?.map((code) => code.toString())
      .toList(growable: false);
  final code = requireJsonMap(team, source: 'team').optionalString('code');
  if (order == null || code == null) return null;
  return (
    RosterAnchor(
      start: DateTime.parse(row.requiredString('tanggal_mula')),
      order: order,
    ),
    code,
  );
}
