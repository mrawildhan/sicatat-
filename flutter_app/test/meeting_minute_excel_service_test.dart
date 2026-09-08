import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/meeting_minute_models.dart';
import 'package:sicatat_flutter/data/reports/meeting_minute_service.dart';

void main() {
  test(
    'export MOM menempatkan satu foto opsional pada baris pembahasannya',
    () {
      final MeetingMinute minute = MeetingMinute(
        id: 'mom-1',
        title: 'STI Muara Port Electrical Inspection',
        status: MeetingMinuteStatus.completed,
        createdBy: 'user-1',
        updatedAt: DateTime(2026, 1, 30, 12),
        meetingDate: DateTime(2026, 1, 30),
        startTime: '09:45:00',
        endTime: '11:50:00',
        location: 'Muara Port STI',
        attendees: 'Arutmin Indonesia, PLN, TCI',
        minuteTaker: 'Ilham Ananto',
        actions: <MeetingMinuteAction>[
          MeetingMinuteAction(
            itemDate: DateTime(2026, 1, 30),
            subjectDiscussion: 'Pengecekan panel dan switchgear',
            assignedTo: 'PLN dan TCI',
            dueDate: DateTime(2026, 2, 5),
            id: 'action-1',
          ),
        ],
      );

      final List<int> bytes = MeetingMinuteExcelService().create(
        minute,
        photos: <MeetingMinuteExportPhoto>[
          MeetingMinuteExportPhoto(
            actionId: 'action-1',
            fileName: 'panel-lvmdp.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[
              0x89,
              0x50,
              0x4e,
              0x47,
              0x0d,
              0x0a,
              0x1a,
              0x0a,
            ]),
          ),
          MeetingMinuteExportPhoto(
            actionId: 'action-1',
            fileName: 'foto-lama-yang-tidak-diekspor.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[
              0x89,
              0x50,
              0x4e,
              0x47,
              0x0d,
              0x0a,
              0x1a,
              0x0a,
            ]),
          ),
        ],
      );
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final Map<String, ArchiveFile> files = <String, ArchiveFile>{
        for (final ArchiveFile file in archive) file.name: file,
      };

      expect(bytes.take(2), <int>[0x50, 0x4b]);
      expect(
        files.keys,
        containsAll(<String>[
          '[Content_Types].xml',
          'xl/workbook.xml',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/drawings/drawing1.xml',
          'xl/media/image1.png',
        ]),
      );
      final String sheetXml = utf8.decode(
        files['xl/worksheets/sheet1.xml']!.content,
      );
      expect(sheetXml, contains('STI Muara Port Electrical Inspection'));
      expect(sheetXml, contains('Pengecekan panel dan switchgear'));
      expect(sheetXml, contains('PLN dan TCI'));
      expect(sheetXml, contains('SUBJECT\nDISCUSSIONS'));
      expect(sheetXml, contains('PHOTO'));
      expect(sheetXml, contains('ASSIGNED TO'));
      expect(sheetXml, contains('DATE DUE'));
      expect(sheetXml, contains('panel-lvmdp.png'));
      expect(sheetXml, isNot(contains('FOTO PEMBAHASAN')));
      expect(sheetXml, isNot(contains('foto-lama-yang-tidak-diekspor.png')));
      expect(
        utf8.decode(files['xl/drawings/drawing1.xml']!.content),
        allOf(contains('Foto pembahasan 1'), contains('<xdr:col>2</xdr:col>')),
      );
      expect(files.keys, isNot(contains('xl/media/image2.png')));
    },
  );
}
