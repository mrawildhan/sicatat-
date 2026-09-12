import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meeting_minute_models.dart';
import '../models/sicatat_types.dart';
import 'meeting_minute_photo_compressor.dart';

class MeetingMinuteService {
  MeetingMinuteService(this._client);

  final SupabaseClient _client;
  static const String photoBucket = 'meeting-minute-photos';
  static const String _select =
      'id,title,meeting_date,start_time,end_time,location,attendees,apologies,minute_taker,distribution_list,new_business_agenda,proposed_by,note,status,created_by,updated_at,follow_up_of,follow_up_source_title,follow_up_source_date,meeting_minute_action(id,item_date,issue_description,subject_discussion,assigned_to,due_date,position,progress_remark,meeting_minute_action_photo(id,meeting_minute_action_id,storage_path,file_name,mime_type,position))';

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
    String? followUpOf,
    String followUpSourceTitle = '',
    DateTime? followUpSourceDate,
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
      'follow_up_of': followUpOf,
      'follow_up_source_title': followUpSourceTitle.trim(),
      'follow_up_source_date': _dateText(followUpSourceDate),
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
    final Object existingResponse = await _client
        .from('meeting_minute_action')
        .select('id')
        .eq('meeting_minute_id', meetingId);
    final Set<String> existingIds = existingResponse is List
        ? existingResponse
              .map(
                (Object? row) => requireJsonMap(
                  row,
                  source: 'meeting minute action',
                ).requiredString('id'),
              )
              .toSet()
        : <String>{};
    final List<MeetingMinuteAction> meaningful = actions
        .where(
          (MeetingMinuteAction action) =>
              action.subjectDiscussion.trim().isNotEmpty ||
              action.issueDescription.trim().isNotEmpty ||
              action.assignedTo.trim().isNotEmpty ||
              action.progressRemark.trim().isNotEmpty ||
              action.itemDate != null ||
              action.dueDate != null,
        )
        .toList(growable: false);
    final Set<String> retainedIds = <String>{};
    for (int index = 0; index < meaningful.length; index++) {
      final MeetingMinuteAction action = meaningful[index];
      final Map<String, Object?> actionValues = action.toJson(
        meetingMinuteId: meetingId,
      )..['position'] = index;
      final String? actionId = action.id;
      if (actionId != null && existingIds.contains(actionId)) {
        actionValues.remove('id');
        await _client
            .from('meeting_minute_action')
            .update(actionValues)
            .eq('id', actionId)
            .eq('meeting_minute_id', meetingId);
        retainedIds.add(actionId);
      } else {
        actionValues.remove('id');
        final Object inserted = await _client
            .from('meeting_minute_action')
            .insert(actionValues)
            .select('id')
            .single();
        retainedIds.add(
          requireJsonMap(
            inserted,
            source: 'meeting minute action',
          ).requiredString('id'),
        );
      }
    }
    for (final String removedId in existingIds.difference(retainedIds)) {
      await _client.from('meeting_minute_action').delete().eq('id', removedId);
    }
    return loadOne(meetingId);
  }

  Future<MeetingMinuteActionPhoto> uploadActionPhoto({
    required String meetingId,
    required String actionId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('Berkas foto tidak berisi data.');
    }
    if (bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw const FormatException('Ukuran foto maksimal 8 MB.');
    }
    final Object existing = await _client
        .from('meeting_minute_action_photo')
        .select('id')
        .eq('meeting_minute_action_id', actionId)
        .limit(2);
    if (existing is List && existing.length >= 2) {
      throw const FormatException(
        'Setiap action plan maksimal dapat memiliki dua foto.',
      );
    }
    _imageExtension(fileName);
    final CompressedMeetingMinutePhoto compressed =
        MeetingMinutePhotoCompressor.compress(bytes: bytes, fileName: fileName);
    final String safeName = compressed.fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '-',
    );
    final String storagePath =
        'meeting-minutes/$meetingId/$actionId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(
          storagePath,
          compressed.bytes,
          fileOptions: const FileOptions(
            contentType: CompressedMeetingMinutePhoto.mimeType,
            upsert: false,
          ),
        );
    try {
      final Object response = await _client
          .from('meeting_minute_action_photo')
          .insert(<String, Object?>{
            'meeting_minute_action_id': actionId,
            'storage_path': storagePath,
            'file_name': safeName,
            'mime_type': CompressedMeetingMinutePhoto.mimeType,
            'size_bytes': compressed.bytes.lengthInBytes,
          })
          .select(
            'id,meeting_minute_action_id,storage_path,file_name,mime_type,position',
          )
          .single();
      return MeetingMinuteActionPhoto.fromJson(
        requireJsonMap(response, source: 'meeting minute action photo'),
      );
    } on Object {
      await _client.storage.from(photoBucket).remove(<String>[storagePath]);
      rethrow;
    }
  }

  Future<void> deleteActionPhoto(MeetingMinuteActionPhoto photo) async {
    await _client.storage.from(photoBucket).remove(<String>[photo.storagePath]);
    await _client
        .from('meeting_minute_action_photo')
        .delete()
        .eq('id', photo.id);
  }

  Future<String> photoUrl(MeetingMinuteActionPhoto photo) => _client.storage
      .from(photoBucket)
      .createSignedUrl(photo.storagePath, 3600);

  Future<List<MeetingMinuteExportPhoto>> downloadPhotos(
    MeetingMinute minute,
  ) async {
    final List<MeetingMinuteExportPhoto> output = <MeetingMinuteExportPhoto>[];
    for (final MeetingMinuteAction action in minute.actions) {
      for (final MeetingMinuteActionPhoto photo in action.photos.take(2)) {
        final Uint8List bytes = await _client.storage
            .from(photoBucket)
            .download(photo.storagePath);
        output.add(
          MeetingMinuteExportPhoto(
            actionId: action.id ?? '',
            fileName: photo.fileName,
            mimeType: photo.mimeType,
            bytes: bytes,
          ),
        );
      }
    }
    return output;
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

  static String _imageExtension(String fileName) {
    final String normalized = fileName.toLowerCase();
    if (normalized.endsWith('.png')) {
      return 'png';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'jpg';
    }
    throw const FormatException('Gunakan foto JPG, JPEG, atau PNG.');
  }
}

class MeetingMinuteExportPhoto {
  const MeetingMinuteExportPhoto({
    required this.actionId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String actionId;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

class MeetingMinuteExcelService {
  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  List<int> create(
    MeetingMinute minute, {
    List<MeetingMinuteExportPhoto> photos = const <MeetingMinuteExportPhoto>[],
  }) {
    final List<MeetingMinuteAction> actions = minute.actions.isEmpty
        ? <MeetingMinuteAction>[const MeetingMinuteAction()]
        : (List<MeetingMinuteAction>.of(minute.actions)
            ..sort((a, b) => a.position.compareTo(b.position)));
    final _XlsxSheet sheet = _XlsxSheet();
    final Map<String, List<MeetingMinuteExportPhoto>> photosByActionId =
        <String, List<MeetingMinuteExportPhoto>>{};
    for (final MeetingMinuteExportPhoto photo in photos) {
      if ((photo.mimeType == 'image/jpeg' || photo.mimeType == 'image/png') &&
          photo.actionId.isNotEmpty) {
        final List<MeetingMinuteExportPhoto> actionPhotos = photosByActionId
            .putIfAbsent(photo.actionId, () => <MeetingMinuteExportPhoto>[]);
        if (actionPhotos.length < 2) actionPhotos.add(photo);
      }
    }
    sheet.merge(
      'A1:H1',
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
    sheet.metadata(11, 'Tindak lanjut dari', _followUpText(minute));
    sheet.merge('A13:H13', 'ACTION PLAN', 4, 22);
    const List<String> headers = <String>[
      'No.',
      'Issues Description',
      'Action Plan',
      'Foto',
      'Date\nRaised',
      'Due\nDate',
      'Resp.\nPerson',
      'Progress /\nRemark',
    ];
    for (int column = 0; column < headers.length; column++) {
      sheet.cell(column, 14, headers[column], 5);
    }
    final List<_XlsxPhoto> workbookPhotos = <_XlsxPhoto>[];
    int row = 15;
    for (int actionIndex = 0; actionIndex < actions.length; actionIndex++) {
      final MeetingMinuteAction action = actions[actionIndex];
      final List<MeetingMinuteExportPhoto> actionPhotos = action.id == null
          ? const <MeetingMinuteExportPhoto>[]
          : (photosByActionId[action.id!] ??
                const <MeetingMinuteExportPhoto>[]);
      final int actionRow = row;
      final int actionEndRow =
          actionRow + (actionPhotos.isEmpty ? 0 : actionPhotos.length - 1);
      final double actionHeight = _actionHeight(action);
      sheet.cell(
        2,
        actionRow,
        _displayValue(action.subjectDiscussion),
        6,
        height: actionPhotos.isEmpty
            ? actionHeight
            : actionHeight < 108
            ? 108
            : actionHeight,
      );
      if (actionPhotos.isEmpty) {
        sheet.cell(3, actionRow, 'Tidak ada foto', 6);
      } else {
        for (
          int photoIndex = 0;
          photoIndex < actionPhotos.length;
          photoIndex++
        ) {
          final int photoRow = actionRow + photoIndex;
          sheet.cell(3, photoRow, '', 6, height: photoIndex == 0 ? null : 108);
          workbookPhotos.add(
            _XlsxPhoto.fromBytes(
              row: photoRow - 1,
              column: 3,
              extension: actionPhotos[photoIndex].mimeType == 'image/png'
                  ? 'png'
                  : 'jpg',
              bytes: actionPhotos[photoIndex].bytes,
            ),
          );
        }
      }
      _mergeOrCell(sheet, 0, actionRow, actionEndRow, '${actionIndex + 1}');
      _mergeOrCell(sheet, 1, actionRow, actionEndRow, _issueText(action));
      _mergeOrCell(
        sheet,
        4,
        actionRow,
        actionEndRow,
        _date(action.itemDate, fallback: 'Belum ditentukan'),
      );
      _mergeOrCell(
        sheet,
        5,
        actionRow,
        actionEndRow,
        _date(action.dueDate, fallback: 'Belum ditentukan'),
      );
      _mergeOrCell(
        sheet,
        6,
        actionRow,
        actionEndRow,
        _displayValue(action.assignedTo),
      );
      _mergeOrCell(
        sheet,
        7,
        actionRow,
        actionEndRow,
        _displayValue(action.progressRemark),
      );
      row = actionEndRow + 1;
    }
    final int noteRow = row + 1;
    sheet.merge(
      'A$noteRow:H$noteRow',
      minute.note.trim().isEmpty
          ? 'CATATAN: —'
          : 'CATATAN: ${minute.note.trim()}',
      3,
      42,
    );
    final Archive archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          _contentTypes(hasPhotos: workbookPhotos.isNotEmpty),
        ),
      )
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRelationships))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook))
      ..addFile(
        ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRelations),
      )
      ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          sheet.xml(hasPhotos: workbookPhotos.isNotEmpty),
        ),
      );
    if (workbookPhotos.isNotEmpty) {
      archive
        ..addFile(
          ArchiveFile.string(
            'xl/worksheets/_rels/sheet1.xml.rels',
            _sheetRelationships,
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/drawings/drawing1.xml',
            _drawing(workbookPhotos),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/drawings/_rels/drawing1.xml.rels',
            _drawingRelationships(workbookPhotos),
          ),
        );
      for (int index = 0; index < workbookPhotos.length; index++) {
        final _XlsxPhoto photo = workbookPhotos[index];
        archive.addFile(
          ArchiveFile.bytes(
            'xl/media/image${index + 1}.${photo.extension}',
            photo.bytes,
          ),
        );
      }
    }
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

  static String _followUpText(MeetingMinute minute) {
    final MeetingMinuteReference? source = minute.followUpSource;
    if (source == null) return '—';
    final String title = source.title.trim().isEmpty
        ? 'Notulen sebelumnya'
        : source.title.trim();
    final String date = _date(source.meetingDate, format: 'd MMMM y');
    return date.isEmpty ? title : '$title ($date)';
  }

  static String _issueText(MeetingMinuteAction action) {
    final String issue = action.issueDescription.trim();
    if (issue.isNotEmpty) return issue;
    final String actionPlan = action.subjectDiscussion.trim();
    return actionPlan.isEmpty ? 'Belum diisi' : actionPlan;
  }

  static String _displayValue(String value) =>
      value.trim().isEmpty ? 'Belum diisi' : value.trim();

  static void _mergeOrCell(
    _XlsxSheet sheet,
    int column,
    int startRow,
    int endRow,
    String value,
  ) {
    if (startRow == endRow) {
      sheet.cell(column, startRow, value, 6);
      return;
    }
    final String letter = String.fromCharCode(65 + column);
    sheet.merge('$letter$startRow:$letter$endRow', value, 6);
  }

  static double _actionHeight(MeetingMinuteAction action) {
    int estimatedLines(String text, int charactersPerLine) =>
        text.split('\n').fold<int>(0, (int total, String line) {
          final int characters = line.trim().isEmpty ? 1 : line.trim().length;
          return total + (characters / charactersPerLine).ceil().clamp(1, 50);
        });
    final int planLines = estimatedLines(action.subjectDiscussion, 42);
    final int progressLines = estimatedLines(action.progressRemark, 22);
    final int lines = planLines > progressLines ? planLines : progressLines;
    return (lines * 15 + 12).clamp(52, 520).toDouble();
  }

  static String _date(
    DateTime? value, {
    String format = 'dd/MM/yyyy',
    String fallback = '',
  }) {
    if (value == null) return fallback;
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
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year.toString().padLeft(4, '0')}';
  }

  static String _clock(String? value) {
    final String raw = (value ?? '').trim();
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  static String _contentTypes({required bool hasPhotos}) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${hasPhotos ? '<Default Extension="png" ContentType="image/png"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>' : ''}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''';
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
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="16"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font></fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0B3D2E"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE7F3ED"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF16A9D6"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0"/><xf numFmtId="0" fontId="2" fillId="4" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs></styleSheet>''';

  static const String _sheetRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>''';

  static String _drawingRelationships(List<_XlsxPhoto> photos) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List<String>.generate(photos.length, (int index) => '<Relationship Id="rId${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${index + 1}.${photos[index].extension}"/>').join()}</Relationships>''';

  static String _drawing(List<_XlsxPhoto> photos) {
    final StringBuffer anchors = StringBuffer();
    for (int index = 0; index < photos.length; index++) {
      final _XlsxPhoto photo = photos[index];
      anchors.write(
        '''<xdr:oneCellAnchor><xdr:from><xdr:col>${photo.column}</xdr:col><xdr:colOff>${photo.leftOffsetEmu}</xdr:colOff><xdr:row>${photo.row}</xdr:row><xdr:rowOff>152400</xdr:rowOff></xdr:from><xdr:ext cx="${photo.widthEmu}" cy="${photo.heightEmu}"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${index + 1}" name="Foto pembahasan ${index + 1}"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId${index + 1}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${photo.widthEmu}" cy="${photo.heightEmu}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>''',
      );
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">$anchors</xdr:wsDr>''';
  }
}

class _XlsxPhoto {
  const _XlsxPhoto._({
    required this.row,
    required this.column,
    required this.extension,
    required this.bytes,
    required this.widthEmu,
    required this.heightEmu,
    required this.leftOffsetEmu,
  });

  factory _XlsxPhoto.fromBytes({
    required int row,
    required int column,
    required String extension,
    required Uint8List bytes,
  }) {
    image.Image? decoded;
    try {
      decoded = image.decodeImage(bytes);
    } on Object {
      // The export still keeps legacy image bytes; a neutral 4:3 frame is
      // safer than failing the entire workbook when their metadata is invalid.
      decoded = null;
    }
    final int sourceWidth = decoded?.width ?? 4;
    final int sourceHeight = decoded?.height ?? 3;
    const int maxWidthPx = 180;
    const int maxHeightPx = 108;
    final double scale =
        (maxWidthPx / sourceWidth) < (maxHeightPx / sourceHeight)
        ? maxWidthPx / sourceWidth
        : maxHeightPx / sourceHeight;
    final int widthPx = (sourceWidth * scale).round().clamp(1, maxWidthPx);
    final int heightPx = (sourceHeight * scale).round().clamp(1, maxHeightPx);
    const int columnWidthPx = 202;
    return _XlsxPhoto._(
      row: row,
      column: column,
      extension: extension,
      bytes: bytes,
      widthEmu: widthPx * 9525,
      heightEmu: heightPx * 9525,
      leftOffsetEmu: ((columnWidthPx - widthPx) ~/ 2) * 9525,
    );
  }

  final int row;
  final int column;
  final String extension;
  final Uint8List bytes;
  final int widthEmu;
  final int heightEmu;
  final int leftOffsetEmu;
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
    final RegExpMatch match = RegExp(r'^([A-Z]+)(\d+):').firstMatch(range)!;
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
    merge('B$row:H$row', value.isEmpty ? '—' : value, 3);
  }

  void _add(int row, String content, double? height) {
    final List<String> values = _rows.putIfAbsent(row, () => <String>[]);
    if (height != null &&
        !values.any((String value) => value.startsWith('height='))) {
      values.add('height="$height" customHeight="1"');
    }
    values.add(content);
  }

  String xml({required bool hasPhotos}) {
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
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><dimension ref="A1:H$lastRow"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="18" customWidth="1"/><col min="2" max="2" width="34" customWidth="1"/><col min="3" max="3" width="44" customWidth="1"/><col min="4" max="4" width="28" customWidth="1"/><col min="5" max="5" width="13" customWidth="1"/><col min="6" max="6" width="13" customWidth="1"/><col min="7" max="7" width="18" customWidth="1"/><col min="8" max="8" width="24" customWidth="1"/></cols><sheetData>$rows</sheetData><mergeCells count="${_merges.length}">${_merges.map((String range) => '<mergeCell ref="$range"/>').join()}</mergeCells>${hasPhotos ? '<drawing r:id="rId1"/>' : ''}</worksheet>''';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
