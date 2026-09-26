import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared look of the SICATAT report PDFs added on 2026-09-26 (follow-up of
/// critical temperatures, check compliance, asset history, monthly report):
/// the same colours, title block, summary boxes and tables as the PM & CM
/// Outstanding PDF.
final PdfColor reportGreen = PdfColor.fromHex('#176B4D');
final PdfColor reportGreenDark = PdfColor.fromHex('#0B3D2E');
final PdfColor reportOrange = PdfColor.fromHex('#E8833B');
final PdfColor reportAmber = PdfColor.fromHex('#F2B84B');
final PdfColor reportMuted = PdfColor.fromHex('#6D7A73');
final PdfColor reportLine = PdfColor.fromHex('#DCE7E0');
final PdfColor reportMint = PdfColor.fromHex('#E7F3ED');
final PdfColor reportDanger = PdfColor.fromHex('#D85B52');

String reportDate(DateTime? value) =>
    value == null ? '-' : DateFormat('d MMM yyyy', 'id_ID').format(value);

String reportDateTime(DateTime? value) => value == null
    ? '-'
    : DateFormat('d MMM yyyy HH.mm', 'id_ID').format(value.toLocal());

/// A multi-page report with the SICATAT footer and, from page 2, the title
/// as a running header.
pw.MultiPage reportPage({
  required String title,
  required List<pw.Widget> Function(pw.Context context) build,
  PdfPageFormat? format,
}) {
  final DateFormat stamp = DateFormat('d/M/yy HH.mm');
  return pw.MultiPage(
    pageFormat: format ?? PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
    header: (pw.Context context) => context.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 8, color: reportMuted),
            ),
          ),
    footer: (pw.Context context) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(
          'SICATAT · dicetak ${stamp.format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 7, color: reportMuted),
        ),
        pw.Text(
          'Halaman ${context.pageNumber} dari ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 7, color: reportMuted),
        ),
      ],
    ),
    build: build,
  );
}

List<pw.Widget> reportHeading(String title, String subtitle) => <pw.Widget>[
  pw.Text(
    title.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 16,
      fontWeight: pw.FontWeight.bold,
      color: reportGreenDark,
    ),
  ),
  pw.SizedBox(height: 2),
  pw.Text(subtitle, style: pw.TextStyle(fontSize: 8.5, color: reportMuted)),
  pw.SizedBox(height: 10),
];

pw.Widget reportSectionTitle(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
  child: pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
      color: reportGreenDark,
    ),
  ),
);

pw.Widget reportNote(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 4),
  child: pw.Text(text, style: pw.TextStyle(fontSize: 7.5, color: reportMuted)),
);

/// One labelled figure of a summary row.
class ReportFigure {
  const ReportFigure(this.label, this.value, {this.color});

  final String label;
  final String value;
  final PdfColor? color;
}

pw.Widget reportFigures(List<ReportFigure> figures) => pw.Row(
  children: <pw.Widget>[
    for (int i = 0; i < figures.length; i++) ...<pw.Widget>[
      if (i > 0) pw.SizedBox(width: 8),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: pw.BoxDecoration(
            color: reportMint,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                figures[i].label,
                style: pw.TextStyle(fontSize: 7.5, color: reportMuted),
              ),
              pw.Text(
                figures[i].value,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: figures[i].color ?? reportGreenDark,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ],
);

/// A striped table. [cellColor] may colour single cells (row index without
/// the header, column index).
pw.Widget reportTable({
  required List<String> headers,
  required List<List<String>> rows,
  Map<int, pw.TableColumnWidth>? widths,
  Set<int> centered = const <int>{},
  Set<int> bold = const <int>{},
  double fontSize = 7.5,
  PdfColor? Function(int row, int column)? cellColor,
}) {
  if (rows.isEmpty) return reportNote('Tidak ada data.');
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    columnWidths: widths,
    headerStyle: pw.TextStyle(
      fontSize: fontSize,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: pw.BoxDecoration(color: reportGreen),
    cellStyle: pw.TextStyle(fontSize: fontSize),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    oddRowDecoration: pw.BoxDecoration(color: reportMint),
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: reportLine, width: 0.5),
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
      final PdfColor? color = row > 0 && cellColor != null
          ? cellColor(row - 1, column)
          : null;
      final bool strong = row > 0 && bold.contains(column);
      if (color == null && !strong) return null;
      return pw.TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: strong || color != null ? pw.FontWeight.bold : null,
      );
    },
  );
}

/// A horizontal bar chart: one labelled bar per entry, scaled to the
/// largest value.
pw.Widget reportBars(
  List<(String label, double value, PdfColor color)> bars, {
  String Function(double value)? format,
  double labelWidth = 90,
}) {
  final double top = bars.fold<double>(
    0,
    (double max, (String, double, PdfColor) bar) => bar.$2 > max ? bar.$2 : max,
  );
  return pw.Column(
    children: <pw.Widget>[
      for (final (String label, double value, PdfColor color) in bars)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: <pw.Widget>[
              pw.SizedBox(
                width: labelWidth,
                child: pw.Text(
                  label,
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (pw.Context context, pw.BoxConstraints? box) {
                    final double width = box?.maxWidth ?? 300;
                    return pw.Row(
                      children: <pw.Widget>[
                        pw.Container(
                          width: top <= 0
                              ? 0
                              : (width - 60) * (value / top).clamp(0, 1),
                          height: 9,
                          color: color,
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          format?.call(value) ?? _plain(value),
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

String _plain(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
