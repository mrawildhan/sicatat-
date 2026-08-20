import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/reports/report_export_service.dart';
import '../../../core/widgets/app_navigation.dart';

class SheetExportScreen extends StatefulWidget {
  const SheetExportScreen({required this.sheetId, super.key});
  final String? sheetId;
  @override
  State<SheetExportScreen> createState() => _SheetExportScreenState();
}

class _SheetExportScreenState extends State<SheetExportScreen> {
  bool _loading = false;
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<ReportExportResult?> _load() async {
    final String? sheetId = widget.sheetId;
    if (sheetId == null || sheetId.isEmpty) {
      _message('Sheet ID is missing.');
      return null;
    }
    setState(() => _loading = true);
    try {
      final ReportExportResult result = await ReportExportService(
        Supabase.instance.client,
      ).load(sheetId: sheetId);
      if (result.rows.isEmpty) {
        _message('No reading data is available for this sheet.');
        return null;
      }
      return result;
    } on Object catch (error) {
      if (mounted) _message('Unable to prepare export: $error');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pdf() async {
    final ReportExportResult? result = await _load();
    if (result == null) return;
    final ReportRow first = result.rows.first;
    final filledBy = result.rows
        .map((row) => row.recordedBy)
        .where((name) => name.isNotEmpty && name != '—')
        .toSet()
        .join(', ');
    final temperatures = _temperatures(result.rows);
    final attention = temperatures.where((item) => item.value >= 60).toList();
    final warning = temperatures
        .where((item) => item.value >= 60 && item.value < 70)
        .length;
    final critical = temperatures.where((item) => item.value >= 70).length;
    final maxTemperature = temperatures.isEmpty
        ? null
        : temperatures
              .map((item) => item.value)
              .reduce((a, b) => a > b ? a : b);
    final pw.Document pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'SICATAT - Equipment condition record',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          _reportHeader(first, filledBy),
          pw.SizedBox(height: 10),
          pw.Row(
            children: <pw.Widget>[
              _metricCard(
                'Temperature readings',
                '${temperatures.length}',
                PdfColors.blue700,
              ),
              pw.SizedBox(width: 8),
              _metricCard(
                'Highest temperature',
                maxTemperature == null
                    ? '-'
                    : '${maxTemperature.toStringAsFixed(1)}°C',
                maxTemperature == null
                    ? PdfColors.grey600
                    : maxTemperature >= 70
                    ? PdfColors.red700
                    : maxTemperature >= 60
                    ? PdfColors.orange700
                    : PdfColors.green700,
              ),
              pw.SizedBox(width: 8),
              _metricCard('Attention 60-69°C', '$warning', PdfColors.orange700),
              pw.SizedBox(width: 8),
              _metricCard('Critical 70°C+', '$critical', PdfColors.red700),
            ],
          ),
          pw.SizedBox(height: 9),
          _temperatureDistribution(temperatures),
          pw.SizedBox(height: 11),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: _exportTable(
                  'Equipment Readings',
                  'Equipment / field',
                  _equipmentBody(result.rows),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _exportTable(
                  'Gearbox Temperature',
                  'Section / point',
                  _gearboxBody(result.rows),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          _attentionPanel(attention),
        ],
      ),
    );
    final Uint8List bytes = await pdf.save();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SheetPdfPreview(
          bytes: bytes,
          filename: 'sicatat-sheet-${first.date}.pdf',
        ),
      ),
    );
  }

  pw.Widget _reportHeader(ReportRow first, String filledBy) => pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: const pw.BoxDecoration(
      color: PdfColors.green800,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          width: 36,
          height: 36,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            color: PdfColors.green600,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Text(
            'S',
            style: const pw.TextStyle(
              fontSize: 22,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 11),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                'DAILY TEMPERATURE CHECK',
                style: const pw.TextStyle(
                  fontSize: 15,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Equipment Condition Report',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.green100,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            _headerInfo('DATE', first.date),
            _headerInfo('CREW / SHIFT', '${first.team} / ${first.shift}'),
            _headerInfo('FILLED BY', filledBy.isEmpty ? '-' : filledBy),
          ],
        ),
      ],
    ),
  );

  pw.Widget _headerInfo(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: <pw.InlineSpan>[
          pw.TextSpan(
            text: '$label  ',
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: PdfColors.green100,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.white),
          ),
        ],
      ),
    ),
  );

  pw.Widget _metricCard(String label, String value, PdfColor color) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 15,
                  color: color,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

  pw.Widget _temperatureDistribution(List<_TemperatureValue> temperatures) {
    final normal = temperatures.where((item) => item.value < 60).length;
    final warning = temperatures
        .where((item) => item.value >= 60 && item.value < 70)
        .length;
    final critical = temperatures.where((item) => item.value >= 70).length;
    final total = temperatures.isEmpty ? 1 : temperatures.length;
    pw.Widget band(int count, PdfColor color) => pw.Expanded(
      flex: count == 0 ? 1 : count,
      child: pw.Container(
        height: 8,
        color: count == 0 ? PdfColors.grey200 : color,
      ),
    );
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(
            width: 106,
            child: pw.Text(
              'TEMPERATURE DISTRIBUTION',
              style: const pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Row(
              children: <pw.Widget>[
                band(normal, PdfColors.green600),
                band(warning, PdfColors.orange500),
                band(critical, PdfColors.red600),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(
            'Normal $normal',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.green800),
          ),
          pw.SizedBox(width: 7),
          pw.Text(
            '60-69°C $warning',
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: PdfColors.orange800,
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Text(
            '70°C+ $critical',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.red800),
          ),
          pw.SizedBox(width: 2),
          pw.Text(
            ' / $total',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _exportTable(
    String title,
    String firstHeader,
    List<List<String>> body,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Text(
        title,
        style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .35),
        columnWidths: <int, pw.TableColumnWidth>{
          0: const pw.FlexColumnWidth(6),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
        },
        children: <pw.TableRow>[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.green700),
            children: <pw.Widget>[
              _tableCell(firstHeader, header: true),
              _tableCell('R1', header: true, center: true),
              _tableCell('R2', header: true, center: true),
            ],
          ),
          ...body.map((row) {
            // Older master data stores units as `C`, while newer templates use
            // `°C`. Treat both as temperatures so 60+ values are always coloured.
            final isTemperature =
                row.first.contains('°C') ||
                RegExp(
                  r'\(\s*C\s*\)',
                  caseSensitive: false,
                ).hasMatch(row.first);
            return pw.TableRow(
              children: <pw.Widget>[
                _tableCell(row[0]),
                _tableCell(row[1], temperature: isTemperature, center: true),
                _tableCell(row[2], temperature: isTemperature, center: true),
              ],
            );
          }),
        ],
      ),
    ],
  );

  pw.Widget _tableCell(
    String value, {
    bool header = false,
    bool temperature = false,
    bool center = false,
  }) {
    final number = double.tryParse(value.replaceAll(',', '.'));
    PdfColor background = PdfColors.white;
    PdfColor foreground = PdfColors.black;
    if (header) {
      background = PdfColors.green700;
      foreground = PdfColors.white;
    } else if (temperature && number != null) {
      if (number >= 70) {
        background = PdfColors.red600;
        foreground = PdfColors.white;
      } else if (number >= 60) {
        background = PdfColors.orange300;
      } else {
        background = PdfColors.green50;
      }
    } else if (value == '—' || value == '-') {
      background = PdfColors.grey100;
      foreground = PdfColors.grey500;
    } else if (value == 'Operating') {
      background = PdfColors.green100;
      foreground = PdfColors.green800;
    }
    return pw.Container(
      color: background,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.2),
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        value == '—' ? '-' : value,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        maxLines: 3,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: header ? 7 : 6.4,
          color: foreground,
          fontWeight: header || (temperature && number != null && number >= 60)
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  List<_TemperatureValue> _temperatures(List<ReportRow> rows) => rows
      .where((row) => row.temperatureCelsius != null)
      .map((row) => _TemperatureValue.fromRow(row))
      .whereType<_TemperatureValue>()
      .toList(growable: false);

  // The summary cards, distribution bar, and colored table cells retain every
  // alert on the same page. A separate chip panel could flow onto an otherwise
  // blank second page when a sheet contains many readings.
  pw.Widget _attentionPanel(List<_TemperatureValue> attention) => pw.SizedBox();

  List<List<String>> _equipmentBody(List<ReportRow> rows) {
    final values = <String, List<String>>{};
    final order = <String>[];
    for (final row in rows.where((row) => row.equipment.isNotEmpty)) {
      final key = '${row.equipment}|${row.point}|${row.unit}';
      final item = values.putIfAbsent(key, () {
        order.add(key);
        return <String>[
          '${row.equipment} - ${row.point}${row.unit.isEmpty ? '' : ' (${row.unit})'}',
          '—',
          '—',
        ];
      });
      if (row.round >= 1 && row.round < item.length) {
        item[row.round] = row.value.isEmpty ? '—' : row.value;
      }
    }
    return order
        .map((key) => values[key]!)
        .where(
          (item) =>
              !(item.first.toLowerCase().contains('remark') &&
                  item[1] == '—' &&
                  item[2] == '—'),
        )
        .toList(growable: false);
  }

  List<List<String>> _gearboxBody(List<ReportRow> rows) {
    const sections = <String>['Gearbox Breaker', 'Gearbox Sizer'];
    const sides = <String>['West', 'East'];
    const points = <String>[
      'Low Speed',
      'Intermediate',
      'High Speed',
      'Input Shaft',
    ];
    final values = <String, List<String>>{};
    for (final row in rows.where(
      (row) => row.equipment.isEmpty && row.side.isNotEmpty,
    )) {
      final key = '${row.section}|${row.side}|${row.point}';
      final item = values.putIfAbsent(key, () => <String>['—', '—']);
      if (row.round >= 1 && row.round <= item.length) {
        item[row.round - 1] = row.value.isEmpty ? '—' : row.value;
      }
    }
    final body = <List<String>>[];
    for (final section in sections) {
      for (final side in sides) {
        final label = '$section - $side';
        final status = values['$section|$side|Status'] ?? <String>['—', '—'];
        body.add(<String>['$label - Status', ...status]);
        for (final point in points) {
          final reading = values['$section|$side|$point'] ?? <String>['—', '—'];
          body.add(<String>['$label - $point (°C)', ...reading]);
        }
      }
    }
    return body;
  }

  Future<void> _csv() async {
    final ReportExportResult? result = await _load();
    if (result == null) return;
    final String date = result.rows.first.date;
    final ReportExportService service = ReportExportService(
      Supabase.instance.client,
    );
    await Share.shareXFiles(<XFile>[
      XFile.fromData(
        utf8.encode(service.toCsv(result)),
        mimeType: 'text/csv',
        name: 'sicatat-sheet-$date.csv',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/sheets',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/sheets'),
        title: const Text('Export this sheet'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Create a PDF or CSV export containing every saved reading in this sheet.',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loading ? null : _pdf,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Create and share PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _csv,
              icon: const Icon(Icons.table_view_rounded),
              label: const Text('Export CSV for Excel'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetPdfPreview extends StatelessWidget {
  const _SheetPdfPreview({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/sheets',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/sheets'),
        title: const Text('PDF preview'),
      ),
      body: PdfPreview(
        build: (PdfPageFormat _) async => bytes,
        initialPageFormat: PdfPageFormat.a4.landscape,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: filename,
      ),
    ),
  );
}

class _TemperatureValue {
  const _TemperatureValue({required this.label, required this.value});

  final String label;
  final double value;

  static _TemperatureValue? fromRow(ReportRow row) {
    final value = row.temperatureCelsius;
    if (value == null) return null;
    final source = row.equipment.isNotEmpty
        ? '${row.equipment} - ${row.point}'
        : '${row.section} ${row.side} - ${row.point}';
    return _TemperatureValue(label: source, value: value);
  }
}
