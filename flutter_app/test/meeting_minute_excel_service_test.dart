import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/meeting_minute_models.dart';
import 'package:sicatat_flutter/data/reports/meeting_minute_service.dart';

void main() {
  test(
    'export MOM menghasilkan berkas XLSX dengan metadata dan tindak lanjut',
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
          ),
        ],
      );

      final List<int> bytes = MeetingMinuteExcelService().create(minute);
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
        ]),
      );
      final String sheetXml = utf8.decode(
        files['xl/worksheets/sheet1.xml']!.content,
      );
      expect(sheetXml, contains('STI Muara Port Electrical Inspection'));
      expect(sheetXml, contains('Pengecekan panel dan switchgear'));
      expect(sheetXml, contains('PLN dan TCI'));
    },
  );
}
