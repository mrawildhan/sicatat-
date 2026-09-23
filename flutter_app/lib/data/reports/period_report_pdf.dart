import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_export_service.dart';

/// The Laporan Periode PDF: every reading in a date range, A4 landscape.
/// Kept outside the screen so tests can build and inspect it.
class PeriodReportPdf {
  const PeriodReportPdf._();

  static Future<Uint8List> build({
    required ReportExportResult result,
    required DateTime from,
    required DateTime to,
    required String teamName,
    required pw.ThemeData theme,
  }) async {
    final pw.Document pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              'LAPORAN SUHU LAPANGAN SICATAT',
              style: const pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              // Count sheets that appear in the rows (empty sheets are skipped).
              // Team is part of the key because older data has two teams on the
              // same date and shift. Rows include unit status lines.
              'Periode: ${_shownDate(from)} s.d. ${_shownDate(to)} - Regu: $teamName - ${result.rows.map((row) => '${row.date}|${row.team}|${row.shift}').toSet().length} lembar berisi data, ${result.rows.length} baris',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[_reportTable(result.rows)],
      ),
    );
    return pdf.save();
  }

  static String _shownDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  /// Database status values, in the words people read on paper.
  static String _sheetStatusLabel(String status) => switch (status) {
    'draft' => 'Draf',
    'submitted' => 'Terkirim',
    'submitted_incomplete' => 'Dikirim tidak lengkap',
    'verified' => 'Terverifikasi',
    _ => status,
  };

  static pw.Widget _reportTable(List<ReportRow> rows) => pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: .35),
    columnWidths: const <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(48),
      1: pw.FixedColumnWidth(68),
      2: pw.FixedColumnWidth(88),
      3: pw.FixedColumnWidth(62),
      4: pw.FlexColumnWidth(1.4),
      5: pw.FixedColumnWidth(62),
      6: pw.FixedColumnWidth(70),
      7: pw.FixedColumnWidth(62),
    },
    children: <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.green700),
        children: <pw.Widget>[
          _reportCell('Tanggal', header: true),
          _reportCell('Regu / shift', header: true),
          _reportCell('Bagian / ronde / jam', header: true),
          _reportCell('Sisi / status', header: true),
          _reportCell('Peralatan / titik ukur', header: true),
          _reportCell('Nilai / peringatan', header: true),
          _reportCell('Dicatat oleh', header: true),
          _reportCell('Status lembar', header: true),
        ],
      ),
      ...rows.map(
        (ReportRow row) => pw.TableRow(
          children: <pw.Widget>[
            _reportCell(shownReportDate(row.date)),
            _reportCell('${row.team}\n${row.shift}'),
            _reportCell('${row.section}\nRonde ${row.round} - ${row.time}'),
            _reportCell('${row.side}\n${row.unitStatus}'),
            _reportCell(
              '${row.equipment.isEmpty ? '' : '${row.equipment} - '}${row.point}',
            ),
            _reportCell(
              '${row.value} ${row.unit}${row.alertLabel.isEmpty ? '' : '\n${row.alertLabel}'}',
              alert: row.alertLabel,
            ),
            _reportCell(row.recordedBy),
            _reportCell(_sheetStatusLabel(row.sheetStatus)),
          ],
        ),
      ),
    ],
  );

  static pw.Widget _reportCell(
    String value, {
    bool header = false,
    String alert = '',
  }) {
    final bool critical = alert.startsWith('KRITIS');
    final bool high = alert.startsWith('TINGGI');
    final bool review = alert.isNotEmpty && !critical && !high;
    final PdfColor background = header
        ? PdfColors.green700
        : critical
        ? PdfColors.red600
        : high
        ? PdfColors.orange300
        : review
        ? PdfColors.amber100
        : PdfColors.white;
    final PdfColor foreground = header || critical
        ? PdfColors.white
        : PdfColors.black;
    return pw.Container(
      color: background,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: header ? 7 : 6,
          color: foreground,
          fontWeight: header || alert.isNotEmpty
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
