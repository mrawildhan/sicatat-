import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/preventive_maintenance_models.dart';

/// Crews and sites of the PM & CM report. Crew A/B/C each work at both CPP
/// and PORT, so one foreman gets both sites of their crew.
const List<String> maintenanceCrews = <String>['A', 'B', 'C'];
const List<String> maintenanceSites = <String>['CPP', 'PORT'];

/// Days since [raisedOn], or null when the sheet has no raise date.
int? maintenanceAgeDays(DateTime? raisedOn, DateTime today) {
  if (raisedOn == null) return null;
  final DateTime day = DateTime(today.year, today.month, today.day);
  final DateTime raised = DateTime(raisedOn.year, raisedOn.month, raisedOn.day);
  final int days = day.difference(raised).inDays;
  return days < 0 ? 0 : days;
}

/// Oldest first, so the longest-waiting work sits at the top of each list.
List<T> _oldestFirst<T>(Iterable<T> items, DateTime? Function(T) raised) =>
    items.toList()..sort((T a, T b) {
      final DateTime? x = raised(a);
      final DateTime? y = raised(b);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });

/// PM and CM go to foremen as separate PDFs (owner request 2026-09-25).
enum MaintenanceReportKind { pm, cm }

/// PM grouped by crew (A, B, C), oldest first within each crew.
List<PreventiveMaintenanceWorkOrder> _byCrewThenOldest(
  Iterable<PreventiveMaintenanceWorkOrder> items,
) {
  final List<PreventiveMaintenanceWorkOrder> oldest = _oldestFirst(
    items,
    (PreventiveMaintenanceWorkOrder item) => item.raisedOn,
  );
  // List.sort is not stable, so sort by crew and keep the age order by index.
  final Map<PreventiveMaintenanceWorkOrder, int> rank =
      <PreventiveMaintenanceWorkOrder, int>{
        for (int i = 0; i < oldest.length; i++) oldest[i]: i,
      };
  return oldest..sort((a, b) {
    final int byCrew = a.crew.compareTo(b.crew);
    return byCrew != 0 ? byCrew : rank[a]!.compareTo(rank[b]!);
  });
}

/// What one PDF covers: one crew's PM (or every crew's), or all CM.
class MaintenanceReport {
  MaintenanceReport({
    required this.kind,
    required this.today,
    this.crew,
    List<PreventiveMaintenanceWorkOrder> pm =
        const <PreventiveMaintenanceWorkOrder>[],
    List<CorrectiveMaintenanceWorkOrder> cm =
        const <CorrectiveMaintenanceWorkOrder>[],
    this.dataUpdatedAt,
  }) : pm = kind == MaintenanceReportKind.pm
           ? _byCrewThenOldest(
               pm.where((item) => crew == null || item.crew == crew),
             )
           : const <PreventiveMaintenanceWorkOrder>[],
       // The newest Plan Start Date of the whole PM export, so every crew's
       // PDF names the same period.
       planEnd = pm
           .map((PreventiveMaintenanceWorkOrder item) => item.plannedStartOn)
           .whereType<DateTime>()
           .fold<DateTime?>(
             null,
             (DateTime? latest, DateTime date) =>
                 latest == null || date.isAfter(latest) ? date : latest,
           ),
       cm = kind == MaintenanceReportKind.cm
           ? _oldestFirst(
               cm,
               (CorrectiveMaintenanceWorkOrder item) => item.raisedOn,
             )
           : const <CorrectiveMaintenanceWorkOrder>[];

  final MaintenanceReportKind kind;

  /// Latest Plan Start Date in the uploaded PM data.
  final DateTime? planEnd;

  /// A, B, or C for a PM report; null for all crews.
  final String? crew;
  final List<PreventiveMaintenanceWorkOrder> pm;
  final List<CorrectiveMaintenanceWorkOrder> cm;
  final DateTime today;

  /// When the PM & CM spreadsheets last changed.
  final DateTime? dataUpdatedAt;

  String get crewLabel => crew == null ? 'All Crew' : 'Crew $crew';

  /// "PM Outstanding · Crew A" or "CM Outstanding · CPP & PORT" (owner's
  /// wording, 2026-09-25).
  String get title => kind == MaintenanceReportKind.pm
      ? 'PM Outstanding · $crewLabel'
      : 'CM Outstanding · CPP & PORT';

  /// "01 - 24 September 2026": from the first of the month up to the latest
  /// Plan Start Date (PM), or the day the CM data was updated.
  String get periodLabel {
    if (kind == MaintenanceReportKind.cm) {
      return 'per ${DateFormat('d MMMM yyyy', 'id_ID').format((dataUpdatedAt ?? today).toLocal())}';
    }
    final DateTime end = planEnd ?? today;
    return '01 - ${DateFormat('dd MMMM yyyy', 'id_ID').format(end)}';
  }

  String get fileName {
    final String date = DateFormat('dd-MM-yyyy').format(today);
    return kind == MaintenanceReportKind.pm
        ? 'PM Outstanding $crewLabel $date.pdf'
        : 'CM Outstanding CPP PORT $date.pdf';
  }

  List<PreventiveMaintenanceWorkOrder> pmAt(String site, [String? crewCode]) =>
      pm
          .where(
            (item) =>
                item.site == site &&
                (crewCode == null || item.crew == crewCode),
          )
          .toList(growable: false);

  List<CorrectiveMaintenanceWorkOrder> cmAt(String site) =>
      cm.where((item) => item.site == site).toList(growable: false);
}

// PDF ---------------------------------------------------------------------------

final PdfColor _green = PdfColor.fromHex('#176B4D');
final PdfColor _greenDark = PdfColor.fromHex('#0B3D2E');
final PdfColor _orange = PdfColor.fromHex('#E8833B');
final PdfColor _muted = PdfColor.fromHex('#6D7A73');
final PdfColor _line = PdfColor.fromHex('#DCE7E0');
final PdfColor _mint = PdfColor.fromHex('#E7F3ED');
final PdfColor _danger = PdfColor.fromHex('#D85B52');

String _date(DateTime? value) =>
    value == null ? '-' : DateFormat('d MMM yyyy', 'id_ID').format(value);

/// A PM report (one crew's work at CPP and PORT, with the per-crew chart)
/// or a CM report (CPP and PORT with the latest progress). Lists are oldest
/// first.
Future<Uint8List> buildMaintenancePdf(
  MaintenanceReport report, {
  required pw.ThemeData theme,
}) async {
  final pw.Document document = pw.Document(theme: theme, title: report.title);
  final DateFormat stamp = DateFormat('d/M/yy HH.mm');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
      header: (pw.Context context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                report.title,
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ),
      footer: (pw.Context context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'SICATAT · dicetak ${stamp.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 7, color: _muted),
          ),
          pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.Text(
          report.title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _greenDark,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'CPP & PORT Asam-Asam · ${report.periodLabel}',
          style: pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.SizedBox(height: 10),
        _summaryRow(report),
        if (report.kind == MaintenanceReportKind.pm) ...<pw.Widget>[
          pw.SizedBox(height: 10),
          _pmChart(report),
          for (final String site in maintenanceSites)
            ..._pmSection(report, site),
        ] else
          for (final String site in maintenanceSites)
            ..._cmSection(report, site),
      ],
    ),
  );
  return document.save();
}

pw.Widget _summaryRow(MaintenanceReport report) {
  pw.Widget box(String label, int value, PdfColor color) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _mint,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Text(
            '$value',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
  final bool pm = report.kind == MaintenanceReportKind.pm;
  return pw.Row(
    children: <pw.Widget>[
      for (final String site in maintenanceSites) ...<pw.Widget>[
        if (site != maintenanceSites.first) pw.SizedBox(width: 8),
        box(
          '${pm ? 'PM' : 'CM'} $site',
          pm ? report.pmAt(site).length : report.cmAt(site).length,
          pm ? _green : _orange,
        ),
      ],
    ],
  );
}

/// Grouped bars drawn with plain boxes: one group per label, one bar per
/// series, value printed above each bar.
pw.Widget _barChart({
  required String title,
  required List<String> groups,
  required List<(String, PdfColor, List<int>)> series,

  /// Colour per group for a single-series chart.
  List<PdfColor>? groupColors,
  List<(String, PdfColor)>? legend,
}) {
  const double chartHeight = 92;
  final int maxValue = series
      .expand(((String, PdfColor, List<int>) s) => s.$3)
      .fold(0, (int a, int b) => a > b ? a : b);
  final double scale = maxValue == 0 ? 0 : chartHeight / maxValue;
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          title,
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: <pw.Widget>[
            for (final (String name, PdfColor color)
                in legend ??
                    <(String, PdfColor)>[
                      for (final (String n, PdfColor c, List<int> _) in series)
                        (n, c),
                    ]) ...<pw.Widget>[
              pw.Container(width: 7, height: 7, color: color),
              pw.SizedBox(width: 3),
              pw.Text(name, style: const pw.TextStyle(fontSize: 7.5)),
              pw.SizedBox(width: 10),
            ],
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            for (int g = 0; g < groups.length; g++)
              pw.Expanded(
                child: pw.Column(
                  children: <pw.Widget>[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: <pw.Widget>[
                        for (final (String _, PdfColor color, List<int> values)
                            in series)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 1.5,
                            ),
                            child: pw.Column(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: <pw.Widget>[
                                pw.Text(
                                  '${values[g]}',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                                pw.Container(
                                  width: 16,
                                  height: values[g] * scale,
                                  color: groupColors?[g] ?? color,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    pw.Container(height: 0.6, color: _line),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      groups[g],
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _pmChart(MaintenanceReport report) {
  final List<String> crews = report.crew == null
      ? maintenanceCrews
      : <String>[report.crew!];
  // One labelled bar per crew and site: Crew A CPP, Crew A PORT, ...
  return _barChart(
    title: 'PM Outstanding per crew',
    groups: <String>[
      for (final String crew in crews)
        for (final String site in maintenanceSites) 'Crew $crew\n$site',
    ],
    series: <(String, PdfColor, List<int>)>[
      (
        'PM',
        _green,
        <int>[
          for (final String crew in crews)
            for (final String site in maintenanceSites)
              report.pmAt(site, crew).length,
        ],
      ),
    ],
    groupColors: <PdfColor>[
      for (final String _ in crews) ...<PdfColor>[_green, _orange],
    ],
    legend: <(String, PdfColor)>[('CPP', _green), ('PORT', _orange)],
  );
}

pw.Widget _sectionTitle(String text, int count) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
  child: pw.Text(
    '$text ($count)',
    style: pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
      color: _greenDark,
    ),
  ),
);

pw.Widget _table({
  required List<String> headers,
  required Map<int, pw.TableColumnWidth> widths,
  required List<List<String>> rows,
  Set<int> ageColumns = const <int>{},

  /// Columns centred in both the header and the cells; the rest are left.
  Set<int> centered = const <int>{},
}) => pw.TableHelper.fromTextArray(
  headers: headers,
  data: rows,
  columnWidths: widths,
  headerStyle: const pw.TextStyle(
    fontSize: 7.5,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  ),
  headerDecoration: pw.BoxDecoration(color: _green),
  cellStyle: const pw.TextStyle(fontSize: 7.5),
  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  oddRowDecoration: pw.BoxDecoration(color: _mint),
  border: pw.TableBorder(
    horizontalInside: pw.BorderSide(color: _line, width: 0.5),
  ),
  headerAlignments: <int, pw.Alignment>{
    for (int column = 0; column < headers.length; column++)
      column: centered.contains(column)
          ? pw.Alignment.center
          : pw.Alignment.centerLeft,
  },
  cellAlignments: <int, pw.Alignment>{
    for (int column = 0; column < headers.length; column++)
      column: centered.contains(column)
          ? pw.Alignment.center
          : pw.Alignment.centerLeft,
  },
  textStyleBuilder: (int column, dynamic value, int row) {
    // Work waiting more than 30 days stands out in red.
    if (row > 0 && ageColumns.contains(column)) {
      final int? days = int.tryParse('$value');
      if (days != null && days > 30) {
        return pw.TextStyle(
          fontSize: 7.5,
          color: _danger,
          fontWeight: pw.FontWeight.bold,
        );
      }
    }
    return null;
  },
);

List<pw.Widget> _pmSection(MaintenanceReport report, String site) {
  final List<PreventiveMaintenanceWorkOrder> items = report.pmAt(site);
  final String who = report.crewLabel;
  if (items.isEmpty) {
    return <pw.Widget>[
      if (site != maintenanceSites.first) pw.NewPage(),
      _sectionTitle('PM $site · $who', 0),
      pw.Text(
        'Tidak ada PM outstanding.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
    ];
  }
  return <pw.Widget>[
    // PORT starts on a fresh page instead of under the CPP list.
    if (site != maintenanceSites.first) pw.NewPage(),
    _sectionTitle('PM $site · $who', items.length),
    _table(
      headers: <String>[
        'No',
        if (report.crew == null) 'Crew',
        'Work order',
        'Pekerjaan',
        'Aset',
        'Dibuat',
        'Rencana mulai',
        'Umur (hari)',
      ],
      widths: report.crew == null
          ? const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(22),
              1: pw.FixedColumnWidth(30),
              2: pw.FixedColumnWidth(62),
              3: pw.FlexColumnWidth(),
              4: pw.FixedColumnWidth(90),
              5: pw.FixedColumnWidth(58),
              6: pw.FixedColumnWidth(62),
              7: pw.FixedColumnWidth(44),
            }
          : const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(22),
              1: pw.FixedColumnWidth(62),
              2: pw.FlexColumnWidth(),
              3: pw.FixedColumnWidth(90),
              4: pw.FixedColumnWidth(58),
              5: pw.FixedColumnWidth(62),
              6: pw.FixedColumnWidth(44),
            },
      ageColumns: <int>{report.crew == null ? 7 : 6},
      centered: report.crew == null
          ? const <int>{0, 1, 4, 5, 6, 7}
          : const <int>{0, 3, 4, 5, 6},
      rows: <List<String>>[
        for (int i = 0; i < items.length; i++)
          <String>[
            '${i + 1}',
            if (report.crew == null) items[i].crew,
            items[i].workOrder,
            items[i].description,
            items[i].equipmentReference,
            _date(items[i].raisedOn),
            _date(items[i].plannedStartOn),
            '${maintenanceAgeDays(items[i].raisedOn, report.today) ?? '-'}',
          ],
      ],
    ),
  ];
}

List<pw.Widget> _cmSection(MaintenanceReport report, String site) {
  final List<CorrectiveMaintenanceWorkOrder> items = report.cmAt(site);
  if (items.isEmpty) {
    return <pw.Widget>[
      if (site != maintenanceSites.first) pw.NewPage(),
      _sectionTitle('CM $site', 0),
      pw.Text(
        'Tidak ada CM outstanding.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
    ];
  }
  return <pw.Widget>[
    if (site != maintenanceSites.first) pw.NewPage(),
    _sectionTitle('CM $site', items.length),
    _table(
      headers: const <String>[
        'No',
        'Work order',
        'Pekerjaan',
        'Aset',
        'Prioritas',
        'Dibuat',
        'Umur (hari)',
        'Progress terakhir',
      ],
      widths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(22),
        1: pw.FixedColumnWidth(58),
        2: pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(80),
        4: pw.FixedColumnWidth(42),
        5: pw.FixedColumnWidth(58),
        6: pw.FixedColumnWidth(44),
        7: pw.FlexColumnWidth(4),
      },
      ageColumns: const <int>{6},
      centered: const <int>{0, 3, 4, 5, 6},
      rows: <List<String>>[
        for (int i = 0; i < items.length; i++)
          <String>[
            '${i + 1}',
            items[i].workOrder,
            items[i].description,
            items[i].equipmentReference,
            items[i].priority ?? '-',
            _date(items[i].raisedOn),
            '${maintenanceAgeDays(items[i].raisedOn, report.today) ?? '-'}',
            items[i].progress ?? '-',
          ],
      ],
    ),
  ];
}
