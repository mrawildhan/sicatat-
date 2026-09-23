import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/local/local_database.dart';
import 'package:sicatat_flutter/data/models/field_entry_models.dart';
import 'package:sicatat_flutter/data/models/sheet_model.dart';
import 'package:sicatat_flutter/data/models/sync_queue_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = '${await getDatabasesPath()}/sicatat_local.db';
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> markAllSynced() async {
    final db = LocalDatabase.instance;
    for (final item in await db.getPendingSyncItems()) {
      await db.markSyncSuccess(item);
    }
  }

  test(
    'updates to synced rows resolve their parent instead of becoming conflicts',
    () async {
      final db = LocalDatabase.instance;
      final sheet = await db.insertSheet(
        CreateSheetCommand(
          date: DateTime(2034, 12, 31),
          shiftId: 'shift-pagi',
          teamId: 'team-c',
          moduleId: 'module-temperature',
          templateVersion: '2.0.0',
          createdBy: 'user-admin',
        ),
      );
      final round = await db.getOrCreateRound(
        sheetId: sheet.id,
        section: InspectionSection.gearboxBreaker,
        roundNumber: 1,
      );
      // The sheet and round inserts reach Supabase before the first save.
      await markAllSynced();

      await db.setRoundTime(
        roundId: round.id,
        inspectedAt: DateTime.utc(2034, 12, 31, 6, 35),
      );
      await db.saveReading(
        ReadingCommand(
          roundId: round.id,
          measurementPointId: 'oil-level',
          recordedBy: 'user-admin',
          valueBoolean: true,
        ),
      );

      final items = await db.getPendingSyncItems();
      final roundUpdate = items.singleWhere(
        (item) =>
            item.entityType == SyncEntityType.round &&
            item.operation == SyncOperation.update,
      );
      final readingInsert = items.singleWhere(
        (item) => item.entityType == SyncEntityType.reading,
      );

      // Before the fix the round update had no sheet_id in its payload, was
      // reported as "missing", and dropped itself plus every reading.
      expect(
        await db.getParentSyncStatus(roundUpdate),
        SyncParentStatus.synced,
      );
      expect(
        await db.getParentSyncStatus(readingInsert),
        SyncParentStatus.pending,
      );

      await db.markSyncSuccess(roundUpdate);
      expect(
        await db.getParentSyncStatus(readingInsert),
        SyncParentStatus.synced,
      );
      await db.markSyncSuccess(readingInsert);

      // Correcting an already-synced reading queues an update without
      // round_id; it must still find its round.
      await db.saveReading(
        ReadingCommand(
          roundId: round.id,
          measurementPointId: 'oil-level',
          recordedBy: 'user-admin',
          valueBoolean: false,
        ),
      );
      final readingUpdate = (await db.getPendingSyncItems()).singleWhere(
        (item) =>
            item.entityType == SyncEntityType.reading &&
            item.operation == SyncOperation.update,
      );
      expect(
        await db.getParentSyncStatus(readingUpdate),
        SyncParentStatus.synced,
      );
    },
  );

  test('a draft continued on a second device adopts the server rows', () async {
    final db = LocalDatabase.instance;
    final sheet = await db.insertSheet(
      CreateSheetCommand(
        date: DateTime(2035, 1, 2),
        shiftId: 'shift-pagi',
        teamId: 'team-a',
        moduleId: 'module-temperature',
        templateVersion: '2.0.0',
        createdBy: 'user-a',
      ),
    );
    for (final item in await db.getPendingSyncItems()) {
      await db.markSyncSuccess(item);
    }

    // This device opens the draft before knowing the round exists remotely,
    // then saves a reading on its own copy of round 1.
    final local = await db.getOrCreateRound(
      sheetId: sheet.id,
      section: InspectionSection.gearboxBreaker,
      roundNumber: 1,
    );
    await db.saveReading(
      ReadingCommand(
        roundId: local.id,
        measurementPointId: 'motor-de',
        recordedBy: 'user-b',
        valueNumeric: 41,
      ),
    );

    await db.mergeRemoteSheetDetail(
      rounds: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'server-round',
          'client_uuid': 'server-round-uuid',
          'sheet_id': sheet.id,
          'section': 'gearbox_breaker',
          'round_number': 1,
          'jam': '2035-01-02T00:30:00Z',
        },
      ],
      unitStatuses: const <Map<String, Object?>>[],
      readings: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'server-reading',
          'client_uuid': 'server-reading-uuid',
          'round_id': 'server-round',
          'unit_status_id': null,
          'measurement_point_id': 'motor-nde',
          'value_numeric': 38,
          'value_boolean': null,
          'value_text': null,
          'measured_at': '2035-01-02T00:31:00Z',
          'recorded_by': 'user-a',
          'is_anomaly': false,
          'anomaly_note': null,
        },
      ],
    );

    // The form now finds the server round, with both readings on it.
    final round = await db.getRound(
      sheetId: sheet.id,
      section: InspectionSection.gearboxBreaker,
      roundNumber: 1,
    );
    expect(round?.id, 'server-round');
    final values = await db.getReadingValues(
      roundId: 'server-round',
      unitStatusId: null,
    );
    expect(values['motor-de']?.numeric, 41);
    expect(values['motor-nde']?.numeric, 38);

    // Queued changes now target the server row instead of a duplicate.
    final queued = await db.getPendingSyncItems();
    final roundInsert = queued.singleWhere(
      (item) => item.entityType == SyncEntityType.round,
    );
    expect(roundInsert.clientUuid, 'server-round-uuid');
    expect(roundInsert.payload['id'], 'server-round');
    expect(roundInsert.payload.containsKey('jam'), isFalse);
    final readingInsert = queued.singleWhere(
      (item) => item.entityType == SyncEntityType.reading,
    );
    expect(readingInsert.payload['round_id'], 'server-round');
    expect(
      jsonEncode(queued.map((item) => item.payload).toList()),
      isNot(contains(local.id)),
    );
  });
}
