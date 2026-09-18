import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/daily_checks/check_schedule.dart';
import 'package:sicatat_flutter/features/daily_checks/daily_check_forms.dart';

void main() {
  final anchor = RosterAnchor(
    start: DateTime(2026, 8, 1),
    order: const <String>['A', 'B', 'C'],
  );

  test('rotation: 3 days Pagi, 3 days Malam, 3 days off per team', () {
    // Days 0-2: A Pagi, C Malam (its Pagi block was days -3..-1), B off.
    expect(anchor.teamCodeFor(DateTime(2026, 8, 1), 'PAGI'), 'A');
    expect(anchor.teamCodeFor(DateTime(2026, 8, 3), 'MALAM'), 'C');
    // Days 3-5: B Pagi, A Malam.
    expect(anchor.teamCodeFor(DateTime(2026, 8, 4), 'PAGI'), 'B');
    expect(anchor.teamCodeFor(DateTime(2026, 8, 4), 'MALAM'), 'A');
    // Days 6-8: C Pagi, B Malam; then the cycle repeats.
    expect(anchor.teamCodeFor(DateTime(2026, 8, 9), 'PAGI'), 'C');
    expect(anchor.teamCodeFor(DateTime(2026, 8, 9), 'MALAM'), 'B');
    expect(anchor.teamCodeFor(DateTime(2026, 8, 10), 'PAGI'), 'A');
    // Before the anchor date the cycle runs backwards too.
    expect(anchor.teamCodeFor(DateTime(2026, 7, 31), 'PAGI'), 'C');
  });

  test('every team works each shift exactly once per 9-day cycle block', () {
    for (var day = 0; day < 9; day++) {
      final date = DateTime(2026, 8, 1).add(Duration(days: day));
      final pagi = anchor.teamCodeFor(date, 'PAGI');
      final malam = anchor.teamCodeFor(date, 'MALAM');
      expect(pagi, isNot(malam));
    }
  });

  test('night checks at 02:00 and 06:00 fall on the next calendar day', () {
    final checks = checksForShift(DateTime(2026, 9, 18), 'MALAM');
    expect(checks.map((check) => check.dueAt), <DateTime>[
      DateTime(2026, 9, 18, 22),
      DateTime(2026, 9, 19, 2),
      DateTime(2026, 9, 19, 6),
    ]);
    expect(checks.every((c) => c.sheetDate == DateTime(2026, 9, 18)), isTrue);
  });

  test('upcoming checks follow the team and skip past times', () {
    final checks = upcomingChecks(
      anchor,
      'A',
      from: DateTime(2026, 8, 3, 12),
      days: 2,
    );
    // 3 Aug: A Pagi (14:00, 18:00 left). 4 Aug: A Malam (22:00, then 02:00
    // and 06:00 on 5 Aug).
    expect(checks.map((c) => c.dueAt), <DateTime>[
      DateTime(2026, 8, 3, 14),
      DateTime(2026, 8, 3, 18),
      DateTime(2026, 8, 4, 22),
      DateTime(2026, 8, 5, 2),
      DateTime(2026, 8, 5, 6),
    ]);
  });

  test('current shift of an early-morning hour is last night Malam', () {
    expect(currentShift(DateTime(2026, 9, 18, 3)), (
      DateTime(2026, 9, 17),
      'MALAM',
    ));
    expect(currentShift(DateTime(2026, 9, 18, 8)), (
      DateTime(2026, 9, 18),
      'PAGI',
    ));
  });

  test('per-point limits replace the 60/70 default', () {
    final form = DailyCheckFormType.hydraulicFeeder.form;
    final pump = form.fields.firstWhere((field) => field.key == 'main_pump');
    expect(form.levelOf(pump, 65), DailyCheckTemperatureLevel.warning);
    DailyCheckThresholds.replaceAll(<String, DailyCheckLimits>{
      DailyCheckThresholds.key(DailyCheckFormType.hydraulicFeeder, 'main_pump'):
          const DailyCheckLimits(75, 85),
    });
    addTearDown(() => DailyCheckThresholds.replaceAll(const {}));
    expect(form.levelOf(pump, 65), DailyCheckTemperatureLevel.normal);
    expect(form.levelOf(pump, 80), DailyCheckTemperatureLevel.warning);
    expect(form.levelOf(pump, 85), DailyCheckTemperatureLevel.critical);
    expect(
      form.worstLevel(<String, Map<String, Object?>>{
        'check_1': <String, Object?>{'f1.main_pump': 70, 'f1.ambient': 71},
      }),
      DailyCheckTemperatureLevel.critical,
    );
  });
}
