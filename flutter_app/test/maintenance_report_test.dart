import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sicatat_flutter/data/models/preventive_maintenance_models.dart';
import 'package:sicatat_flutter/features/operations/maintenance_report.dart';

PreventiveMaintenanceWorkOrder _pm(
  String wo,
  String crew,
  String site,
  DateTime raised,
) => PreventiveMaintenanceWorkOrder(
  workOrder: wo,
  description: 'PM $wo',
  equipmentReference: 'EQ-$wo',
  crew: crew,
  site: site,
  status: 'A',
  raisedOn: raised,
);

CorrectiveMaintenanceWorkOrder _cm(String wo, String site, DateTime raised) =>
    CorrectiveMaintenanceWorkOrder(
      workOrder: wo,
      description: 'CM $wo',
      equipmentReference: 'EQ-$wo',
      site: site,
      priority: '2',
      raisedOn: raised,
      progress: 'Menunggu part',
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  final DateTime today = DateTime(2026, 9, 25);

  test('umur PM & CM dikelompokkan 0–7, 8–14, 15–30, >30 hari', () {
    expect(maintenanceAgeDays(DateTime(2026, 9, 18), today), 7);
    expect(maintenanceAgeDays(null, today), isNull);
    expect(
      maintenanceAgeCounts(<DateTime?>[
        DateTime(2026, 9, 25),
        DateTime(2026, 9, 18),
        DateTime(2026, 9, 17),
        DateTime(2026, 8, 26),
        DateTime(2026, 8, 25),
        null,
      ], today),
      <int>[2, 1, 1, 1],
    );
  });

  test(
    'laporan foreman: PM crew-nya di CPP & PORT, semua CM, terlama dulu',
    () async {
      final MaintenanceReport report = MaintenanceReport(
        crew: 'A',
        pm: <PreventiveMaintenanceWorkOrder>[
          _pm('1', 'A', 'CPP', DateTime(2026, 9, 1)),
          _pm('2', 'A', 'CPP', DateTime(2026, 8, 12)),
          _pm('3', 'B', 'CPP', DateTime(2026, 8, 12)),
          _pm('4', 'A', 'PORT', DateTime(2026, 9, 4)),
        ],
        cm: <CorrectiveMaintenanceWorkOrder>[
          _cm('9', 'CPP', DateTime(2026, 8, 1)),
          _cm('8', 'PORT', DateTime(2026, 9, 1)),
        ],
        today: today,
      );
      expect(report.pmAt('CPP').map((item) => item.workOrder), <String>[
        '2',
        '1',
      ]);
      expect(report.pmAt('PORT').map((item) => item.workOrder), <String>['4']);
      expect(report.cm, hasLength(2));
      expect(report.fileName, 'PM CM Tertunda Crew A 25-09-2026.pdf');

      final List<int> bytes = await buildMaintenancePdf(
        report,
        theme: pw.ThemeData.base(),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
}
