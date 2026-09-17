import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/daily_checks/daily_check_forms.dart';
import 'package:sicatat_flutter/features/daily_checks/daily_check_pdf.dart';
import 'package:sicatat_flutter/features/daily_checks/daily_check_repository.dart';

DailyCheckSheet _sheet(
  DailyCheckFormType type,
  Map<String, Map<String, Object?>> readings,
) => DailyCheckSheet(
  id: 'test',
  type: type,
  date: DateTime(2026, 9, 17),
  shiftId: 'shift',
  teamId: 'team',
  status: DailyCheckStatus.submitted,
  readings: readings,
  createdBy: 'user',
  createdAt: DateTime(2026, 9, 17, 8),
  shiftCode: 'PAGI',
  teamName: 'Crew A',
  submitterName: 'Penguji',
  notes: 'Catatan contoh',
);

Future<void> _build(DailyCheckSheet sheet, String name) async {
  final background = File(sheet.form.printBackground).readAsBytesSync();
  final bytes = await buildDailyCheckPdf(sheet, background: background);
  expect(bytes.length, greaterThan(background.length));
  // Set DAILY_CHECK_PDF_DIR to keep the files for a visual check.
  final outputDir = Platform.environment['DAILY_CHECK_PDF_DIR'];
  if (outputDir != null) File('$outputDir/$name').writeAsBytesSync(bytes);
}

void main() {
  test('hydraulic feeder PDF fills the paper form', () async {
    final form = DailyCheckFormType.hydraulicFeeder.form;
    final fields = form.fields.toList();
    await _build(
      _sheet(DailyCheckFormType.hydraulicFeeder, <String, Map<String, Object?>>{
        'check_1': <String, Object?>{
          for (final field in fields)
            'f1.${field.key}': 40 + fields.indexOf(field) * 2.5,
          'f2.status': 'not_running',
          'f2.reason': 'Perawatan terjadwal',
          'remarks': 'Rembesan oli kecil di feeder 1',
          'recorded_at': '2026-09-17T02:05:00Z',
        },
        'check_2': <String, Object?>{'f1.ambient': 33, 'f2.main_pump': 72},
      }),
      'hydraulic.pdf',
    );
  });

  test('coal valve PDF fills the paper form', () async {
    await _build(
      _sheet(DailyCheckFormType.coalValve, <String, Map<String, Object?>>{
        'reading_1': <String, Object?>{
          for (final side in <String>['west', 'east', 'north', 'south'])
            for (final valve in <String>['rv01', 'rv02', 'rv03', 'rv04'])
              '$side.$valve': side == 'east' && valve == 'rv02' ? 65 : 42,
          'recorded_at': '2026-09-17T00:30:00Z',
          'remarks': 'RV02 sisi timur hangat',
        },
        'reading_4': <String, Object?>{
          'west.rv01': 71,
          'recorded_at': '2026-09-17T09:00:00Z',
        },
      }),
      'coal_valve.pdf',
    );
  });
}
