import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/core/pdf/pdf_theme.dart';
import 'package:sicatat_flutter/data/reports/period_report_pdf.dart';
import 'package:sicatat_flutter/data/reports/report_export_service.dart';
import 'package:sicatat_flutter/data/reports/sheet_export_pdf.dart';
import 'package:sicatat_flutter/features/guide/guide_content.dart';

ByteData _font(String asset) =>
    ByteData.sublistView(File(asset).readAsBytesSync());

final _theme = pdfThemeFromFontBytes(
  regular: _font(appFontRegularAsset),
  bold: _font(appFontBoldAsset),
);

/// Every exported PDF must use the app font only.  PDF standard fonts
/// (Helvetica) looked different from the app and lack glyphs such as "≥".
void _expectAppFontOnly(Uint8List bytes, String name) {
  final String raw = String.fromCharCodes(bytes);
  final Set<String> fonts = RegExp(r'/BaseFont\s*/([A-Za-z0-9+\-_]+)')
      .allMatches(raw)
      .map((m) => m.group(1)!)
      .toSet();
  expect(fonts, isNotEmpty, reason: name);
  for (final String font in fonts) {
    expect(font, contains('Roboto'), reason: '$name uses $font');
  }
  // Set EXPORT_PDF_DIR to keep the files for a visual check.
  final String? dir = Platform.environment['EXPORT_PDF_DIR'];
  if (dir != null) File('$dir/$name').writeAsBytesSync(bytes);
}

ReportRow _row(
  String point,
  String value, {
  String section = 'Pembacaan Peralatan',
}) => ReportRow(
  date: '2026-08-19',
  team: 'Crew A',
  shift: 'Shift Malam',
  section: section,
  round: 1,
  time: '21:23',
  side: 'Barat',
  unitStatus: 'Beroperasi',
  equipment: 'Feeder Breaker',
  point: point,
  value: value,
  unit: '°C',
  recordedBy: 'Fadil',
  sheetStatus: 'submitted',
  isAnomaly: false,
);

void main() {
  test('the sheet export PDF uses the app font', () async {
    final Uint8List bytes = await SheetExportPdf.build(
      ReportExportResult(
        sheetCount: 1,
        rows: <ReportRow>[
          _row('Motor DE', '45'),
          _row('Motor NDE', '62'),
          _row('Gear box', '71'),
          _row('Low Speed', '58', section: 'Gearbox Breaker'),
        ],
      ),
      theme: _theme,
    );
    _expectAppFontOnly(bytes, 'sheet-export.pdf');
  });

  test(
    'the period report PDF uses the app font and readable statuses',
    () async {
      final Uint8List bytes = await PeriodReportPdf.build(
        result: ReportExportResult(
          sheetCount: 1,
          rows: <ReportRow>[_row('Motor DE', '45'), _row('Gear box', '71')],
        ),
        from: DateTime(2026, 8, 15),
        to: DateTime(2026, 9, 23),
        teamName: 'Semua regu',
        theme: _theme,
      );
      _expectAppFontOnly(bytes, 'period-report.pdf');
    },
  );

  test('the guide PDF uses the app font', () async {
    _expectAppFontOnly(await buildGuidePdfBytes(theme: _theme), 'guide.pdf');
  });
}
