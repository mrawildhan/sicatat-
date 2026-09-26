import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/file_download.dart';

const String xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// One column of an exported list: its header and width in characters.
class XlsxColumn {
  const XlsxColumn(this.header, {this.width = 16});

  final String header;
  final double width;
}

/// A plain Excel workbook with one sheet: an optional title line, a bold
/// header row with a filter, frozen below the header. Cells take [String],
/// [num], [DateTime] (written as a real Excel date), [bool] (Ya/Tidak) or
/// null.
///
/// Written by hand (like the Notulen export) so no extra package is needed
/// on the web.
Uint8List buildXlsx({
  required String sheetName,
  required List<XlsxColumn> columns,
  required List<List<Object?>> rows,
  String? title,
}) {
  final StringBuffer data = StringBuffer();
  int rowNo = 0;
  if (title != null) {
    rowNo++;
    data.write('<row r="$rowNo">${_cell(0, rowNo, title, style: 3)}</row>');
  }
  rowNo++;
  final int headerRow = rowNo;
  data.write('<row r="$rowNo">');
  for (int i = 0; i < columns.length; i++) {
    data.write(_cell(i, rowNo, columns[i].header, style: 1));
  }
  data.write('</row>');
  for (final List<Object?> row in rows) {
    rowNo++;
    data.write('<row r="$rowNo">');
    for (int i = 0; i < columns.length && i < row.length; i++) {
      data.write(_cell(i, rowNo, row[i]));
    }
    data.write('</row>');
  }
  final String lastColumn = _column(columns.length - 1);
  final String cols = <String>[
    for (int i = 0; i < columns.length; i++)
      '<col min="${i + 1}" max="${i + 1}" width="${columns[i].width}" customWidth="1"/>',
  ].join();
  final String sheet =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="$headerRow" topLeftCell="A${headerRow + 1}" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>'
      '<cols>$cols</cols>'
      '<sheetData>$data</sheetData>'
      '<autoFilter ref="A$headerRow:$lastColumn${rowNo < headerRow + 1 ? headerRow : rowNo}"/>'
      '</worksheet>';
  final String safeName = _escape(
    sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim(),
  );
  final String name = safeName.length > 31
      ? safeName.substring(0, 31)
      : (safeName.isEmpty ? 'Data' : safeName);
  final Archive archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(
      ArchiveFile.string(
        'xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="$name" sheetId="1" r:id="rId1"/></sheets>'
            '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'
            "'${name.replaceAll("'", "''")}'!\$A\$$headerRow:\$$lastColumn\$${rowNo < headerRow + 1 ? headerRow : rowNo}"
            '</definedName></definedNames>'
            '</workbook>',
      ),
    )
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
    ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Saves [bytes]: a download on the website, the share sheet on Android.
Future<void> saveExportFile(
  Uint8List bytes, {
  required String fileName,
  String mimeType = xlsxMimeType,
}) async {
  if (kIsWeb) {
    downloadFile(bytes: bytes, fileName: fileName, mimeType: mimeType);
    return;
  }
  await Share.shareXFiles(<XFile>[
    XFile.fromData(bytes, mimeType: mimeType, name: fileName),
  ]);
}

String _cell(int column, int row, Object? value, {int style = 0}) {
  final String ref = '${_column(column)}$row';
  final String s = style == 0 ? '' : ' s="$style"';
  return switch (value) {
    null => '',
    num() when value.isFinite => '<c r="$ref"$s><v>$value</v></c>',
    DateTime() => '<c r="$ref" s="2"><v>${_serial(value)}</v></c>',
    bool() => _inline(ref, s, value ? 'Ya' : 'Tidak'),
    _ => _inline(ref, s, value.toString()),
  };
}

String _inline(String ref, String style, String text) =>
    '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">'
    '${_escape(text)}</t></is></c>';

/// Days since 1899-12-30, Excel's date origin.
int _serial(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
).difference(DateTime.utc(1899, 12, 30)).inDays;

String _column(int index) {
  String name = '';
  int n = index + 1;
  while (n > 0) {
    final int rest = (n - 1) % 26;
    name = String.fromCharCode(65 + rest) + name;
    n = (n - 1) ~/ 26;
  }
  return name;
}

String _escape(String value) =>
    const HtmlEscape(HtmlEscapeMode.element)
        .convert(value)
        // Control characters other than tab and line breaks are invalid in XML.
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

const String _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

const String _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

/// Styles: 0 normal, 1 header (bold, green fill, wrapped), 2 date,
/// 3 title (bold, larger).
const String _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts>'
    '<fonts count="3">'
    '<font><sz val="11"/><name val="Aptos"/></font>'
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>'
    '<font><b/><sz val="14"/><name val="Aptos"/></font>'
    '</fonts>'
    '<fills count="3">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF0B3D2E"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="4">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
