import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'daily_check_forms.dart';
import 'daily_check_repository.dart';

/// Opens the print dialog with the sheet laid out like its paper form.
Future<void> printDailyCheckSheet(DailyCheckSheet sheet) async {
  final bytes = await buildDailyCheckPdf(sheet);
  final date = DateFormat('yyyy-MM-dd').format(sheet.date);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: '${sheet.type.storageValue}-$date-${sheet.shiftCode ?? 'shift'}.pdf',
  );
}

Future<Uint8List> buildDailyCheckPdf(DailyCheckSheet sheet) async {
  final doc = pw.Document(title: sheet.form.title, author: 'SICATAT');
  final isHydraulic = sheet.type == DailyCheckFormType.hydraulicFeeder;
  doc.addPage(
    pw.MultiPage(
      pageFormat: isHydraulic ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'SICATAT · printed ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
      build: (context) => <pw.Widget>[
        _header(sheet),
        pw.SizedBox(height: 10),
        if (isHydraulic) ..._hydraulic(sheet) else _coalValve(sheet),
        pw.SizedBox(height: 10),
        ..._footer(sheet, isHydraulic),
      ],
    ),
  );
  return doc.save();
}

const _border = pw.TableBorder(
  left: pw.BorderSide(width: .5),
  right: pw.BorderSide(width: .5),
  top: pw.BorderSide(width: .5),
  bottom: pw.BorderSide(width: .5),
  horizontalInside: pw.BorderSide(width: .5),
  verticalInside: pw.BorderSide(width: .5),
);

const _headFill = PdfColor.fromInt(0xFFE7F3ED);

pw.Widget _header(DailyCheckSheet sheet) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: <pw.Widget>[
    pw.Center(
      child: pw.Text(
        sheet.form.printTitle,
        style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.SizedBox(height: 10),
    _infoLine('Date', DateFormat('dd MMMM yyyy').format(sheet.date)),
    _infoLine('Shift', sheet.shiftLabel),
    _infoLine('Crew', sheet.teamName ?? '-'),
    _infoLine(
      'Status',
      sheet.isDraft
          ? 'Draft'
          : 'Submitted${sheet.submitterName == null ? '' : ' by ${sheet.submitterName}'}',
    ),
  ],
);

pw.Widget _infoLine(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 2),
  child: pw.Row(
    children: <pw.Widget>[
      pw.SizedBox(
        width: 50,
        child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ),
      pw.Text(
        ': $value',
        style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

pw.Widget _cell(
  String text, {
  bool bold = false,
  PdfColor? fill,
  PdfColor? color,
  pw.Alignment align = pw.Alignment.center,
  double size = 8,
}) => pw.Container(
  color: fill,
  alignment: align,
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.6),
  child: pw.Text(
    text,
    textAlign: align == pw.Alignment.center
        ? pw.TextAlign.center
        : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: size,
      color: color,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

String _number(Object? value) {
  if (value is! num) return '';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

/// PDF shows 60–69 °C orange and 70 °C and above red, like the temperature
/// sheet export.
pw.Widget _valueCell(Object? value, DailyCheckField field) {
  final text = _number(value);
  if (value is num && field.kind == DailyCheckValueKind.temperature) {
    return switch (temperatureLevel(value.toDouble())) {
      DailyCheckTemperatureLevel.critical => _cell(
        text,
        bold: true,
        fill: PdfColors.red100,
        color: PdfColors.red800,
      ),
      DailyCheckTemperatureLevel.warning => _cell(
        text,
        bold: true,
        fill: PdfColors.orange100,
        color: PdfColors.orange800,
      ),
      DailyCheckTemperatureLevel.normal => _cell(text),
    };
  }
  return _cell(text);
}

String _slotHeading(DailyCheckSheet sheet, DailyCheckSlot slot) {
  final recorded = sheet.readings[slot.key]?[DailyCheckForm.recordedAtKey];
  final at = recorded is String ? DateTime.tryParse(recorded)?.toLocal() : null;
  final time = at != null ? DateFormat('HH:mm').format(at) : slot.plannedTime;
  return time == null ? slot.label : '${slot.label} ($time)';
}

List<pw.Widget> _hydraulic(DailyCheckSheet sheet) {
  final form = sheet.form;
  final slots = sheet.slots;
  final units = form.units;
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(20),
    1: const pw.FixedColumnWidth(140),
    for (var i = 0; i < slots.length * units.length; i++)
      2 + i: const pw.FixedColumnWidth(52),
    2 + slots.length * units.length: const pw.FlexColumnWidth(),
  };

  String unitStatusText(DailyCheckSlot slot, DailyCheckUnit unit) {
    final values = sheet.readings[slot.key] ?? const <String, Object?>{};
    final status = form.unitStatus(values, unit);
    return status == DailyCheckUnitStatus.running ? '' : status.label;
  }

  pw.TableRow header() => pw.TableRow(
    children: <pw.Widget>[
      _cell('No', bold: true, fill: _headFill),
      _cell(
        'Description',
        bold: true,
        fill: _headFill,
        align: pw.Alignment.centerLeft,
      ),
      for (final slot in slots)
        for (final unit in units)
          _cell(
            '${_slotHeading(sheet, slot)}\n${unit.label}',
            bold: true,
            fill: _headFill,
            size: 7,
          ),
      _cell('Remarks', bold: true, fill: _headFill),
    ],
  );

  pw.TableRow sectionRow(String title) => pw.TableRow(
    children: <pw.Widget>[
      _cell('', fill: PdfColors.grey200),
      _cell(
        title.toUpperCase(),
        bold: true,
        fill: PdfColors.grey200,
        align: pw.Alignment.centerLeft,
      ),
      for (var i = 0; i < slots.length * units.length + 1; i++)
        _cell('', fill: PdfColors.grey200),
    ],
  );

  pw.TableRow fieldRow(DailyCheckField field, int number) => pw.TableRow(
    children: <pw.Widget>[
      _cell('$number'),
      _cell(
        field.unit == null ? field.label : '${field.label} (${field.unit})',
        align: pw.Alignment.centerLeft,
      ),
      for (final slot in slots)
        for (final unit in units)
          unitStatusText(slot, unit).isNotEmpty
              ? _cell('-', color: PdfColors.grey600)
              : _valueCell(
                  sheet.readings[slot.key]?[DailyCheckForm.valueKey(
                    unit,
                    field,
                  )],
                  field,
                ),
      _cell(''),
    ],
  );

  final statusRow = pw.TableRow(
    children: <pw.Widget>[
      _cell(''),
      _cell('Unit status', bold: true, align: pw.Alignment.centerLeft),
      for (final slot in slots)
        for (final unit in units)
          _cell(
            sheet.readings[slot.key] == null
                ? ''
                : unitStatusText(slot, unit).isEmpty
                ? 'Running'
                : unitStatusText(slot, unit),
            size: 7,
          ),
      _cell(''),
    ],
  );

  final remarks = <pw.Widget>[];
  for (final slot in slots) {
    final values = sheet.readings[slot.key] ?? const <String, Object?>{};
    final notes = <String>[
      if (values[DailyCheckForm.remarksKey] case final String text) text,
      for (final unit in units)
        if (values[DailyCheckForm.reasonKey(unit)] case final String reason)
          '${unit.label} ${unitStatusText(slot, unit).toLowerCase()}: $reason',
    ];
    if (notes.isNotEmpty) {
      remarks.add(
        pw.Text(
          '${slot.label}: ${notes.join(' · ')}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      );
    }
  }

  var number = 1;
  final rows = <pw.TableRow>[header(), statusRow];
  for (final section in form.sections) {
    rows.add(sectionRow(section.title));
    for (final field in section.fields) {
      rows.add(fieldRow(field, number++));
    }
  }
  return <pw.Widget>[
    pw.Table(border: _border, columnWidths: widths, children: rows),
    pw.SizedBox(height: 8),
    if (remarks.isNotEmpty) ...<pw.Widget>[
      pw.Text(
        'Remarks',
        style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      ...remarks,
    ],
  ];
}

pw.Widget _coalValve(DailyCheckSheet sheet) {
  final form = sheet.form;
  final fields = form.fields.toList();
  final rows = <pw.TableRow>[
    pw.TableRow(
      children: <pw.Widget>[
        _cell('Time', bold: true, fill: _headFill),
        _cell('Shooting point', bold: true, fill: _headFill),
        for (final field in fields)
          _cell('${field.label} (°C)', bold: true, fill: _headFill),
      ],
    ),
  ];
  for (final slot in sheet.slots) {
    final values = sheet.readings[slot.key];
    final recorded = values?[DailyCheckForm.recordedAtKey];
    final at = recorded is String
        ? DateTime.tryParse(recorded)?.toLocal()
        : null;
    for (var i = 0; i < form.units.length; i++) {
      final unit = form.units[i];
      rows.add(
        pw.TableRow(
          children: <pw.Widget>[
            // The paper form merges the time over four rows; the first row
            // carries it here.
            _cell(
              i == 0
                  ? (at == null ? slot.label : DateFormat('HH:mm').format(at))
                  : '',
              bold: i == 0,
            ),
            _cell(unit.label, align: pw.Alignment.centerLeft),
            for (final field in fields)
              _valueCell(values?[DailyCheckForm.valueKey(unit, field)], field),
          ],
        ),
      );
    }
  }
  final remarks = <pw.Widget>[
    for (final slot in sheet.slots)
      if (sheet.readings[slot.key]?[DailyCheckForm.remarksKey]
          case final String text)
        pw.Text('${slot.label}: $text', style: const pw.TextStyle(fontSize: 8)),
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Table(
        border: _border,
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FixedColumnWidth(70),
          1: pw.FixedColumnWidth(90),
        },
        children: rows,
      ),
      if (remarks.isNotEmpty) ...<pw.Widget>[
        pw.SizedBox(height: 8),
        pw.Text(
          'Remarks',
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        ...remarks,
      ],
    ],
  );
}

List<pw.Widget> _footer(DailyCheckSheet sheet, bool isHydraulic) => <pw.Widget>[
  if (sheet.notes case final String notes when notes.isNotEmpty) ...<pw.Widget>[
    pw.Text('Notes: $notes', style: const pw.TextStyle(fontSize: 8)),
    pw.SizedBox(height: 6),
  ],
  if (isHydraulic) ...<pw.Widget>[
    pw.Text(
      'Note: Fill in the Remarks column if any sign of damage is found on the unit.',
      style: const pw.TextStyle(fontSize: 8),
    ),
    pw.Text(
      'Temperature and pressure are monitored every 4 hours: day shift at 10:00, 14:00 & 18:00; '
      'night shift at 22:00, 02:00 & 06:00.',
      style: const pw.TextStyle(fontSize: 8),
    ),
  ],
  pw.Text(
    'Colour: orange 60-69 °C, red 70 °C and above.',
    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 4),
  pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: <pw.Widget>[
      pw.Column(
        children: <pw.Widget>[
          pw.Text('Acknowledged by,', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 30),
          pw.Container(width: 140, height: .5, color: PdfColors.black),
          pw.SizedBox(height: 2),
          pw.Text(
            'Supervisor / Foreman',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ],
  ),
];
