import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/admin/presentation/threshold_management_screen.dart';

({Map<String, Object?>? payload, String? error}) _validate({
  String warningMin = '',
  String warningMax = '',
  String alarmMin = '',
  String alarmMax = '',
  String delta = '',
  String sourceNote = 'OEM manual',
}) => validateThresholdInput(
  pointId: 'point-1',
  warningMin: warningMin,
  warningMax: warningMax,
  alarmMin: alarmMin,
  alarmMax: alarmMax,
  delta: delta,
  sourceNote: sourceNote,
  isActive: true,
);

void main() {
  test('accepts comma decimals and builds the payload', () {
    final result = _validate(warningMin: '55,5', alarmMin: '65', delta: '8');
    expect(result.error, isNull);
    expect(result.payload, <String, Object?>{
      'measurement_point_id': 'point-1',
      'warning_min': 55.5,
      'warning_max': null,
      'alarm_min': 65.0,
      'alarm_max': null,
      'delta_max_per_round': 8.0,
      'source_note': 'OEM manual',
      'is_active': true,
    });
  });

  test('rejects text that is not a number instead of saving null', () {
    expect(
      _validate(warningMin: 'abc').error,
      'Warning minimum harus berupa angka.',
    );
    expect(_validate(alarmMin: '-').error, 'Alarm minimum harus berupa angka.');
  });

  test('requires at least one limit and a source note', () {
    expect(_validate().error, 'Isi minimal satu batas warning atau alarm.');
    expect(
      _validate(alarmMin: '75', sourceNote: '  ').error,
      'Sumber atau referensi engineering wajib diisi.',
    );
  });

  test('keeps warning below alarm, including the 60/70 defaults', () {
    expect(_validate(warningMin: '70', alarmMin: '70').payload, isNull);
    expect(
      _validate(warningMin: '72').error,
      'Batas warning (72°C) harus lebih rendah dari batas alarm (70°C).',
    );
    expect(_validate(alarmMin: '65').error, isNull);
    expect(_validate(warningMin: '69', warningMax: '60').payload, isNull);
  });

  test('delta must be positive', () {
    expect(
      _validate(alarmMin: '75', delta: '0').error,
      'Perubahan maksimum antar ronde harus lebih dari 0.',
    );
  });

  test('formats whole numbers without a trailing .0', () {
    expect(formatThresholdNumber(60), '60');
    expect(formatThresholdNumber(60.5), '60.5');
  });
}
