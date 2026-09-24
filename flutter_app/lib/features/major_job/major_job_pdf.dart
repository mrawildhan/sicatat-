import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'major_job_models.dart';

/// Layout agreed with the owner on 2026-09-22/23 (formerly a Python/Word
/// script): every landscape photo is cropped to exactly 5.4 × 3.6 cm and every
/// portrait photo to 2.4 × 3.6 cm, so rows are level and all photos match.
/// Photos are never letterboxed or framed; the centre of the picture is kept.
const double majorJobLandscapeWidthCm = 5.4;
const double majorJobPortraitWidthCm = 2.4;
const double majorJobPhotoHeightCm = 3.6;
const double _photoGap = 0.15 * PdfPageFormat.inch;
const double _noColumn = 0.55 * PdfPageFormat.inch;
const double _photoColumn = 4.75 * PdfPageFormat.inch;
const double _descriptionColumn = 2.2 * PdfPageFormat.inch;
const double _photoArea = 4.45 * PdfPageFormat.inch;
final PdfColor _headerShade = PdfColor.fromHex('#D9D9D9');

enum MajorJobReportKind {
  weekly('WEEKLY JOB REPORT', 'Weekly Job'),
  monthly('MAJOR JOB REPORT', 'Mayor Job');

  const MajorJobReportKind(this.title, this.filePrefix);

  final String title;

  /// Owner's existing file names ("Mayor Job 01 - 31 Agustus 2026.pdf").
  final String filePrefix;
}

class MajorJobReport {
  const MajorJobReport({
    required this.kind,
    required this.start,
    required this.end,
    required this.sections,
    this.area = 'COP',
  });

  final MajorJobReportKind kind;
  final DateTime start;
  final DateTime end;
  final List<MajorJobSection> sections;
  final String area;

  String get rangeLabel => majorJobRangeLabel(start, end);

  String get fileName =>
      '${kind.filePrefix} ${rangeLabel.replaceAll('–', '-')}.pdf';

  Iterable<MajorJob> get jobs =>
      sections.expand((MajorJobSection section) => section.jobs);
}

/// Weekly reports are cumulative over the month's weeks up to [until], so
/// October's start on 29 September ("Weekly Job 29 September – 12 Oktober").
/// Monthly reports follow the calendar month, with the weeks clipped to it,
/// so "Mayor Job 01 – 30 September" includes 29 – 30 September (owner
/// decision 2026-09-24). Jobs without photos are left out, like the old
/// script did.
MajorJobReport majorJobReportFor({
  required MajorJobReportKind kind,
  required int year,
  required int month,
  required List<MajorJob> jobs,
  MajorJobPeriod? until,
}) {
  final List<MajorJob> withPhotos = jobs
      .where((job) => job.photos.isNotEmpty)
      .toList();
  final List<MajorJobPeriod> weeks = majorJobWeeksOfMonth(year, month);
  if (kind == MajorJobReportKind.monthly || until == null || weeks.isEmpty) {
    return MajorJobReport(
      kind: kind,
      start: DateTime(year, month),
      end: DateTime(year, month + 1, 0),
      sections: majorJobCalendarSections(year, month, withPhotos),
    );
  }
  return MajorJobReport(
    kind: kind,
    start: weeks.first.start,
    end: until.end,
    sections: majorJobSections(year, month, withPhotos)
        .where((section) => !section.period.end.isAfter(until.end))
        .toList(),
  );
}

class _PlacedPhoto {
  const _PlacedPhoto(this.photo, this.width, this.height);

  final MajorJobPhoto photo;
  final double width;
  final double height;
}

/// Fills rows left to right while the photos still fit the cell.
List<List<T>> majorJobPhotoRows<T>(
  List<T> items,
  double Function(T item) widthOf, {
  double available = _photoArea,
  double gap = _photoGap,
}) {
  final List<List<T>> rows = <List<T>>[];
  List<T> current = <T>[];
  double used = 0;
  for (final T item in items) {
    final double width = widthOf(item);
    final double needed = current.isEmpty ? width : used + gap + width;
    if (current.isNotEmpty && needed > available) {
      rows.add(current);
      current = <T>[item];
      used = width;
    } else {
      current.add(item);
      used = needed;
    }
  }
  if (current.isNotEmpty) rows.add(current);
  return rows;
}

pw.Widget _photoBox(_PlacedPhoto placed, Uint8List? bytes) {
  if (bytes == null) {
    return pw.Container(
      width: placed.width,
      height: placed.height,
      alignment: pw.Alignment.center,
      color: PdfColors.grey200,
      child: pw.Text('Foto tidak tersedia', style: const pw.TextStyle(fontSize: 7)),
    );
  }
  // DecorationImage clips to the box, so BoxFit.cover crops the centre.
  return pw.Container(
    width: placed.width,
    height: placed.height,
    decoration: pw.BoxDecoration(
      image: pw.DecorationImage(
        image: pw.MemoryImage(bytes),
        fit: pw.BoxFit.cover,
      ),
    ),
  );
}

pw.Widget _photoCell(MajorJob job, Map<String, Uint8List> photos) {
  final List<_PlacedPhoto> placed = <_PlacedPhoto>[
    for (final MajorJobPhoto photo in job.photos)
      _PlacedPhoto(
        photo,
        (photo.isLandscape ? majorJobLandscapeWidthCm : majorJobPortraitWidthCm) *
            PdfPageFormat.cm,
        majorJobPhotoHeightCm * PdfPageFormat.cm,
      ),
  ];
  final List<List<_PlacedPhoto>> rows = majorJobPhotoRows(
    placed,
    (_PlacedPhoto p) => p.width,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(
      horizontal: (_photoColumn - _photoArea) / 2,
      vertical: 5,
    ),
    child: pw.Column(
      children: <pw.Widget>[
        for (int r = 0; r < rows.length; r++) ...<pw.Widget>[
          if (r > 0) pw.SizedBox(height: _photoGap),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: <pw.Widget>[
              for (int i = 0; i < rows[r].length; i++) ...<pw.Widget>[
                if (i > 0) pw.SizedBox(width: _photoGap),
                _photoBox(rows[r][i], photos[rows[r][i].photo.id]),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

pw.Widget _headerCell(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
  child: pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
  ),
);

pw.Widget _table(
  MajorJobSection section,
  int firstNumber,
  Map<String, Uint8List> photos,
) => pw.Table(
  border: pw.TableBorder.all(width: .75),
  columnWidths: const <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(_noColumn),
    1: pw.FixedColumnWidth(_photoColumn),
    2: pw.FixedColumnWidth(_descriptionColumn),
  },
  children: <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _headerShade),
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: <pw.Widget>[
        _headerCell('No'),
        _headerCell('Photo'),
        _headerCell('Job Description'),
      ],
    ),
    for (int i = 0; i < section.jobs.length; i++)
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: <pw.Widget>[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              '${firstNumber + i}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          _photoCell(section.jobs[i], photos),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              section.jobs[i].description,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5),
            ),
          ),
        ],
      ),
  ],
);

/// Builds the report PDF. [photos] maps photo id → bytes; the caller loads
/// them first so this stays synchronous with respect to the network.
Future<Uint8List> buildMajorJobPdf(
  MajorJobReport report, {
  required Map<String, Uint8List> photos,
  required pw.ThemeData theme,
}) async {
  final pw.Document document = pw.Document(
    theme: theme,
    title: report.fileName.replaceAll('.pdf', ''),
    author: 'SICATAT',
  );
  final List<pw.Widget> content = <pw.Widget>[
    pw.Center(
      child: pw.Text(
        report.kind.title,
        style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.SizedBox(height: 3),
    pw.Center(
      child: pw.Text(
        '${report.area}  |  ${report.rangeLabel}',
        style: const pw.TextStyle(fontSize: 12),
      ),
    ),
    pw.SizedBox(height: 6),
    pw.Divider(thickness: 1.5, height: 1.5, color: PdfColors.black),
    pw.SizedBox(height: 12),
  ];
  int number = 1;
  for (int s = 0; s < report.sections.length; s++) {
    final MajorJobSection section = report.sections[s];
    if (s > 0) content.add(pw.NewPage());
    content
      ..add(
        pw.Center(
          child: pw.Text(
            section.period.label,
            style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
      )
      ..add(pw.SizedBox(height: 6))
      ..add(_table(section, number, photos));
    number += section.jobs.length;
  }
  if (report.sections.isEmpty) {
    content.add(
      pw.Center(child: pw.Text('Belum ada pekerjaan berfoto pada periode ini.')),
    );
  }
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter.copyWith(
        marginLeft: .5 * PdfPageFormat.inch,
        marginRight: .5 * PdfPageFormat.inch,
        marginTop: .6 * PdfPageFormat.inch,
        marginBottom: .6 * PdfPageFormat.inch,
      ),
      build: (_) => content,
    ),
  );
  return document.save();
}
