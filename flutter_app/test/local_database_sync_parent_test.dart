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
}
