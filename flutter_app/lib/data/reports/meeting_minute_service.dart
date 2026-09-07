import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meeting_minute_models.dart';
import '../models/sicatat_types.dart';

class MeetingMinuteService {
  MeetingMinuteService(this._client);

  final SupabaseClient _client;
  static const String _select =
      'id,title,meeting_date,start_time,end_time,location,attendees,apologies,minute_taker,distribution_list,new_business_agenda,proposed_by,note,status,created_by,updated_at,meeting_minute_action(id,item_date,subject_discussion,assigned_to,due_date,position)';

  Future<List<MeetingMinute>> loadAll() async {
    final Object response = await _client
        .from('meeting_minute')
        .select(_select)
        .order('updated_at', ascending: false);
    if (response is! List) {
      throw const FormatException('Data notulen yang diterima tidak valid.');
    }
    return response
        .map(
          (Object? row) => MeetingMinute.fromJson(
            requireJsonMap(row, source: 'meeting minute'),
          ),
        )
        .toList(growable: false);
  }

  Future<MeetingMinute> loadOne(String id) async {
    final Object response = await _client
        .from('meeting_minute')
        .select(_select)
        .eq('id', id)
        .single();
    return MeetingMinute.fromJson(
      requireJsonMap(response, source: 'meeting minute'),
    );
  }

  Future<MeetingMinute> save({
    required String? id,
    required String actorId,
    required String title,
    required DateTime? meetingDate,
    required String? startTime,
    required String? endTime,
    required String location,
    required String attendees,
    required String apologies,
    required String minuteTaker,
    required String distributionList,
    required String newBusinessAgenda,
    required String proposedBy,
    required String note,
    required MeetingMinuteStatus status,
    required List<MeetingMinuteAction> actions,
  }) async {
    final Map<String, Object?> values = <String, Object?>{
      'title': title.trim(),
      'meeting_date': _dateText(meetingDate),
      'start_time': _timeText(startTime),
      'end_time': _timeText(endTime),
      'location': location.trim(),
      'attendees': attendees.trim(),
      'apologies': apologies.trim(),
      'minute_taker': minuteTaker.trim(),
      'distribution_list': distributionList.trim(),
      'new_business_agenda': newBusinessAgenda.trim(),
      'proposed_by': proposedBy.trim(),
      'note': note.trim(),
      'status': status.storageValue,
    };
    final String meetingId;
    if (id == null) {
      values['created_by'] = actorId;
      final Object response = await _client
          .from('meeting_minute')
          .insert(values)
          .select('id')
          .single();
      meetingId = requireJsonMap(
        response,
        source: 'meeting minute',
      ).requiredString('id');
    } else {
      await _client.from('meeting_minute').update(values).eq('id', id);
      meetingId = id;
    }
    await _client
        .from('meeting_minute_action')
        .delete()
        .eq('meeting_minute_id', meetingId);
    final List<MeetingMinuteAction> meaningful = actions
        .where(
          (MeetingMinuteAction action) =>
              action.subjectDiscussion.trim().isNotEmpty ||
              action.assignedTo.trim().isNotEmpty ||
              action.itemDate != null ||
              action.dueDate != null,
        )
        .toList(growable: false);
    if (meaningful.isNotEmpty) {
      await _client.from('meeting_minute_action').insert(<Map<String, Object?>>[
        for (int index = 0; index < meaningful.length; index++)
          meaningful[index].toJson(meetingMinuteId: meetingId)
            ..['position'] = index,
      ]);
    }
    return loadOne(meetingId);
  }

  Future<void> delete(String id) =>
      _client.from('meeting_minute').delete().eq('id', id);

  static String? _dateText(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String? _timeText(String? value) {
    final String normalized = (value ?? '').trim();
    if (normalized.isEmpty) return null;
    return normalized.length == 5 ? '$normalized:00' : normalized;
  }
}

class MeetingMinuteExcelService {
  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  List<int> create(MeetingMinute minute) {
    final List<MeetingMinuteAction> actions = minute.actions.isEmpty
        ? <MeetingMinuteAction>[const MeetingMinuteAction()]
        : (List<MeetingMinuteAction>.of(minute.actions)
            ..sort((a, b) => a.position.compareTo(b.position)));
    final _XlsxSheet sheet = _XlsxSheet();
    sheet.merge(
      'A1:D1',
      minute.title.isEmpty ? 'NOTULEN RAPAT' : minute.title,
      1,
      30,
    );
    sheet.metadata(3, 'Tanggal & waktu', _meetingTime(minute));
    sheet.metadata(4, 'Lokasi', minute.location);
    sheet.metadata(5, 'Peserta', minute.attendees);
    sheet.metadata(6, 'Berhalangan hadir', minute.apologies);
    sheet.metadata(7, 'Pencatat notulen', minute.minuteTaker);
    sheet.metadata(8, 'Distribusi', minute.distributionList);
    sheet.metadata(9, 'Agenda baru', minute.newBusinessAgenda);
    sheet.metadata(10, 'Diajukan oleh', minute.proposedBy);
    sheet.merge('A12:D12', 'TINDAK LANJUT RAPAT', 4, 22);
    const List<String> headers = <String>[
      'ITEM [DD.MM.YY]',
      'PEMBAHASAN',
      'PENANGGUNG JAWAB',
      'TENGGAT',
    ];
    for (int column = 0; column < headers.length; column++) {
      sheet.cell(column, 13, headers[column], 5);
    }
    for (int index = 0; index < actions.length; index++) {
      final MeetingMinuteAction action = actions[index];
      final int row = 14 + index;
      sheet.cell(0, row, _date(action.itemDate), 6, height: 52);
      sheet.cell(1, row, action.subjectDiscussion, 6, height: 52);
      sheet.cell(2, row, action.assignedTo, 6, height: 52);
      sheet.cell(3, row, _date(action.dueDate), 6, height: 52);
    }
    final int noteRow = 16 + actions.length;
    sheet.merge(
      'A$noteRow:D$noteRow',
      minute.note.trim().isEmpty
          ? 'CATATAN: —'
          : 'CATATAN: ${minute.note.trim()}',
      3,
      42,
    );
    final Archive archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRelationships))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook))
      ..addFile(
        ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRelations),
      )
      ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.xml));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _meetingTime(MeetingMinute minute) {
    final String date = _date(minute.meetingDate, format: 'd MMMM y');
    final String start = _clock(minute.startTime);
    final String end = _clock(minute.endTime);
    final String range = start.isEmpty
        ? end
        : end.isEmpty
        ? start
        : '$start–$end';
    if (date.isEmpty) return range.isEmpty ? '' : '$range WITA';
    return range.isEmpty ? date : '$date, $range WITA';
  }

  static String _date(DateTime? value, {String format = 'dd.MM.yy'}) {
    if (value == null) return '';
    if (format == 'd MMMM y') {
      const List<String> months = <String>[
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember',
      ];
      return '${value.day} ${months[value.month - 1]} ${value.year}';
    }
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${(value.year % 100).toString().padLeft(2, '0')}';
  }

  static String _clock(String? value) {
    final String raw = (value ?? '').trim();
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  static const String _contentTypes =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''';
  static const String _rootRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';
  static const String _workbook =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="MOM" sheetId="1" r:id="rId1"/></sheets></workbook>''';
  static const String _workbookRelations =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';
  static const String _styles =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="16"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0B3D2E"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE7F3ED"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0"/><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs></styleSheet>''';
}

class _XlsxSheet {
  final Map<int, List<String>> _rows = <int, List<String>>{};
  final List<String> _merges = <String>[];

  void cell(int column, int row, String value, int style, {double? height}) {
    final String ref = '${String.fromCharCode(65 + column)}$row';
    _add(
      row,
      '<c r="$ref" s="$style" t="inlineStr"><is><t>${_escape(value)}</t></is></c>',
      height,
    );
  }

  void merge(String range, String value, int style, [double? height]) {
    final RegExpMatch match = RegExp(r'^([A-D]+)(\d+):').firstMatch(range)!;
    final int row = int.parse(match.group(2)!);
    _add(
      row,
      '<c r="${match.group(1)}$row" s="$style" t="inlineStr"><is><t>${_escape(value)}</t></is></c>',
      height,
    );
    _merges.add(range);
  }

  void metadata(int row, String label, String value) {
    cell(0, row, label, 2, height: 32);
    merge('B$row:D$row', value.isEmpty ? '—' : value, 3);
  }

  void _add(int row, String content, double? height) {
    final List<String> values = _rows.putIfAbsent(row, () => <String>[]);
    if (height != null &&
        !values.any((String value) => value.startsWith('height='))) {
      values.add('height="$height" customHeight="1"');
    }
    values.add(content);
  }

  String get xml {
    final List<int> keys = _rows.keys.toList()..sort();
    final StringBuffer rows = StringBuffer();
    for (final int row in keys) {
      final List<String> values = _rows[row]!;
      final String attributes = values
          .where((String value) => !value.startsWith('<'))
          .join(' ');
      final String content = values
          .where((String value) => value.startsWith('<'))
          .join();
      rows.write('<row r="$row" $attributes>$content</row>');
    }
    final int lastRow = keys.isEmpty ? 1 : keys.last;
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:D$lastRow"/><sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="17" customWidth="1"/><col min="2" max="2" width="58" customWidth="1"/><col min="3" max="3" width="24" customWidth="1"/><col min="4" max="4" width="17" customWidth="1"/></cols><sheetData>$rows</sheetData><mergeCells count="${_merges.length}">${_merges.map((String range) => '<mergeCell ref="$range"/>').join()}</mergeCells></worksheet>''';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
