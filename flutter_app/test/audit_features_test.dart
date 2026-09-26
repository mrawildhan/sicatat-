import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sicatat_flutter/core/export/xlsx_export.dart';
import 'package:sicatat_flutter/data/models/operational_budget_models.dart';
import 'package:sicatat_flutter/data/models/purchase_requisition_models.dart';
import 'package:sicatat_flutter/features/daily_checks/alert_follow_up.dart';
import 'package:sicatat_flutter/features/daily_checks/check_schedule.dart';
import 'package:sicatat_flutter/features/daily_checks/compliance.dart';
import 'package:sicatat_flutter/features/documents/presentation/asset_history_screen.dart';
import 'package:sicatat_flutter/features/operations/presentation/budget_charts.dart';
import 'package:sicatat_flutter/features/operations/presentation/maintenance_backlog_trend.dart';
import 'package:sicatat_flutter/features/operations/presentation/pr_tracking.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('compliance', () {
    final RosterAnchor anchor = RosterAnchor(
      start: DateTime(2026, 8, 1),
      order: const <String>['A', 'B', 'C'],
    );

    test('a sheet sent within 2 hours after the shift is on time', () {
      final DateTime day = DateTime(2026, 9, 1);
      final DateTime now = DateTime(2026, 9, 5);
      ComplianceSheet sheet(DateTime sent) => ComplianceSheet(
        form: ComplianceForm.feederSizer,
        date: day,
        shiftCode: 'PAGI',
        status: 'submitted',
        submittedAt: sent,
      );
      expect(
        complianceStatusOf(
          sheet(DateTime(2026, 9, 1, 20, 30)),
          day,
          'PAGI',
          now,
        ),
        ComplianceStatus.onTime,
      );
      expect(
        complianceStatusOf(
          sheet(DateTime(2026, 9, 1, 21, 30)),
          day,
          'PAGI',
          now,
        ),
        ComplianceStatus.late,
      );
      // Shift Malam ends at 07:00 the next day.
      expect(
        complianceStatusOf(
          ComplianceSheet(
            form: ComplianceForm.coalValve,
            date: day,
            shiftCode: 'MALAM',
            status: 'submitted',
            submittedAt: DateTime(2026, 9, 2, 8),
          ),
          day,
          'MALAM',
          now,
        ),
        ComplianceStatus.onTime,
      );
      expect(
        complianceStatusOf(null, day, 'PAGI', now),
        ComplianceStatus.missing,
      );
      expect(
        complianceStatusOf(
          ComplianceSheet(
            form: ComplianceForm.feederSizer,
            date: day,
            shiftCode: 'PAGI',
            status: 'submitted_incomplete',
            submittedAt: DateTime(2026, 9, 1, 18),
          ),
          day,
          'PAGI',
          now,
        ),
        ComplianceStatus.incomplete,
      );
    });

    test('running and future shifts are not counted', () {
      final DateTime day = DateTime(2026, 9, 26);
      expect(
        complianceStatusOf(null, day, 'PAGI', DateTime(2026, 9, 26, 10)),
        ComplianceStatus.running,
      );
      expect(
        complianceStatusOf(null, day, 'MALAM', DateTime(2026, 9, 26, 10)),
        ComplianceStatus.upcoming,
      );
    });

    test('the month counts three sheets per ended shift, per roster crew', () {
      final ComplianceMonth month = ComplianceMonth(
        month: DateTime(2026, 9),
        anchor: anchor,
        now: DateTime(2026, 9, 2, 12),
        sheets: <ComplianceSheet>[
          ComplianceSheet(
            form: ComplianceForm.hydraulicFeeder,
            date: DateTime(2026, 9, 1),
            shiftCode: 'PAGI',
            status: 'submitted',
            submittedAt: DateTime(2026, 9, 1, 18),
            needsApproval: true,
          ),
        ],
      );
      // 1 Sep Pagi and Malam have ended: 2 shifts x 3 sheets.
      expect(month.due.length, 6);
      expect(month.count(ComplianceStatus.onTime), 1);
      expect(month.count(ComplianceStatus.missing), 5);
      expect(month.waitingApproval.length, 1);
      expect(
        month.cellsOf(DateTime(2026, 9, 1), 'PAGI').first.teamCode,
        anchor.teamCodeFor(DateTime(2026, 9, 1), 'PAGI'),
      );
      expect(month.crews.map((c) => c.due).fold<int>(0, (a, b) => a + b), 6);
      expect(month.dayStatus(DateTime(2026, 9, 1)), ComplianceStatus.missing);
      expect(month.dayStatus(DateTime(2026, 9, 20)), ComplianceStatus.upcoming);
    });

    test('a foreman sees only their crew', () {
      final ComplianceMonth month = ComplianceMonth(
        month: DateTime(2026, 9),
        anchor: anchor,
        now: DateTime(2026, 9, 30),
        sheets: const <ComplianceSheet>[],
        onlyTeam: 'B',
      );
      expect(month.cells.every((c) => c.teamCode == 'B'), isTrue);
      expect(month.crews.single.teamCode, 'B');
    });
  });

  test('xlsx export is a valid workbook with typed cells', () {
    final List<int> bytes = buildXlsx(
      sheetName: 'Uji/Data',
      title: 'Judul & <tes>',
      columns: const <XlsxColumn>[
        XlsxColumn('Teks'),
        XlsxColumn('Angka'),
        XlsxColumn('Tanggal'),
        XlsxColumn('Ya/tidak'),
      ],
      rows: <List<Object?>>[
        <Object?>['a & b', 12.5, DateTime(2026, 9, 26), true],
        <Object?>[null, 3, null, false],
      ],
    );
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.map((f) => f.name),
      containsAll(<String>[
        '[Content_Types].xml',
        'xl/workbook.xml',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]),
    );
    final String sheet = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(sheet, contains('Judul &amp; &lt;tes&gt;'));
    expect(sheet, contains('<v>12.5</v>'));
    // 26 September 2026 as an Excel serial date.
    expect(sheet, contains('<c r="C3" s="2"><v>46291</v></c>'));
    expect(sheet, contains('>Ya<'));
    final String workbook = utf8.decode(
      archive.findFile('xl/workbook.xml')!.content as List<int>,
    );
    expect(workbook, contains('name="Uji Data"'));
  });

  test('critical temperatures map to their Ellipse units', () {
    TemperatureAlertRecord alert(String form, String point) =>
        TemperatureAlertRecord(
          id: '1',
          formLabel: form,
          pointLabel: point,
          value: 75,
          limitValue: 70,
          occurredAt: DateTime(2026, 9, 1),
          status: AlertFollowUpStatus.open,
        );
    final TemperatureAlertRecord breaker = alert(
      'Daily Temperature Feeder Sizer',
      'Gearbox Breaker Ronde 1 - Bearing',
    );
    final TemperatureAlertRecord sizer = alert(
      'Daily Temperature Feeder Sizer',
      'Gearbox Sizer Ronde 2 - Motor',
    );
    final TemperatureAlertRecord valve = alert(
      'Temperature Coal Valve',
      'Pembacaan 4 - Sisi Selatan - RV04',
    );
    expect(alertBelongsToAsset('AFB01', breaker), isTrue);
    expect(alertBelongsToAsset('AFB01', sizer), isFalse);
    expect(alertBelongsToAsset('acr01', sizer), isTrue);
    expect(alertBelongsToAsset('AGV4', valve), isTrue);
    expect(alertBelongsToAsset('AGV1', valve), isFalse);
    expect(assetHasTemperature('ACV11'), isFalse);
  });

  test('open PRs exclude closed, cancelled and rejected ones', () {
    PurchaseRequisition pr({String? po, String? status, DateTime? closed}) =>
        PurchaseRequisition(
          id: '1',
          noPr: '32000',
          noPo: po,
          description: null,
          equipmentReference: null,
          closedDate: closed,
          releaseDate: DateTime(2026, 6, 1),
          status: status,
        );
    expect(isPurchaseRequisitionOpen(pr(po: 'P52598')), isTrue);
    expect(
      isPurchaseRequisitionOpen(pr(po: 'WAS REJECTED 21 Okt 25')),
      isFalse,
    );
    expect(isPurchaseRequisitionOpen(pr(status: 'CANCEL')), isFalse);
    expect(
      isPurchaseRequisitionOpen(pr(closed: DateTime(2026, 7, 1))),
      isFalse,
    );
    expect(isPurchaseOrderNumber('P52598'), isTrue);
    expect(isPurchaseOrderNumber('WAS APPROVED'), isFalse);
    expect(prAgeDays(pr(), DateTime(2026, 9, 26)), 117);
  });

  test('budget analysis projects the year from months with actuals', () {
    final OperationalBudgetSummary summary = OperationalBudgetSummary(
      <OperationalBudgetMonth>[
        for (int m = 1; m <= 12; m++)
          OperationalBudgetMonth(
            site: 'CPP',
            period: DateTime(2026, m),
            budgetUsd: 100,
            actualUsd: m <= 3 ? 150 : 0,
            syncedAt: null,
          ),
      ],
    );
    final BudgetAnalysis analysis = BudgetAnalysis(
      summary,
      const <OperationalBudgetItem>[],
    );
    expect(analysis.lastActual, DateTime(2026, 3));
    expect(analysis.budgetToDate, 300);
    expect(analysis.actualToDate, 450);
    expect(analysis.budgetYear, 1200);
    expect(analysis.projectedYear, 1800);
  });

  test('backlog comparison picks the newest point far enough back', () {
    final List<BacklogPoint> points = <BacklogPoint>[
      for (int d = 1; d <= 20; d++) BacklogPoint(DateTime(2026, 9, d))..pm = d,
    ];
    expect(backlogPointBefore(points, 7)!.day, DateTime(2026, 9, 13));
    expect(backlogPointBefore(points, 30), isNull);
  });
}
