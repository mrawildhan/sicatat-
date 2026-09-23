import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/pdf/pdf_fonts.dart';
import 'daily_check_forms.dart';
import 'daily_check_repository.dart';

/// Prints a sheet on its own paper form.
///
/// The page background is the blank form exported from the owner's Excel
/// file (assets/forms/*.png, rendered at 220 dpi from Excel's own PDF
/// export), so logo, fonts, borders, and wording match the paper exactly.
/// Values are written on top at the cell positions measured from that export
/// (points on a US Letter page, the paper size set in both workbooks).
Future<void> printDailyCheckSheet(DailyCheckSheet sheet) async {
  final background = await rootBundle.load(sheet.form.printBackground);
  final bytes = await buildDailyCheckPdf(
    sheet,
    background: background.buffer.asUint8List(),
  );
  final date = DateFormat('yyyy-MM-dd').format(sheet.date);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${sheet.type.storageValue}-$date-${sheet.shiftCode ?? 'shift'}.pdf',
  );
}

Future<Uint8List> buildDailyCheckPdf(
  DailyCheckSheet sheet, {
  required Uint8List background,
}) => buildDailyCheckPdfBatch(<DailyCheckSheet>[sheet], background: background);

/// One page per sheet, all of the same form, e.g. a week of Hydraulic
/// sheets for the archive.
Future<Uint8List> buildDailyCheckPdfBatch(
  List<DailyCheckSheet> sheets, {
  required Uint8List background,
}) async {
  final doc = pw.Document(
    theme: await loadPdfTheme(),
    title: sheets.isEmpty ? 'SICATAT' : sheets.first.form.title,
    author: 'SICATAT',
  );
  final image = pw.MemoryImage(background);
  for (final sheet in sheets) {
    final isHydraulic = sheet.type == DailyCheckFormType.hydraulicFeeder;
    final format = isHydraulic
        ? PdfPageFormat.letter.landscape
        : PdfPageFormat.letter;
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: <pw.Widget>[
            pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
            ...(isHydraulic ? _hydraulic(sheet) : _coalValve(sheet)),
            _statusFooter(sheet, format),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Prints every sheet of [type] from [from] to [to] in one PDF.
Future<void> printDailyCheckSheets(
  DailyCheckFormType type,
  List<DailyCheckSheet> sheets,
  DateTime from,
  DateTime to,
) async {
  final background = await rootBundle.load(type.form.printBackground);
  final bytes = await buildDailyCheckPdfBatch(
    sheets,
    background: background.buffer.asUint8List(),
  );
  final range =
      '${DateFormat('yyyy-MM-dd').format(from)}_${DateFormat('yyyy-MM-dd').format(to)}';
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${type.storageValue}-$range.pdf',
  );
}

// --- shared helpers -------------------------------------------------------

String _number(Object? value) {
  if (value is! num) return '';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

String _dateText(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String _shiftText(DailyCheckSheet sheet) => switch (sheet.shiftCode) {
  'PAGI' => 'Shift Pagi',
  'MALAM' => 'Shift Malam',
  _ => sheet.shiftName ?? '-',
};

/// Free text placed at the left edge of a label such as "Date :".
pw.Widget _label(double left, double top, String text, {double size = 10}) =>
    pw.Positioned(
      left: left,
      top: top,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      ),
    );

/// A value centred in one cell. Temperatures carry the PDF warning colours:
/// orange 60–69 °C, red 70 °C and above (as in the temperature sheet export).
pw.Widget _cell(
  double left,
  double top,
  double right,
  double bottom,
  String text, {
  DailyCheckTemperatureLevel? level,
  PdfColor color = PdfColors.black,
  double size = 9,
}) {
  var fill = PdfColors.white;
  var textColor = color;
  var hasFill = false;
  if (level != null) {
    switch (level) {
      case DailyCheckTemperatureLevel.critical:
        fill = PdfColors.red100;
        textColor = PdfColors.red800;
        hasFill = true;
      case DailyCheckTemperatureLevel.warning:
        fill = PdfColors.orange100;
        textColor = PdfColors.orange800;
        hasFill = true;
      case DailyCheckTemperatureLevel.normal:
        break;
    }
  }
  const inset = 0.9;
  return pw.Positioned(
    left: left + inset,
    top: top + inset,
    child: pw.Container(
      width: right - left - inset * 2,
      height: bottom - top - inset * 2,
      color: hasFill ? fill : null,
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: size,
          color: textColor,
          fontWeight: hasFill ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ),
  );
}

/// One line of small text clipped to a box, used for remarks.
pw.Widget _line(
  double left,
  double top,
  double width,
  double height,
  String text, {
  double size = 7,
}) => pw.Positioned(
  left: left,
  top: top,
  child: pw.SizedBox(
    width: width,
    height: height,
    child: pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(fontSize: size),
      ),
    ),
  ),
);

pw.Widget _statusFooter(DailyCheckSheet sheet, PdfPageFormat format) {
  final status = sheet.isDraft
      ? 'DRAF - belum dikirim'
      : 'Terkirim ${sheet.submittedAt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(sheet.submittedAt!)}'
            '${sheet.submitterName == null ? '' : ' oleh ${sheet.submitterName}'}';
  return pw.Positioned(
    left: 36,
    bottom: 18,
    child: pw.Text(
      'SICATAT - $status',
      style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
    ),
  );
}

String? _recordedTime(Map<String, Object?>? values) {
  final recorded = values?[DailyCheckForm.recordedAtKey];
  final at = recorded is String ? DateTime.tryParse(recorded)?.toLocal() : null;
  return at == null ? null : DateFormat('HH:mm').format(at);
}

List<String> _wrap(String text, int width) {
  final lines = <String>[];
  var current = '';
  for (final word in text.split(' ')) {
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = '  $word';
    }
  }
  if (current.trim().isNotEmpty) lines.add(current);
  return lines;
}

// --- Daily Check Sheet Hydraulic Pump Feeder CPP -------------------------

/// Column edges D..J: Check I F1, F2, Check II F1, F2, Check III F1, F2.
const List<double> _hydraulicColumns = <double>[
  220.0,
  263.0,
  302.7,
  344.1,
  386.0,
  430.1,
  474.3,
];
const double _hydraulicRemarksLeft = 474.3;
const double _hydraulicRemarksRight = 634.9;

/// Row edges of the nine temperature rows (Ambient temp … Heat Exchanger C).
const List<double> _hydraulicTemperatureRows = <double>[
  162.9,
  176.2,
  189.5,
  202.9,
  216.2,
  229.5,
  242.8,
  256.1,
  269.5,
  282.1,
];

/// Row edges of the four pressure rows (Forward, Charge, Case, Vacuum).
const List<double> _hydraulicPressureRows = <double>[
  334.6,
  348.0,
  361.3,
  374.6,
  387.4,
];

List<pw.Widget> _hydraulic(DailyCheckSheet sheet) {
  final form = sheet.form;
  final slots = sheet.slots;
  final widgets = <pw.Widget>[
    _label(69, 90.5, '${_dateText(sheet.date)}  (${_shiftText(sheet)})'),
    _label(68, 108.3, sheet.teamName ?? '-'),
  ];

  final temperatures = form.sections[0].fields;
  final pressures = form.sections[1].fields;
  final speed = form.sections[2].fields.first;

  void fillRows(List<DailyCheckField> fields, List<double> rows) {
    for (var row = 0; row < fields.length; row++) {
      final field = fields[row];
      for (var s = 0; s < slots.length; s++) {
        final values = sheet.readings[slots[s].key];
        for (var u = 0; u < form.units.length; u++) {
          final column = s * form.units.length + u;
          final unit = form.units[u];
          final left = _hydraulicColumns[column];
          final right = _hydraulicColumns[column + 1];
          if (values == null) continue;
          final stopped =
              form.unitStatus(values, unit) != DailyCheckUnitStatus.running;
          if (stopped) {
            widgets.add(
              _cell(
                left,
                rows[row],
                right,
                rows[row + 1],
                '-',
                color: PdfColors.grey700,
              ),
            );
            continue;
          }
          final value = values[DailyCheckForm.valueKey(unit, field)];
          if (value is! num) continue;
          widgets.add(
            _cell(
              left,
              rows[row],
              right,
              rows[row + 1],
              _number(value),
              level: field.kind == DailyCheckValueKind.temperature
                  ? form.levelOf(field, value.toDouble())
                  : null,
            ),
          );
        }
      }
    }
  }

  fillRows(temperatures, _hydraulicTemperatureRows);
  fillRows(pressures, _hydraulicPressureRows);

  // The Remaks/Speed column: feeder speed first, then each check's remark
  // and any stopped feeder with its reason, one line per row.
  const numerals = <String>['I', 'II', 'III'];
  final lines = <String>[];
  final speeds = <String>[];
  for (var s = 0; s < slots.length; s++) {
    final values = sheet.readings[slots[s].key];
    if (values == null) continue;
    final perFeeder = <String>[
      for (final unit in form.units)
        switch (values[DailyCheckForm.valueKey(unit, speed)]) {
          final num v => _number(v),
          _ => '-',
        },
    ];
    if (perFeeder.any((value) => value != '-')) {
      speeds.add('${numerals[s]} ${perFeeder.join('/')}');
    }
  }
  if (speeds.isNotEmpty) lines.add('Speed (F1/F2): ${speeds.join(', ')}');
  for (var s = 0; s < slots.length; s++) {
    final values = sheet.readings[slots[s].key];
    if (values == null) continue;
    final time = _recordedTime(values);
    final prefix = 'Check ${numerals[s]}${time == null ? '' : ' $time'}';
    for (final unit in form.units) {
      final status = form.unitStatus(values, unit);
      if (status == DailyCheckUnitStatus.running) continue;
      final reason = values[DailyCheckForm.reasonKey(unit)];
      lines.add(
        '$prefix ${unit.label} ${status.label.toLowerCase()}'
        '${reason is String ? ': $reason' : ''}',
      );
    }
    if (values[DailyCheckForm.remarksKey] case final String remark) {
      lines.add('$prefix: $remark');
    }
  }
  // About 48 characters of 7pt Helvetica fit one Remaks row; longer entries
  // continue on the next row.
  final wrapped = <String>[for (final line in lines) ..._wrap(line, 48)];
  final remarkRows = <(double, double)>[
    for (var i = 0; i < _hydraulicTemperatureRows.length - 1; i++)
      (_hydraulicTemperatureRows[i], _hydraulicTemperatureRows[i + 1]),
    for (var i = 0; i < _hydraulicPressureRows.length - 1; i++)
      (_hydraulicPressureRows[i], _hydraulicPressureRows[i + 1]),
  ];
  for (var i = 0; i < wrapped.length && i < remarkRows.length; i++) {
    final (top, bottom) = remarkRows[i];
    widgets.add(
      _line(
        _hydraulicRemarksLeft + 3,
        top,
        _hydraulicRemarksRight - _hydraulicRemarksLeft - 6,
        bottom - top,
        wrapped[i],
      ),
    );
  }

  if (sheet.notes case final String notes when notes.isNotEmpty) {
    widgets.add(_line(39, 448, 460, 12, 'Catatan: $notes', size: 8));
  }
  // "Mengetahui, Pengawas/Foreman": the approver's name sits on the
  // signature line, with the approval time above it.
  if (sheet.approvedAt case final approvedAt?) {
    widgets
      ..add(
        _centered(
          522,
          436,
          120,
          'Disetujui ${DateFormat('dd/MM/yyyy HH:mm').format(approvedAt)}',
          size: 6.5,
        ),
      )
      ..add(_centered(522, 449, 120, sheet.approverName ?? '-', bold: true));
  }
  return widgets;
}

/// Text centred in a box of [width] starting at [left].
pw.Widget _centered(
  double left,
  double top,
  double width,
  String text, {
  double size = 9,
  bool bold = false,
}) => pw.Positioned(
  left: left,
  top: top,
  child: pw.SizedBox(
    width: width,
    child: pw.Text(
      text,
      maxLines: 1,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  ),
);

// --- Data Temperature Coal Valve ------------------------------------------

/// Column edges: Waktu | Titik Tembak | RV01 | RV02 | RV03 | RV04.
const List<double> _coalColumns = <double>[
  78.5,
  162.0,
  237.1,
  308.0,
  380.1,
  445.3,
  517.9,
];

/// Row edges of the 16 printed rows (4 time blocks × 4 sides).
const List<double> _coalRows = <double>[
  128.7,
  142.7,
  156.7,
  170.8,
  184.8,
  198.9,
  212.9,
  226.9,
  241.0,
  255.0,
  269.1,
  283.1,
  297.2,
  311.2,
  325.2,
  339.3,
  353.3,
];

List<pw.Widget> _coalValve(DailyCheckSheet sheet) {
  final form = sheet.form;
  final fields = form.fields.toList();
  final widgets = <pw.Widget>[
    _label(172, 71.5, _shiftText(sheet), size: 11),
    _label(172, 86.6, _dateText(sheet.date), size: 11),
  ];
  final remarks = <String>[];
  final slots = sheet.slots;
  for (var s = 0; s < slots.length; s++) {
    final values = sheet.readings[slots[s].key];
    if (values == null) continue;
    final blockTop = _coalRows[s * form.units.length];
    final blockBottom = _coalRows[(s + 1) * form.units.length];
    final time = _recordedTime(values);
    if (time != null) {
      widgets.add(
        _cell(
          _coalColumns[0],
          blockTop,
          _coalColumns[1],
          blockBottom,
          time,
          size: 11,
        ),
      );
    }
    for (var u = 0; u < form.units.length; u++) {
      final unit = form.units[u];
      final row = s * form.units.length + u;
      for (var f = 0; f < fields.length; f++) {
        final value = values[DailyCheckForm.valueKey(unit, fields[f])];
        if (value is! num) continue;
        widgets.add(
          _cell(
            _coalColumns[f + 2],
            _coalRows[row],
            _coalColumns[f + 3],
            _coalRows[row + 1],
            _number(value),
            level: form.levelOf(fields[f], value.toDouble()),
            size: 10,
          ),
        );
      }
    }
    if (values[DailyCheckForm.remarksKey] case final String remark) {
      remarks.add('${time ?? slots[s].label}: $remark');
    }
  }
  // The paper form has no remarks column or signature; notes and the
  // approval go under the table.
  final notes = <String>[
    ...remarks,
    if (sheet.notes case final String text when text.isNotEmpty) text,
  ];
  if (sheet.approvedAt case final approvedAt?) {
    widgets.add(
      _line(
        _coalColumns[0],
        366 + notes.length * 12,
        _coalColumns.last - _coalColumns.first,
        12,
        'Mengetahui: ${sheet.approverName ?? '-'} '
        '(disetujui ${DateFormat('dd/MM/yyyy HH:mm').format(approvedAt)})',
        size: 8,
      ),
    );
  }
  for (var i = 0; i < notes.length; i++) {
    widgets.add(
      _line(
        _coalColumns[0],
        362 + i * 12,
        _coalColumns.last - _coalColumns.first,
        12,
        '${i == 0 ? 'Keterangan: ' : ''}${notes[i]}',
        size: 8,
      ),
    );
  }
  return widgets;
}
