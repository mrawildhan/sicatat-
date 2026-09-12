import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/meeting_minute_models.dart';
import 'package:sicatat_flutter/data/reports/meeting_minute_service.dart';

void main() {
  test(
    'export MOM menampilkan kolom foto untuk satu dan dua foto action plan',
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
        followUpOf: 'mom-sebelumnya',
        followUpSourceTitle: 'MOM Ban Bocor Kendaraan Ringan',
        followUpSourceDate: DateTime(2026, 1, 23),
        actions: <MeetingMinuteAction>[
          MeetingMinuteAction(
            itemDate: DateTime(2025, 9, 22),
            issueDescription: 'Ban bocor kendaraan ringan di lapangan.',
            subjectDiscussion: 'Komunikasi ke SHE Site untuk revisi prosedur.',
            assignedTo: 'Aditio Y, Yoyon',
            dueDate: DateTime(2026, 4, 6),
            progressRemark: 'Pelatihan penggantian ban telah dilakukan.',
            id: 'action-1',
          ),
          MeetingMinuteAction(
            itemDate: DateTime(2025, 12, 1),
            issueDescription: 'Ban bocor kendaraan ringan di lapangan.',
            subjectDiscussion: 'Kirim permintaan resmi pelatihan via email.',
            assignedTo: 'Johan',
            dueDate: DateTime(2025, 12, 12),
            id: 'action-2',
            position: 1,
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
            actionId: 'action-2',
            fileName: 'screenshot-email.png',
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
            actionId: 'action-2',
            fileName: 'bukti-pelatihan.png',
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
      expect(sheetXml, contains('Ban bocor kendaraan ringan di lapangan.'));
      expect(
        sheetXml,
        contains('Komunikasi ke SHE Site untuk revisi prosedur.'),
      );
      expect(sheetXml, contains('Kirim permintaan resmi pelatihan via email.'));
      expect(sheetXml, contains('Pelatihan penggantian ban telah dilakukan.'));
      expect(sheetXml, contains('Issues Description'));
      expect(sheetXml, contains('Action Plan'));
      expect(sheetXml, contains('Foto'));
      expect(sheetXml, contains('Foto 1: panel-lvmdp.png'));
      expect(sheetXml, contains('Foto 1: screenshot-email.png'));
      expect(sheetXml, contains('Foto 2: bukti-pelatihan.png'));
      expect(sheetXml, contains('Progress /\nRemark'));
      expect(sheetXml, contains('Tindak lanjut dari'));
      expect(
        sheetXml,
        contains('MOM Ban Bocor Kendaraan Ringan (23 Januari 2026)'),
      );
      expect(sheetXml, contains('panel-lvmdp.png'));
      expect(sheetXml, contains('screenshot-email.png'));
      expect(sheetXml, contains('<mergeCell ref="A15:A17"/>'));
      expect(sheetXml, contains('<mergeCell ref="B15:B17"/>'));
      expect(sheetXml, contains('width="18"'));
      expect(
        utf8.decode(files['xl/drawings/drawing1.xml']!.content),
        allOf(
          contains('Foto pembahasan 1'),
          contains('Foto pembahasan 2'),
          contains('<xdr:col>3</xdr:col>'),
          contains('<xdr:row>14</xdr:row>'),
          contains('<xdr:row>15</xdr:row>'),
          contains('<xdr:row>16</xdr:row>'),
        ),
      );
      expect(
        files.keys,
        containsAll(<String>[
          'xl/media/image1.png',
          'xl/media/image2.png',
          'xl/media/image3.png',
        ]),
      );
    },
  );
}
