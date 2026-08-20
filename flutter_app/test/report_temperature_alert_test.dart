import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/reports/report_export_service.dart';

ReportRow _row({required String value, required String unit}) => ReportRow(
  date: '2026-08-20',
  team: 'Crew A',
  shift: 'Pagi',
  section: 'Gearbox Breaker',
  round: 1,
  time: '08:00',
  side: 'West',
  unitStatus: 'Operating',
  equipment: 'Feeder Breaker',
  point: 'Motor DE',
  value: value,
  unit: unit,
  recordedBy: 'Tester',
  sheetStatus: 'draft',
  isAnomaly: false,
);

void main() {
  test('marks 60 to 69 Celsius as high for reports and CSV', () {
    final ReportRow row = _row(value: '64.5', unit: 'C');

    expect(row.temperatureCelsius, 64.5);
    expect(row.isHighTemperature, isTrue);
    expect(row.isCriticalTemperature, isFalse);
    expect(row.alertLabel, 'HIGH 60-69°C');
  });

  test('marks 70 Celsius and above as critical', () {
    final ReportRow row = _row(value: '70', unit: '°C');

    expect(row.isCriticalTemperature, isTrue);
    expect(row.alertLabel, 'CRITICAL >=70°C');
  });
}
