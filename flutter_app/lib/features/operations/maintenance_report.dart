import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/preventive_maintenance_models.dart';

/// Crews and sites of the PM & CM report. Crew A/B/C each work at both CPP
/// and PORT, so one foreman gets both sites of their crew.
const List<String> maintenanceCrews = <String>['A', 'B', 'C'];
const List<String> maintenanceSites = <String>['CPP', 'PORT'];

/// Age groups (days since the work order was raised) for the charts.
class MaintenanceAgeBucket {
  const MaintenanceAgeBucket(this.label, this.maxDays);

  final String label;

  /// Upper bound in days, inclusive; null for the open-ended last group.
  final int? maxDays;
}

const List<MaintenanceAgeBucket> maintenanceAgeBuckets = <MaintenanceAgeBucket>[
  MaintenanceAgeBucket('0–7 hari', 7),
  MaintenanceAgeBucket('8–14 hari', 14),
  MaintenanceAgeBucket('15–30 hari', 30),
  MaintenanceAgeBucket('> 30 hari', null),
];

/// Days since [raisedOn], or null when the sheet has no raise date.
int? maintenanceAgeDays(DateTime? raisedOn, DateTime today) {
  if (raisedOn == null) return null;
  final DateTime day = DateTime(today.year, today.month, today.day);
  final DateTime raised = DateTime(raisedOn.year, raisedOn.month, raisedOn.day);
  final int days = day.difference(raised).inDays;
  return days < 0 ? 0 : days;
}

/// Index into [maintenanceAgeBuckets], or null without a raise date.
int? maintenanceAgeBucket(DateTime? raisedOn, DateTime today) {
  final int? days = maintenanceAgeDays(raisedOn, today);
  if (days == null) return null;
  for (int i = 0; i < maintenanceAgeBuckets.length; i++) {
    final int? max = maintenanceAgeBuckets[i].maxDays;
    if (max == null || days <= max) return i;
  }
  return maintenanceAgeBuckets.length - 1;
}

/// Counts per age group.
List<int> maintenanceAgeCounts(
  Iterable<DateTime?> raisedDates,
  DateTime today,
) {
  final List<int> counts = List<int>.filled(maintenanceAgeBuckets.length, 0);
  for (final DateTime? raised in raisedDates) {
    final int? bucket = maintenanceAgeBucket(raised, today);
    if (bucket != null) counts[bucket]++;
  }
  return counts;
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

/// What one PDF covers: one crew (for its foreman) or every crew.
class MaintenanceReport {
  MaintenanceReport({
    required this.crew,
    required List<PreventiveMaintenanceWorkOrder> pm,
    required List<CorrectiveMaintenanceWorkOrder> cm,
    required this.today,
    this.dataUpdatedAt,
  }) : pm = _oldestFirst(
         pm.where((item) => crew == null || item.crew == crew),
         (PreventiveMaintenanceWorkOrder item) => item.raisedOn,
       ),
       cm = _oldestFirst(
         cm,
         (CorrectiveMaintenanceWorkOrder item) => item.raisedOn,
       );

  /// A, B, or C; null for all crews.
  final String? crew;
  final List<PreventiveMaintenanceWorkOrder> pm;
  final List<CorrectiveMaintenanceWorkOrder> cm;
  final DateTime today;

  /// When the PM & CM spreadsheets last changed.
  final DateTime? dataUpdatedAt;

  String get crewLabel => crew == null ? 'Semua crew' : 'Crew $crew';

  String get fileName =>
      'PM CM Tertunda $crewLabel ${DateFormat('dd-MM-yyyy').format(today)}.pdf';

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

/// The PM & CM report a foreman receives: summary, charts, and the full
/// lists (oldest first) with the latest CM progress.
Future<Uint8List> buildMaintenancePdf(
  MaintenanceReport report, {
  required pw.ThemeData theme,
}) async {
  final pw.Document document = pw.Document(
    theme: theme,
    title: 'PM & CM Tertunda ${report.crewLabel}',
  );
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
                'PM & CM Tertunda · ${report.crewLabel}',
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
          'PM & CM TERTUNDA · ${report.crewLabel.toUpperCase()}',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _greenDark,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'CPP & PORT Asam-Asam · data spreadsheet per '
          '${report.dataUpdatedAt == null ? '-' : stamp.format(report.dataUpdatedAt!.toLocal())}'
          ' · umur dihitung sampai ${_date(report.today)}',
          style: pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.SizedBox(height: 10),
        _summaryRow(report),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(child: _pmChart(report)),
            pw.SizedBox(width: 14),
            pw.Expanded(child: _ageChart(report)),
          ],
        ),
        for (final String site in maintenanceSites) ..._pmSection(report, site),
        for (final String site in maintenanceSites) ..._cmSection(report, site),
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
  return pw.Row(
    children: <pw.Widget>[
      box('PM CPP', report.pmAt('CPP').length, _green),
      pw.SizedBox(width: 8),
      box('PM PORT', report.pmAt('PORT').length, _green),
      pw.SizedBox(width: 8),
      box('CM CPP', report.cmAt('CPP').length, _orange),
      pw.SizedBox(width: 8),
      box('CM PORT', report.cmAt('PORT').length, _orange),
    ],
  );
}

/// Grouped bars drawn with plain boxes: one group per label, one bar per
/// series, value printed above each bar.
pw.Widget _barChart({
  required String title,
  required List<String> groups,
  required List<(String, PdfColor, List<int>)> series,
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
          style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: <pw.Widget>[
            for (final (String name, PdfColor color, List<int> _)
                in series) ...<pw.Widget>[
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
                                  color: color,
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
  return _barChart(
    title: 'PM tertunda per crew',
    groups: <String>[for (final String crew in crews) 'Crew $crew'],
    series: <(String, PdfColor, List<int>)>[
      (
        'CPP',
        _green,
        <int>[for (final String crew in crews) report.pmAt('CPP', crew).length],
      ),
      (
        'PORT',
        _orange,
        <int>[
          for (final String crew in crews) report.pmAt('PORT', crew).length,
        ],
      ),
    ],
  );
}

pw.Widget _ageChart(MaintenanceReport report) => _barChart(
  title: 'Umur pekerjaan sejak dibuat',
  groups: <String>[
    for (final MaintenanceAgeBucket bucket in maintenanceAgeBuckets)
      bucket.label,
  ],
  series: <(String, PdfColor, List<int>)>[
    (
      'PM',
      _green,
      maintenanceAgeCounts(
        report.pm.map((PreventiveMaintenanceWorkOrder item) => item.raisedOn),
        report.today,
      ),
    ),
    (
      'CM',
      _orange,
      maintenanceAgeCounts(
        report.cm.map((CorrectiveMaintenanceWorkOrder item) => item.raisedOn),
        report.today,
      ),
    ),
  ],
);

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
  cellAlignments: <int, pw.Alignment>{
    0: pw.Alignment.centerRight,
    for (final int column in ageColumns) column: pw.Alignment.centerRight,
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
  final String who = report.crew == null ? 'semua crew' : report.crewLabel;
  if (items.isEmpty) {
    return <pw.Widget>[
      _sectionTitle('PM $site · $who', 0),
      pw.Text(
        'Tidak ada PM tertunda.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
    ];
  }
  return <pw.Widget>[
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
      _sectionTitle('CM $site', 0),
      pw.Text(
        'Tidak ada CM tertunda.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
    ];
  }
  return <pw.Widget>[
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
