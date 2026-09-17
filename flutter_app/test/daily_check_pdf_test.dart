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
  submitterName: 'Tester',
  notes: 'Sample notes',
);

void main() {
  // Set DAILY_CHECK_PDF_DIR to keep the files for a visual check.
  final outputDir = Platform.environment['DAILY_CHECK_PDF_DIR'];

  test(
    'hydraulic feeder PDF builds with values, a stopped feeder and remarks',
    () async {
      final form = DailyCheckFormType.hydraulicFeeder.form;
      final bytes = await buildDailyCheckPdf(
        _sheet(
          DailyCheckFormType.hydraulicFeeder,
          <String, Map<String, Object?>>{
            'check_1': <String, Object?>{
              for (final field in form.fields)
                'f1.${field.key}':
                    40 + form.fields.toList().indexOf(field) * 2.5,
              'f2.status': 'not_running',
              'f2.reason': 'Planned maintenance',
              'remarks': 'Small oil seep on feeder 1',
              'recorded_at': '2026-09-17T02:05:00Z',
            },
            'check_2': <String, Object?>{'f1.ambient': 33, 'f2.main_pump': 72},
          },
        ),
      );
      expect(bytes.length, greaterThan(1000));
      if (outputDir != null) {
        File('$outputDir/hydraulic.pdf').writeAsBytesSync(bytes);
      }
    },
  );

  test('coal valve PDF builds with ten readings', () async {
    final bytes = await buildDailyCheckPdf(
      _sheet(DailyCheckFormType.coalValve, <String, Map<String, Object?>>{
        'reading_1': <String, Object?>{
          for (final side in <String>['west', 'east', 'north', 'south'])
            for (final valve in <String>['rv01', 'rv02', 'rv03', 'rv04'])
              '$side.$valve': side == 'east' && valve == 'rv02' ? 65 : 42,
          'recorded_at': '2026-09-17T00:30:00Z',
          'remarks': 'East RV02 warm',
        },
        'reading_2': <String, Object?>{'west.rv01': 71},
      }),
    );
    expect(bytes.length, greaterThan(1000));
    if (outputDir != null) {
      File('$outputDir/coal_valve.pdf').writeAsBytesSync(bytes);
    }
  });
}
