import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/pdf/report_pdf.dart';
import '../../data/models/operational_budget_models.dart';
import '../../data/models/preventive_maintenance_models.dart';
import '../../data/models/purchase_requisition_models.dart';
import '../../data/models/sicatat_types.dart';
import '../../data/services/operational_budget_service.dart';
import '../../data/services/preventive_maintenance_service.dart';
import '../daily_checks/alert_follow_up.dart';
import '../daily_checks/compliance.dart';
import '../operations/maintenance_report.dart';
import '../operations/presentation/budget_charts.dart';
import '../operations/presentation/maintenance_backlog_trend.dart';
import '../operations/presentation/pr_tracking.dart';
import '../warehouse/warehouse_data.dart';

/// Laporan Bulanan (owner request 2026-09-26): one PDF with the month's
/// temperatures and follow-up, check compliance, PM & CM backlog, budget,
/// PR and warehouse, ready to send to a superior or show an auditor.
/// Every section loads on its own; one the role may not read is left out.
class MonthlyReportData {
  MonthlyReportData({required this.month});

  final DateTime month;
  ComplianceMonth? compliance;
  List<TemperatureAlertRecord>? alerts;
  List<PreventiveMaintenanceWorkOrder>? pm;
  List<CorrectiveMaintenanceWorkOrder>? cm;
  List<BacklogPoint>? backlog;
  BudgetAnalysis? budget;
  List<PurchaseRequisition>? prReleased;
  int? prClosed;
  List<PurchaseRequisition>? prOpen;
  int? outstandingPo;
  int? outstandingPoOverdue;
  int? receipts;
  int? pickups;
  int? lateLoans;
  final List<String> unavailable = <String>[];

  DateTime get start => DateTime(month.year, month.month);
  DateTime get end => DateTime(month.year, month.month + 1);
  String get label => DateFormat('MMMM yyyy', 'id_ID').format(month);
}

Future<MonthlyReportData> loadMonthlyReport(
  SupabaseClient client,
  DateTime month, {
  String? onlyTeamId,
}) async {
  final MonthlyReportData data = MonthlyReportData(month: month);
  final DateFormat day = DateFormat('yyyy-MM-dd');
  final DateTime today = DateTime.now();

  Future<void> section(String label, Future<void> Function() load) async {
    try {
      await load();
    } on Object {
      data.unavailable.add(label);
    }
  }

  List<Object?> list(Object? rows) => rows is List ? rows : const <Object?>[];

  await Future.wait(<Future<void>>[
    section('kepatuhan pengisian', () async {
      data.compliance = await loadComplianceMonth(
        client,
        month,
        onlyTeamId: onlyTeamId,
      );
    }),
    section('suhu kritis', () async {
      data.alerts = await AlertFollowUpService(client)
          .load(from: data.start, to: data.end);
    }),
    section('PM & CM', () async {
      final PreventiveMaintenanceService service = PreventiveMaintenanceService(
        client,
      );
      data.pm = await service.loadOutstanding();
      data.cm = await service.loadCorrectiveOutstanding();
      data.backlog = (await loadBacklogHistory(client, days: 400))
          .where(
            (BacklogPoint p) =>
                !p.day.isBefore(data.start) && p.day.isBefore(data.end),
          )
          .toList(growable: false);
    }),
    section('anggaran', () async {
      final OperationalBudgetService service = OperationalBudgetService(client);
      final OperationalBudgetSummary summary = await service.loadSummary();
      final List<OperationalBudgetItem> items = await service.loadItems();
      data.budget = BudgetAnalysis(summary, items);
    }),
    section('PR', () async {
      const String columns =
          'id,no_pr,no_po,description,equip_ref,closed_date,release_date,status';
      final List<Object?> released = list(
        await client
            .from('purchase_requisition')
            .select(columns)
            .gte('release_date', day.format(data.start))
            .lt('release_date', day.format(data.end))
            .order('release_date', ascending: true)
            .limit(1000),
      );
      final List<Object?> closed = list(
        await client
            .from('purchase_requisition')
            .select('id')
            .gte('closed_date', day.format(data.start))
            .lt('closed_date', day.format(data.end))
            .limit(1000),
      );
      final List<Object?> open = list(
        await client
            .from('purchase_requisition')
            .select(columns)
            .isFilter('closed_date', null)
            .gte(
              'release_date',
              day.format(today.subtract(const Duration(days: 365))),
            )
            .limit(2000),
      );
      data.prReleased = <PurchaseRequisition>[
        for (final Object? row in released)
          PurchaseRequisition.fromJson(requireJsonMap(row)),
      ];
      data.prClosed = closed.length;
      data.prOpen = <PurchaseRequisition>[
        for (final Object? row in open)
          PurchaseRequisition.fromJson(requireJsonMap(row)),
      ].where(isPurchaseRequisitionOpen).toList(growable: false);
    }),
    section('barang dipesan', () async {
      final List<Object?> rows = list(
        await client
            .from('warehouse_outstanding_po')
            .select('due_date')
            .limit(5000),
      );
      data.outstandingPo = rows.length;
      data.outstandingPoOverdue = rows.where((Object? row) {
        final DateTime? due = DateTime.tryParse(
          requireJsonMap(row).optionalString('due_date') ?? '',
        );
        return due != null && due.isBefore(warehouseDateOnly(today));
      }).length;
    }),
    section('penerimaan & pinjaman gudang', () async {
      final List<Object?> receipts = list(
        await client
            .from('warehouse_receipt')
            .select('id')
            .gte('received_on', day.format(data.start))
            .lt('received_on', day.format(data.end))
            .limit(10000),
      );
      final List<Object?> loans = list(
        await client
            .from('warehouse_list_order_loan')
            .select('loaned_on')
            .eq('returned', false)
            .limit(5000),
      );
      final List<Object?> appLoans = list(
        await client
            .from('warehouse_tool_loan_item')
            .select('loan:loan_id(loaned_on)')
            .isFilter('returned_at', null)
            .limit(5000),
      );
      data.receipts = receipts.length;
      int late = 0;
      for (final Object? row in loans) {
        final DateTime? on = DateTime.tryParse(
          requireJsonMap(row).optionalString('loaned_on') ?? '',
        );
        if (on != null && warehouseLoanAgeDays(on) > warehouseLoanOverdueDays) {
          late++;
        }
      }
      for (final Object? row in appLoans) {
        final Object? loan = requireJsonMap(row)['loan'];
        final DateTime? on = loan is Map
            ? DateTime.tryParse('${loan['loaned_on']}')
            : null;
        if (on != null && warehouseLoanAgeDays(on) > warehouseLoanOverdueDays) {
          late++;
        }
      }
      data.lateLoans = late;
    }),
    section('pengambilan barang', () async {
      final List<Object?> issues = list(
        await client
            .from('warehouse_issue_history')
            .select('id')
            .gte('issued_on', day.format(data.start))
            .lt('issued_on', day.format(data.end))
            .limit(20000),
      );
      data.pickups = issues.length;
    }),
  ]);
  return data;
}

String _percent(double rate) => '${(rate * 100).round()}%';

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

Future<Uint8List> buildMonthlyReportPdf(
  MonthlyReportData data, {
  required pw.ThemeData theme,
}) {
  final String title = 'Laporan Bulanan ${data.label}';
  final DateTime today = DateTime.now();
  final pw.Document document = pw.Document(theme: theme, title: title);
  final List<pw.Widget> body = <pw.Widget>[
    ...reportHeading(
      title,
      'CPP & PORT Asam-Asam · dibuat ${reportDate(today)} dari data SICATAT',
    ),
  ];

  // 1. Temperatures and compliance.
  final ComplianceMonth? compliance = data.compliance;
  final List<TemperatureAlertRecord>? alerts = data.alerts;
  body.add(reportSectionTitle('1. Pemeriksaan suhu'));
  if (compliance != null) {
    body.add(
      reportFigures(<ReportFigure>[
        ReportFigure('Lembar jatuh tempo', '${compliance.due.length}'),
        ReportFigure('Terisi', _percent(compliance.filledRate)),
        ReportFigure('Tepat waktu', _percent(compliance.onTimeRate)),
        ReportFigure(
          'Tidak ada',
          '${compliance.count(ComplianceStatus.missing)}',
          color: reportDanger,
        ),
        ReportFigure(
          'Belum disetujui',
          '${compliance.waitingApproval.length}',
          color: reportOrange,
        ),
      ]),
    );
    body.add(pw.SizedBox(height: 6));
    body.add(
      reportTable(
        headers: const <String>[
          'Crew',
          'Jatuh tempo',
          'Tepat waktu',
          'Terlambat',
          'Belum lengkap',
          'Tidak ada',
          'Terisi',
        ],
        centered: const <int>{0, 1, 2, 3, 4, 5, 6},
        bold: const <int>{0},
        rows: <List<String>>[
          for (final ComplianceCrewSummary crew in compliance.crews)
            <String>[
              crew.teamCode,
              '${crew.due}',
              '${crew.onTime}',
              '${crew.late}',
              '${crew.incomplete}',
              '${crew.missing}',
              _percent(crew.filledRate),
            ],
        ],
      ),
    );
  }
  if (alerts != null) {
    int count(AlertFollowUpStatus status) =>
        alerts.where((a) => a.status == status).length;
    body.add(pw.SizedBox(height: 8));
    body.add(
      reportNote(
        'Suhu kritis bulan ini: ${alerts.length} · terbuka '
        '${count(AlertFollowUpStatus.open)} · ditangani '
        '${count(AlertFollowUpStatus.inProgress)} · ditutup '
        '${count(AlertFollowUpStatus.closed)}',
      ),
    );
    if (alerts.isNotEmpty) {
      body.add(
        reportTable(
          headers: const <String>[
            'Waktu',
            'Titik ukur',
            '°C',
            'Regu',
            'Status',
            'Tindakan',
          ],
          centered: const <int>{0, 2, 3, 4},
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(58),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FixedColumnWidth(24),
            3: pw.FixedColumnWidth(40),
            4: pw.FixedColumnWidth(44),
            5: pw.FlexColumnWidth(2.4),
          },
          rows: <List<String>>[
            for (final TemperatureAlertRecord a in alerts.take(30))
              <String>[
                DateFormat('d/M HH.mm').format(a.occurredAt),
                a.pointLabel,
                _number(a.value),
                a.teamName ?? '-',
                a.status.label,
                a.action ?? '-',
              ],
          ],
          cellColor: (int row, int column) => column == 2 ? reportDanger : null,
        ),
      );
      if (alerts.length > 30) {
        body.add(
          reportNote(
            '${alerts.length - 30} suhu kritis lain ada di menu Tindak lanjut suhu kritis.',
          ),
        );
      }
    }
  }

  // 2. PM & CM.
  final List<PreventiveMaintenanceWorkOrder>? pm = data.pm;
  final List<CorrectiveMaintenanceWorkOrder>? cm = data.cm;
  if (pm != null && cm != null) {
    body.add(
      reportSectionTitle('2. PM & CM tertunda (posisi saat laporan dibuat)'),
    );
    final int pmLate = pm
        .where(
          (w) =>
              w.plannedStartOn != null &&
              w.plannedStartOn!.isBefore(
                DateTime(today.year, today.month, today.day),
              ),
        )
        .length;
    body.add(
      reportFigures(<ReportFigure>[
        ReportFigure('PM tertunda', '${pm.length}', color: reportOrange),
        ReportFigure('PM lewat rencana', '$pmLate', color: reportDanger),
        ReportFigure('CM tertunda', '${cm.length}', color: reportDanger),
        ReportFigure(
          'CM > 30 hari',
          '${cm.where((w) => w.raisedOn != null && today.difference(w.raisedOn!).inDays > 30).length}',
          color: reportDanger,
        ),
      ]),
    );
    body.add(pw.SizedBox(height: 6));
    body.add(
      reportBars(<(String, double, PdfColor)>[
        for (final String crew in maintenanceCrews)
          for (final String site in maintenanceSites)
            (
              'PM Crew $crew $site',
              pm
                  .where((w) => w.crew == crew && w.site == site)
                  .length
                  .toDouble(),
              site == 'CPP' ? reportGreen : reportOrange,
            ),
        for (final String site in maintenanceSites)
          (
            'CM $site',
            cm.where((w) => w.site == site).length.toDouble(),
            reportDanger,
          ),
      ]),
    );
    final List<BacklogPoint> backlog = data.backlog ?? const <BacklogPoint>[];
    if (backlog.length >= 2) {
      final BacklogPoint first = backlog.first;
      final BacklogPoint last = backlog.last;
      body.add(
        reportNote(
          'Selama bulan ini (${reportDate(first.day)} → ${reportDate(last.day)}): '
          'PM ${first.pm} → ${last.pm}, CM ${first.cm} → ${last.cm}.',
        ),
      );
    } else {
      body.add(
        reportNote(
          'Riwayat backlog harian tercatat sejak 26 September 2026; '
          'perbandingan awal–akhir bulan muncul setelah dua hari data.',
        ),
      );
    }
  }

  // 3. Budget.
  final BudgetAnalysis? budget = data.budget;
  if (budget != null && budget.periods.isNotEmpty) {
    body.add(reportSectionTitle('3. Anggaran operasional (USD)'));
    final DateTime period = DateTime(data.month.year, data.month.month);
    final bool inYear = budget.periods.contains(period);
    body.add(
      reportFigures(<ReportFigure>[
        if (inYear)
          ReportFigure(
            'Anggaran ${data.label}',
            budgetUsd(budget.budgetOf(period)),
          ),
        if (inYear)
          ReportFigure(
            'Aktual ${data.label}',
            budget.actualOf(period) == 0
                ? 'belum ada'
                : budgetUsd(budget.actualOf(period)),
            color: budget.actualOf(period) > budget.budgetOf(period)
                ? reportDanger
                : reportGreen,
          ),
        ReportFigure(
          'Aktual s.d. ${budget.lastActual == null ? '-' : DateFormat('MMM', 'id_ID').format(budget.lastActual!)}',
          budgetUsd(budget.actualToDate),
        ),
        ReportFigure(
          'Proyeksi setahun',
          budgetUsd(budget.projectedYear),
          color: budget.projectedYear > budget.budgetYear
              ? reportDanger
              : reportGreen,
        ),
        ReportFigure('Anggaran setahun', budgetUsd(budget.budgetYear)),
      ]),
    );
    final List<(OperationalBudgetItem, double, double)> over = budget.overspent;
    if (over.isNotEmpty) {
      body.add(pw.SizedBox(height: 6));
      body.add(reportNote('Elemen biaya di atas anggaran (kumulatif):'));
      body.add(
        reportTable(
          headers: const <String>[
            'Lokasi',
            'Elemen biaya',
            'Anggaran',
            'Aktual',
            'Selisih',
          ],
          centered: const <int>{0},
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(36),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(70),
            3: pw.FixedColumnWidth(70),
            4: pw.FixedColumnWidth(70),
          },
          rows: <List<String>>[
            for (final (OperationalBudgetItem item, double b, double a)
                in over.take(10))
              <String>[
                item.site,
                item.description,
                budgetUsd(b),
                budgetUsd(a),
                '+${budgetUsd(a - b)}',
              ],
          ],
          cellColor: (int row, int column) => column == 4 ? reportDanger : null,
        ),
      );
    }
  }

  // 4. PR & warehouse.
  body.add(reportSectionTitle('4. PR & gudang'));
  final List<PurchaseRequisition>? prOpen = data.prOpen;
  body.add(
    reportFigures(<ReportFigure>[
      if (data.prReleased != null)
        ReportFigure('PR dirilis bulan ini', '${data.prReleased!.length}'),
      if (data.prClosed != null)
        ReportFigure('PR barang datang', '${data.prClosed}'),
      if (prOpen != null)
        ReportFigure(
          'PR terbuka > 90 hari',
          '${prOpen.where((pr) => prAgeDays(pr, today) > 90).length}',
          color: reportDanger,
        ),
    ]),
  );
  body.add(pw.SizedBox(height: 6));
  body.add(
    reportFigures(<ReportFigure>[
      if (data.outstandingPo != null)
        ReportFigure(
          'PO belum datang',
          '${data.outstandingPo} (${data.outstandingPoOverdue} lewat)',
          color: reportOrange,
        ),
      if (data.receipts != null)
        ReportFigure('Penerimaan gudang', '${data.receipts}'),
      if (data.pickups != null)
        ReportFigure('Pengambilan barang', '${data.pickups}'),
      if (data.lateLoans != null)
        ReportFigure(
          'Alat terlambat kembali',
          '${data.lateLoans}',
          color: data.lateLoans! > 0 ? reportDanger : reportGreen,
        ),
    ]),
  );
  if (prOpen != null) {
    body.add(pw.SizedBox(height: 6));
    body.add(
      reportBars(<(String, double, PdfColor)>[
        for (final (String label, int from, int to) in prAgeBuckets)
          (
            'PR terbuka $label',
            prOpen
                .where((pr) {
                  final int age = prAgeDays(pr, today);
                  return age >= from && age <= to;
                })
                .length
                .toDouble(),
            from > 60 ? reportDanger : reportGreen,
          ),
      ], labelWidth: 110),
    );
  }
  if (data.unavailable.isNotEmpty) {
    body.add(pw.SizedBox(height: 10));
    body.add(
      reportNote(
        'Tidak termasuk (tidak tersedia untuk peran pembuat laporan): '
        '${data.unavailable.join(', ')}.',
      ),
    );
  }

  document.addPage(
    reportPage(title: title, build: (pw.Context context) => body),
  );
  return document.save();
}
