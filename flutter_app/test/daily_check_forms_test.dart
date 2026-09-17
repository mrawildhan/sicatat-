import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/daily_checks/daily_check_forms.dart';

void main() {
  group('hydraulic feeder form', () {
    final form = DailyCheckFormType.hydraulicFeeder.form;

    Map<String, Object?> fullFeeder(String unit) => <String, Object?>{
      for (final field in form.fields)
        if (field.required) '$unit.${field.key}': 40,
    };

    test('has three checks at the times printed on the paper form', () {
      expect(
        form.slotsForShift('PAGI').map((slot) => slot.plannedTime),
        <String>['10:00', '14:00', '18:00'],
      );
      expect(
        form.slotsForShift('MALAM').map((slot) => slot.plannedTime),
        <String>['22:00', '02:00', '06:00'],
      );
    });

    test('a check is complete only when both feeders are filled', () {
      expect(form.slotState(null), DailyCheckSlotState.empty);
      expect(
        form.slotState(<String, Object?>{'recorded_at': 'x'}),
        DailyCheckSlotState.empty,
      );
      final one = fullFeeder('f1');
      expect(form.slotState(one), DailyCheckSlotState.partial);
      expect(form.missingCount(one), 13);
      expect(
        form.slotState(<String, Object?>{...one, ...fullFeeder('f2')}),
        DailyCheckSlotState.complete,
      );
    });

    test('speed is optional', () {
      final values = <String, Object?>{
        ...fullFeeder('f1'),
        ...fullFeeder('f2'),
      };
      expect(values.containsKey('f1.speed'), isFalse);
      expect(form.missingCount(values), 0);
    });

    test('a stopped feeder needs only a reason', () {
      final values = <String, Object?>{
        ...fullFeeder('f1'),
        'f2.status': 'not_running',
      };
      expect(form.missingCount(values), 1);
      values['f2.reason'] = 'Planned maintenance';
      expect(form.slotState(values), DailyCheckSlotState.complete);
    });

    test('pressure values do not count as temperatures', () {
      final readings = <String, Map<String, Object?>>{
        'check_1': <String, Object?>{'f1.main_pump': 58, 'f1.forward': 320},
      };
      expect(form.highestTemperature(readings), 58);
    });
  });

  group('coal valve form', () {
    final form = DailyCheckFormType.coalValve.form;

    test('has ten readings of four valves on four sides', () {
      expect(form.slotsForShift('PAGI'), hasLength(10));
      expect(form.units, hasLength(4));
      expect(form.fields, hasLength(4));
      expect(form.missingCount(<String, Object?>{}), 16);
    });
  });

  test('temperature bands follow the app rule', () {
    expect(temperatureLevel(59.9), DailyCheckTemperatureLevel.normal);
    expect(temperatureLevel(60), DailyCheckTemperatureLevel.warning);
    expect(temperatureLevel(69.9), DailyCheckTemperatureLevel.warning);
    expect(temperatureLevel(70), DailyCheckTemperatureLevel.critical);
  });

  test('form types round-trip through storage values', () {
    for (final type in DailyCheckFormType.values) {
      expect(DailyCheckFormType.fromStorage(type.storageValue), type);
    }
    expect(DailyCheckFormType.fromStorage('unknown'), isNull);
  });
}
