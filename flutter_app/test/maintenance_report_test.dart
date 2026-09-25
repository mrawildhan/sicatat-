import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sicatat_flutter/data/models/preventive_maintenance_models.dart';
import 'package:sicatat_flutter/features/operations/maintenance_report.dart';

PreventiveMaintenanceWorkOrder _pm(
  String wo,
  String crew,
  String site,
  DateTime raised, [
  DateTime? planned,
]) => PreventiveMaintenanceWorkOrder(
  workOrder: wo,
  description: 'PM $wo',
  equipmentReference: 'EQ-$wo',
  crew: crew,
  site: site,
  status: 'A',
  raisedOn: raised,
  plannedStartOn: planned,
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

  test('umur dihitung dari tanggal dibuat', () {
    expect(maintenanceAgeDays(DateTime(2026, 9, 18), today), 7);
    expect(maintenanceAgeDays(DateTime(2026, 9, 26), today), 0);
    expect(maintenanceAgeDays(null, today), isNull);
  });

  test('PDF PM per crew dan PDF CM terpisah, terlama dulu', () async {
    final List<PreventiveMaintenanceWorkOrder> pm =
        <PreventiveMaintenanceWorkOrder>[
          _pm('1', 'A', 'CPP', DateTime(2026, 9, 1)),
          _pm('2', 'A', 'CPP', DateTime(2026, 8, 12)),
          _pm('3', 'B', 'CPP', DateTime(2026, 8, 12), DateTime(2026, 9, 24)),
          _pm('4', 'A', 'PORT', DateTime(2026, 9, 4)),
        ];
    final List<CorrectiveMaintenanceWorkOrder> cm =
        <CorrectiveMaintenanceWorkOrder>[
          _cm('9', 'CPP', DateTime(2026, 8, 1)),
          _cm('8', 'PORT', DateTime(2026, 9, 1)),
        ];

    final MaintenanceReport pmReport = MaintenanceReport(
      kind: MaintenanceReportKind.pm,
      crew: 'A',
      pm: pm,
      cm: cm,
      today: today,
    );
    expect(pmReport.pmAt('CPP').map((item) => item.workOrder), <String>[
      '2',
      '1',
    ]);
    expect(pmReport.pmAt('PORT').map((item) => item.workOrder), <String>['4']);
    expect(pmReport.cm, isEmpty);
    expect(pmReport.title, 'PM Outstanding · Crew A');
    expect(pmReport.fileName, 'PM Outstanding Crew A 25-09-2026.pdf');
    // Period ends at the latest Plan Start Date of the whole PM export.
    expect(pmReport.periodLabel, '01 - 24 September 2026');

    final MaintenanceReport cmReport = MaintenanceReport(
      kind: MaintenanceReportKind.cm,
      pm: pm,
      cm: cm,
      today: today,
    );
    expect(cmReport.pm, isEmpty);
    expect(cmReport.cmAt('CPP').single.workOrder, '9');
    expect(cmReport.title, 'CM Outstanding · CPP & PORT');
    expect(cmReport.fileName, 'CM Outstanding CPP PORT 25-09-2026.pdf');

    for (final MaintenanceReport report in <MaintenanceReport>[
      pmReport,
      cmReport,
    ]) {
      final List<int> bytes = await buildMaintenancePdf(
        report,
        theme: pw.ThemeData.base(),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });
}
