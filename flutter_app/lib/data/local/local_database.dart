import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/field_entry_models.dart';
import '../models/dashboard_activity.dart';
import '../models/master_data_models.dart';
import '../models/sicatat_types.dart';
import '../models/sheet_model.dart';
import '../models/sync_queue_item.dart';

/// SQLite database matching the existing SICATAT local schema.
///
/// The migration intentionally keeps the same table and column names so that
/// the offline queue can be ported without changing the Supabase contract.
class LocalDatabase {
  LocalDatabase._();

  static final instance = LocalDatabase._();
  static const Uuid _uuid = Uuid();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final databasesPath = await getDatabasesPath();
    final currentDatabasePath = path.join(databasesPath, 'sicatat_local.db');
    _database = await openDatabase(
      currentDatabasePath,
      version: 5,
      onCreate: (db, version) async {
        final schema = await rootBundle.loadString(
          'assets/sql/local_schema.sql',
        );
        for (final statement in schema.split(';')) {
          final sql = statement
              .split('\n')
              .where((line) => !line.trimLeft().startsWith('--'))
              .join('\n')
              .trim();
          if (sql.isNotEmpty) await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute(
            'create table if not exists cache_app_config (id text primary key, data text not null)',
          );
        }
        if (oldVersion < 4) {
          await db.execute('alter table reading add column anomaly_note text');
        }
        if (oldVersion < 5) {
          await db.execute('alter table sheet add column verified_by text');
          await db.execute('alter table sheet add column verified_at text');
          await db.execute('''
            create table if not exists audit_log (
              id text primary key,
              client_uuid text not null unique,
              entity_type text not null,
              entity_id text not null,
              action text not null,
              old_value text,
              new_value text,
              changed_by text,
              changed_at text not null,
              sync_status text not null default 'pending'
            )
          ''');
        }
      },
    );
    await _importLegacyDatabaseIfNeeded(
      _database!,
      legacyDatabasePath: path.join(databasesPath, 'sicatat_localSQLite.db'),
    );
    await _recoverLegacyConflictsIfNeeded(_database!);
    return _database!;
  }

  Future<void> _importLegacyDatabaseIfNeeded(
    Database database, {
    required String legacyDatabasePath,
  }) async {
    const markerId = 'legacy_capacitor_database_imported_v1';
    final marker = await database.query(
      'cache_app_config',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: const <Object?>[markerId],
      limit: 1,
    );
    if (marker.isNotEmpty) return;

    if (!await File(legacyDatabasePath).exists()) {
      await _saveLegacyImportMarker(database, markerId);
      return;
    }

    await database.execute('ATTACH DATABASE ? AS legacy', <Object?>[
      legacyDatabasePath,
    ]);
    try {
      await database.transaction((transaction) async {
        const transactionTables = <String>[
          'round',
          'unit_status',
          'sheet_contributor',
          'cache_equipment',
          'cache_measurement_point',
          'cache_shift',
          'cache_team',
          'cache_roster_anchor',
          'cache_app_user',
        ];
        for (final table in transactionTables) {
          await transaction.execute(
            'INSERT OR IGNORE INTO $table SELECT * FROM legacy.$table',
          );
        }
        // v5 adds verification and anomaly columns. Import the v3 legacy
        // shape explicitly so a first launch never fails with a SELECT *
        // column-count mismatch.
        await transaction.execute('''
          INSERT OR IGNORE INTO sheet (
            id, client_uuid, module_id, template_version, tanggal, shift_id,
            team_id, status, created_by, created_at, submitted_at, app_version,
            force_submitted_by, force_submitted_at, force_reason, sync_status
          )
          SELECT
            id, client_uuid, module_id, template_version, tanggal, shift_id,
            team_id, status, created_by, created_at, submitted_at, app_version,
            force_submitted_by, force_submitted_at, force_reason, sync_status
          FROM legacy.sheet
        ''');
        await transaction.execute('''
          INSERT OR IGNORE INTO reading (
            id, client_uuid, round_id, unit_status_id, measurement_point_id,
            value_numeric, value_boolean, value_text, measured_at, recorded_by,
            is_anomaly, sync_status
          )
          SELECT
            id, client_uuid, round_id, unit_status_id, measurement_point_id,
            value_numeric, value_boolean, value_text, measured_at, recorded_by,
            is_anomaly, sync_status
          FROM legacy.reading
        ''');
        // Queue IDs are local autoincrement values. Do not copy them so an
        // existing Flutter queue cannot cause a legacy operation to be lost.
        await transaction.execute('''
          INSERT INTO sync_queue (
            entity_type, client_uuid, operation, payload_json, created_at,
            attempt_count, last_error
          )
          SELECT entity_type, client_uuid, operation, payload_json, created_at,
            attempt_count, last_error
          FROM legacy.sync_queue
          ORDER BY id ASC
        ''');
        await transaction.insert('cache_app_config', <String, Object?>{
          'id': markerId,
          'data': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } finally {
      await database.execute('DETACH DATABASE legacy');
    }
  }

  Future<void> _saveLegacyImportMarker(Database database, String markerId) =>
      database.insert('cache_app_config', <String, Object?>{
        'id': markerId,
        'data': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _recoverLegacyConflictsIfNeeded(Database database) async {
    const markerId = 'legacy_capacitor_conflicts_requeued_v1';
    final marker = await database.query(
      'cache_app_config',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: const <Object?>[markerId],
      limit: 1,
    );
    if (marker.isNotEmpty) return;
    await database.transaction((transaction) async {
      final sheets = await transaction.query(
        'sheet',
        where: 'sync_status = ?',
        whereArgs: const <Object?>['conflict'],
      );
      for (final sheet in sheets) {
        final sheetId = sheet['id'];
        final sheetClientUuid = sheet['client_uuid'];
        if (sheetId is! String || sheetClientUuid is! String) continue;
        await transaction.update(
          'sheet',
          <String, Object?>{'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: <Object?>[sheetId],
        );
        await _enqueueLegacyRow(
          transaction,
          entityType: 'sheet',
          clientUuid: sheetClientUuid,
          payload: sheet,
        );

        final rounds = await transaction.query(
          'round',
          where: 'sheet_id = ?',
          whereArgs: <Object?>[sheetId],
          orderBy: 'rowid ASC',
        );
        for (final round in rounds) {
          final roundId = round['id'];
          final roundClientUuid = round['client_uuid'];
          if (roundId is! String || roundClientUuid is! String) continue;
          await transaction.update(
            'round',
            <String, Object?>{'sync_status': 'pending'},
            where: 'id = ?',
            whereArgs: <Object?>[roundId],
          );
          await _enqueueLegacyRow(
            transaction,
            entityType: 'round',
            clientUuid: roundClientUuid,
            payload: round,
          );

          final statuses = await transaction.query(
            'unit_status',
            where: 'round_id = ?',
            whereArgs: <Object?>[roundId],
            orderBy: 'rowid ASC',
          );
          for (final status in statuses) {
            final statusClientUuid = status['client_uuid'];
            if (statusClientUuid is! String) continue;
            await transaction.update(
              'unit_status',
              <String, Object?>{'sync_status': 'pending'},
              where: 'client_uuid = ?',
              whereArgs: <Object?>[statusClientUuid],
            );
            await _enqueueLegacyRow(
              transaction,
              entityType: 'unit_status',
              clientUuid: statusClientUuid,
              payload: status,
            );
          }

          final readings = await transaction.query(
            'reading',
            where: 'round_id = ?',
            whereArgs: <Object?>[roundId],
            orderBy: 'rowid ASC',
          );
          for (final reading in readings) {
            final readingClientUuid = reading['client_uuid'];
            if (readingClientUuid is! String) continue;
            await transaction.update(
              'reading',
              <String, Object?>{'sync_status': 'pending'},
              where: 'client_uuid = ?',
              whereArgs: <Object?>[readingClientUuid],
            );
            await _enqueueLegacyRow(
              transaction,
              entityType: 'reading',
              clientUuid: readingClientUuid,
              payload: reading,
            );
          }
        }

        final contributors = await transaction.query(
          'sheet_contributor',
          where: 'sheet_id = ?',
          whereArgs: <Object?>[sheetId],
        );
        for (final contributor in contributors) {
          await _enqueue(
            transaction,
            entityType: 'sheet_contributor',
            clientUuid: _uuid.v4(),
            operation: 'insert',
            payload: contributor,
          );
        }
      }
      await transaction.insert('cache_app_config', <String, Object?>{
        'id': markerId,
        'data': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _enqueueLegacyRow(
    DatabaseExecutor executor, {
    required String entityType,
    required String clientUuid,
    required Map<String, Object?> payload,
  }) {
    final serverPayload = Map<String, Object?>.from(payload)
      ..remove('sync_status');
    return _enqueue(
      executor,
      entityType: entityType,
      clientUuid: clientUuid,
      operation: 'insert',
      payload: serverPayload,
    );
  }

  Future<String?> normalizeLegacyRoundTime(
    String clientUuid,
    String rawTime,
  ) async {
    final match = RegExp(r'^(\d{2}):(\d{2})(?::(\d{2}))?$').firstMatch(rawTime);
    if (match == null) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT sheet.tanggal AS sheet_date
      FROM round
      INNER JOIN sheet ON sheet.id = round.sheet_id
      WHERE round.client_uuid = ?
      LIMIT 1
    ''',
      <Object?>[clientUuid],
    );
    if (rows.isEmpty || rows.single['sheet_date'] is! String) return null;
    final date = DateTime.tryParse(rows.single['sheet_date']! as String);
    if (date == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '0');
    if (hour == null || minute == null || second == null) return null;
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    ).toUtc().toIso8601String();
    await db.update(
      'round',
      <String, Object?>{'jam': normalized},
      where: 'client_uuid = ?',
      whereArgs: <Object?>[clientUuid],
    );
    return normalized;
  }

  Future<List<SheetModel>> listSheets() async {
    final db = await database;
    final rows = await db.query(
      'sheet',
      orderBy: 'tanggal DESC, created_at DESC',
    );
    return rows.map(SheetModel.fromLocalRow).toList(growable: false);
  }

  /// Stores server sheet headers for list visibility without ever adding them
  /// to the local sync queue. Pending work made on this device is preserved.
  Future<void> cacheRemoteSheets(Iterable<SheetModel> sheets) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final sheet in sheets) {
        final existing = await transaction.query(
          'sheet',
          columns: const <String>['sync_status'],
          where: 'id = ?',
          whereArgs: <Object?>[sheet.id],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            existing.single['sync_status'] == 'pending') {
          continue;
        }
        final row = <String, Object?>{
          'id': sheet.id,
          'client_uuid': sheet.clientUuid,
          'module_id': sheet.moduleId,
          'template_version': sheet.templateVersion,
          'tanggal': _dateOnly(sheet.date),
          'shift_id': sheet.shiftId,
          'team_id': sheet.teamId,
          'status': sheet.status.storageValue,
          'created_by': sheet.createdBy,
          'created_at': sheet.createdAt.toUtc().toIso8601String(),
          'sync_status': SheetSyncStatus.synced.name,
        };
        if (existing.isEmpty) {
          await transaction.insert('sheet', row);
        } else {
          await transaction.update(
            'sheet',
            row,
            where: 'id = ?',
            whereArgs: <Object?>[sheet.id],
          );
        }
      }
    });
  }

  /// Returns an on-device summary for one calendar day.
  ///
  /// A queued operation means the device has data that still needs to be sent
  /// to Supabase. This must not be displayed as synced.
  Future<DashboardActivity> getDashboardActivity(DateTime day) async {
    final db = await database;
    final String date = _dateOnly(day);
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT COUNT(*) FROM sheet WHERE tanggal = ? AND status = 'draft') AS draft_count,
        (SELECT COUNT(*) FROM sheet WHERE tanggal = ? AND sync_status = 'synced') AS synced_count,
        (SELECT COUNT(*)
           FROM reading
           INNER JOIN round ON round.id = reading.round_id
           INNER JOIN sheet ON sheet.id = round.sheet_id
          WHERE sheet.tanggal = ?
            AND reading.value_numeric >= 60) AS high_temperature_count,
        (SELECT COUNT(*) FROM sync_queue) AS pending_sync_count,
        (SELECT COUNT(*) FROM sheet WHERE sync_status = 'conflict') AS conflict_count
      ''',
      <Object?>[date, date, date],
    );
    final Map<String, Object?> row = rows.single;
    return DashboardActivity(
      draftCount: _countFromRow(row, 'draft_count'),
      syncedCount: _countFromRow(row, 'synced_count'),
      highTemperatureCount: _countFromRow(row, 'high_temperature_count'),
      pendingSyncCount: _countFromRow(row, 'pending_sync_count'),
      conflictCount: _countFromRow(row, 'conflict_count'),
    );
  }

  int _countFromRow(Map<String, Object?> row, String key) {
    final Object? value = row[key];
    return value is num ? value.toInt() : 0;
  }

  Future<SheetModel?> getSheet(String id) async {
    final db = await database;
    final rows = await db.query(
      'sheet',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : SheetModel.fromLocalRow(rows.single);
  }

  Future<void> cacheShifts(List<ShiftOption> shifts) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final shift in shifts) {
        await transaction.insert('cache_shift', <String, Object?>{
          'id': shift.id,
          'data': jsonEncode(shift.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String?> getCachedShiftName(String id) async {
    final db = await database;
    final rows = await db.query(
      'cache_shift',
      columns: <String>['data'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final encoded = rows.single['data'];
    if (encoded is! String) return null;
    return ShiftOption.fromJson(
      requireJsonMap(jsonDecode(encoded), source: 'cache shift'),
    ).name;
  }

  Future<List<ShiftOption>> getCachedShifts() async {
    final db = await database;
    final rows = await db.query('cache_shift', columns: <String>['data']);
    final shifts = rows
        .map((row) => row['data'])
        .whereType<String>()
        .map(
          (encoded) => ShiftOption.fromJson(
            requireJsonMap(jsonDecode(encoded), source: 'cache shift'),
          ),
        )
        .toList(growable: false);
    shifts.sort((left, right) => left.code.compareTo(right.code));
    return shifts;
  }

  Future<void> cacheTemperatureTemplate(TemperatureTemplate template) async {
    final db = await database;
    await db.insert('cache_app_config', <String, Object?>{
      'id': 'temperature_template',
      'data': jsonEncode(<String, Object?>{
        'module_id': template.moduleId,
        'version': template.version,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TemperatureTemplate?> getCachedTemperatureTemplate() async {
    final db = await database;
    final rows = await db.query(
      'cache_app_config',
      columns: <String>['data'],
      where: 'id = ?',
      whereArgs: <Object?>['temperature_template'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final encoded = rows.single['data'];
    if (encoded is! String) return null;
    final json = requireJsonMap(
      jsonDecode(encoded),
      source: 'cache template suhu',
    );
    return TemperatureTemplate(
      moduleId: json.requiredString('module_id'),
      version: json.requiredString('version'),
    );
  }

  Future<void> cacheMeasurementPoints(List<MeasurementPoint> points) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final point in points) {
        await transaction.insert('cache_measurement_point', <String, Object?>{
          'id': point.id,
          'data': jsonEncode(point.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<MeasurementPoint>> getCachedGearboxMeasurementPoints() async {
    final db = await database;
    final rows = await db.query(
      'cache_measurement_point',
      columns: <String>['data'],
    );
    const codes = <String>[
      'gb_low_speed',
      'gb_intermediate',
      'gb_high_speed',
      'gb_input_shaft',
    ];
    final byCode = <String, MeasurementPoint>{};
    for (final row in rows) {
      final encoded = row['data'];
      if (encoded is String) {
        final point = MeasurementPoint.fromJson(
          requireJsonMap(jsonDecode(encoded), source: 'cache titik ukur'),
        );
        byCode[point.code] = point;
      }
    }
    return codes
        .map((code) => byCode[code])
        .whereType<MeasurementPoint>()
        .toList(growable: false);
  }

  /// Saves a draft and its idempotent sync operation in one SQLite transaction.
  /// No widget should write to the transaction tables directly.
  Future<SheetModel> insertSheet(CreateSheetCommand command) async {
    final db = await database;
    final date = _dateOnly(command.date);
    final id = _uuid.v4();
    final clientUuid = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': id,
      'client_uuid': clientUuid,
      'module_id': command.moduleId,
      'template_version': command.templateVersion,
      'tanggal': date,
      'shift_id': command.shiftId,
      'team_id': command.teamId,
      'status': SheetStatus.draft.storageValue,
      'created_by': command.createdBy,
      'created_at': createdAt.toIso8601String(),
    };

    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'sheet',
        columns: <String>['id'],
        where: 'module_id = ? AND tanggal = ? AND shift_id = ? AND team_id = ?',
        whereArgs: <Object?>[
          command.moduleId,
          date,
          command.shiftId,
          command.teamId,
        ],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const SheetAlreadyExistsException();
      }
      await transaction.insert('sheet', <String, Object?>{
        ...payload,
        'sync_status': 'pending',
      });
      await transaction.insert('sync_queue', <String, Object?>{
        'entity_type': 'sheet',
        'client_uuid': clientUuid,
        'operation': 'insert',
        'payload_json': jsonEncode(payload),
      });
    });

    return SheetModel(
      id: id,
      clientUuid: clientUuid,
      date: command.date,
      shiftId: command.shiftId,
      teamId: command.teamId,
      moduleId: command.moduleId,
      templateVersion: command.templateVersion,
      createdBy: command.createdBy,
      createdAt: createdAt,
      status: SheetStatus.draft,
      syncStatus: SheetSyncStatus.pending,
    );
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<RoundModel> getOrCreateRound({
    required String sheetId,
    required InspectionSection section,
    required int roundNumber,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      final existing = await transaction.query(
        'round',
        where: 'sheet_id = ? AND section = ? AND round_number = ?',
        whereArgs: <Object?>[sheetId, section.storageValue, roundNumber],
        limit: 1,
      );
      if (existing.isNotEmpty) return RoundModel.fromLocalRow(existing.single);

      final id = _uuid.v4();
      final clientUuid = _uuid.v4();
      final payload = <String, Object?>{
        'id': id,
        'client_uuid': clientUuid,
        'sheet_id': sheetId,
        'section': section.storageValue,
        'round_number': roundNumber,
        'jam': null,
      };
      await transaction.insert('round', <String, Object?>{
        ...payload,
        'sync_status': 'pending',
      });
      await _enqueue(
        transaction,
        entityType: 'round',
        clientUuid: clientUuid,
        operation: 'insert',
        payload: payload,
      );
      return RoundModel(
        id: id,
        clientUuid: clientUuid,
        sheetId: sheetId,
        section: section,
        roundNumber: roundNumber,
        syncStatus: 'pending',
      );
    });
  }

  /// Read-only lookup used by the summary. It must not create a missing round,
  /// otherwise opening a summary could make an empty draft look partially done.
  Future<RoundModel?> getRound({
    required String sheetId,
    required InspectionSection section,
    required int roundNumber,
  }) async {
    final db = await database;
    final rows = await db.query(
      'round',
      where: 'sheet_id = ? AND section = ? AND round_number = ?',
      whereArgs: <Object?>[sheetId, section.storageValue, roundNumber],
      limit: 1,
    );
    return rows.isEmpty ? null : RoundModel.fromLocalRow(rows.single);
  }

  Future<void> setRoundTime({
    required String roundId,
    required DateTime inspectedAt,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await _ensureRoundEditable(transaction, roundId);
      final rows = await transaction.query(
        'round',
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Round not found.');
      }
      final clientUuid = rows.single['client_uuid'];
      final syncStatus = rows.single['sync_status'];
      if (clientUuid is! String || syncStatus is! String) {
        throw const FormatException('Round UUID is invalid.');
      }
      final timestamp = inspectedAt.toUtc().toIso8601String();
      await transaction.update(
        'round',
        <String, Object?>{'jam': timestamp, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object?>[roundId],
      );
      if (syncStatus != 'synced') {
        // A new round has not reached Supabase yet. Include its timestamp in
        // the insert payload, avoiding a second operation that races the
        // parent insert.
        final queued = await transaction.query(
          'sync_queue',
          where: 'entity_type = ? AND client_uuid = ? AND operation = ?',
          whereArgs: <Object?>['round', clientUuid, 'insert'],
          limit: 1,
        );
        if (queued.isNotEmpty) {
          final row = queued.single;
          final queueId = row['id'];
          final encoded = row['payload_json'];
          if (queueId is int && encoded is String) {
            final payload = requireJsonMap(
              jsonDecode(encoded),
              source: 'queued round insert',
            )..['jam'] = timestamp;
            await transaction.update(
              'sync_queue',
              <String, Object?>{'payload_json': jsonEncode(payload)},
              where: 'id = ?',
              whereArgs: <Object?>[queueId],
            );
            return;
          }
        }
      }
      await _enqueue(
        transaction,
        entityType: 'round',
        clientUuid: clientUuid,
        operation: 'update',
        payload: <String, Object?>{'client_uuid': clientUuid, 'jam': timestamp},
      );
    });
  }

  Future<UnitStatusModel?> getUnitStatus({
    required String roundId,
    required String unitCode,
  }) async {
    final db = await database;
    final rows = await db.query(
      'unit_status',
      where:
          "round_id = ? AND IFNULL(unit_code, '') = ? AND equipment_id IS NULL",
      whereArgs: <Object?>[roundId, unitCode],
      limit: 1,
    );
    return rows.isEmpty ? null : UnitStatusModel.fromLocalRow(rows.single);
  }

  Future<Map<String, double>> getNumericReadings({
    required String roundId,
    required String? unitStatusId,
  }) async {
    final values = await getReadingValues(
      roundId: roundId,
      unitStatusId: unitStatusId,
    );
    return <String, double>{
      for (final entry in values.entries)
        if (entry.value.numeric != null) entry.key: entry.value.numeric!,
    };
  }

  Future<Map<String, FieldReadingValue>> getReadingValues({
    required String roundId,
    required String? unitStatusId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'reading',
      columns: <String>[
        'measurement_point_id',
        'value_numeric',
        'value_boolean',
        'value_text',
      ],
      where: "round_id = ? AND IFNULL(unit_status_id, '') = ?",
      whereArgs: <Object?>[roundId, unitStatusId ?? ''],
    );
    final readings = <String, FieldReadingValue>{};
    for (final row in rows) {
      final id = row['measurement_point_id'];
      if (id is! String) continue;
      final numeric = row['value_numeric'];
      final boolean = row['value_boolean'];
      final text = row['value_text'];
      readings[id] = FieldReadingValue(
        numeric: numeric is num ? numeric.toDouble() : null,
        boolean: boolean is bool
            ? boolean
            : boolean is num
            ? boolean != 0
            : null,
        text: text is String ? text : null,
      );
    }
    return readings;
  }

  Future<UnitStatusModel> saveUnitStatus({
    required String roundId,
    required UnitOperationalStatus status,
    required DateTime answeredAt,
    String? unitCode,
    String? equipmentId,
    String? reason,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      await _ensureRoundEditable(transaction, roundId);
      final existing = await transaction.query(
        'unit_status',
        where: "round_id = ? AND IFNULL(unit_code, '') = ? AND IFNULL(equipment_id, '') = ?",
        whereArgs: <Object?>[roundId, unitCode ?? '', equipmentId ?? ''],
        limit: 1,
      );
      final timestamp = answeredAt.toUtc().toIso8601String();
      if (existing.isNotEmpty) {
        final row = existing.single;
        final id = row['id'];
        final clientUuid = row['client_uuid'];
        if (id is! String || clientUuid is! String) {
          throw const FormatException('Local unit status is invalid.');
        }
        final payload = <String, Object?>{
          'id': id,
          'client_uuid': clientUuid,
          'status': status.storageValue,
          'reason': reason,
          'answered_at': timestamp,
        };
        await transaction.update(
          'unit_status',
          <String, Object?>{...payload, 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        await _enqueue(
          transaction,
          entityType: 'unit_status',
          clientUuid: clientUuid,
          operation: 'update',
          payload: payload,
        );
        return UnitStatusModel(
          id: id,
          clientUuid: clientUuid,
          roundId: roundId,
          unitCode: unitCode,
          equipmentId: equipmentId,
          status: status,
          reason: reason,
          answeredAt: answeredAt,
          syncStatus: 'pending',
        );
      }

      final id = _uuid.v4();
      final clientUuid = _uuid.v4();
      final payload = <String, Object?>{
        'id': id,
        'client_uuid': clientUuid,
        'round_id': roundId,
        'unit_code': unitCode,
        'equipment_id': equipmentId,
        'status': status.storageValue,
        'reason': reason,
        'answered_at': timestamp,
      };
      await transaction.insert('unit_status', <String, Object?>{
        ...payload,
        'sync_status': 'pending',
      });
      await _enqueue(
        transaction,
        entityType: 'unit_status',
        clientUuid: clientUuid,
        operation: 'insert',
        payload: payload,
      );
      return UnitStatusModel(
        id: id,
        clientUuid: clientUuid,
        roundId: roundId,
        unitCode: unitCode,
        equipmentId: equipmentId,
        status: status,
        reason: reason,
        answeredAt: answeredAt,
        syncStatus: 'pending',
      );
    });
  }

  Future<String> saveTemperatureReading(TemperatureReadingCommand command) =>
      saveReading(
        ReadingCommand(
          roundId: command.roundId,
          unitStatusId: command.unitStatusId,
          measurementPointId: command.measurementPointId,
          recordedBy: command.recordedBy,
          valueNumeric: command.value,
          measuredAt: command.measuredAt,
        ),
      );

  Future<String> saveReading(ReadingCommand command) async {
    final db = await database;
    return db.transaction((transaction) async {
      await _ensureRoundEditable(transaction, command.roundId);
      final existing = await transaction.query(
        'reading',
        where: "round_id = ? AND measurement_point_id = ? AND IFNULL(unit_status_id, '') = ?",
        whereArgs: <Object?>[
          command.roundId,
          command.measurementPointId,
          command.unitStatusId ?? '',
        ],
        limit: 1,
      );
      final measuredAt = (command.measuredAt ?? DateTime.now())
          .toUtc()
          .toIso8601String();
      if (existing.isNotEmpty) {
        final row = existing.single;
        final id = row['id'];
        final clientUuid = row['client_uuid'];
        if (id is! String || clientUuid is! String) {
          throw const FormatException('Local reading is invalid.');
        }
        final payload = <String, Object?>{
          'id': id,
          'client_uuid': clientUuid,
          'value_numeric': command.valueNumeric,
          'value_boolean': command.valueBoolean,
          'value_text': command.valueText,
          'measured_at': measuredAt,
          'is_anomaly': command.isAnomaly,
          'anomaly_note': command.anomalyNote,
        };
        await transaction.update(
          'reading',
          <String, Object?>{...payload, 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        await _enqueue(
          transaction,
          entityType: 'reading',
          clientUuid: clientUuid,
          operation: 'update',
          payload: payload,
        );
        return id;
      }

      final id = _uuid.v4();
      final clientUuid = _uuid.v4();
      final payload = <String, Object?>{
        'id': id,
        'client_uuid': clientUuid,
        'round_id': command.roundId,
        'unit_status_id': command.unitStatusId,
        'measurement_point_id': command.measurementPointId,
        'value_numeric': command.valueNumeric,
        'value_boolean': command.valueBoolean,
        'value_text': command.valueText,
        'measured_at': measuredAt,
        'recorded_by': command.recordedBy,
        // Keep JSON booleans in queued payloads; SQLite itself accepts the
        // value and Supabase receives a valid PostgREST boolean.
        'is_anomaly': command.isAnomaly,
        'anomaly_note': command.anomalyNote,
      };
      await transaction.insert('reading', <String, Object?>{
        ...payload,
        'sync_status': 'pending',
      });
      await _enqueue(
        transaction,
        entityType: 'reading',
        clientUuid: clientUuid,
        operation: 'insert',
        payload: payload,
      );
      return id;
    });
  }

  Future<void> saveContributor({
    required String sheetId,
    required String userId,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'sheet_contributor',
        where: 'sheet_id = ? AND user_id = ?',
        whereArgs: <Object?>[sheetId, userId],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await transaction.insert('sheet_contributor', <String, Object?>{
        'sheet_id': sheetId,
        'user_id': userId,
      });
      await _enqueue(
        transaction,
        entityType: 'sheet_contributor',
        clientUuid: _uuid.v4(),
        operation: 'insert',
        payload: <String, Object?>{'sheet_id': sheetId, 'user_id': userId},
      );
    });
  }

  Future<List<ExpectedSide>> getIncompleteSides(String sheetId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      select r.section, r.round_number, u.unit_code, u.status
      from round r
      join unit_status u on u.round_id = r.id
      where r.sheet_id = ? and u.unit_code is not null and u.status is not null
    ''',
      <Object?>[sheetId],
    );
    final answered = <String>{};
    for (final row in rows) {
      final section = row['section'];
      final number = row['round_number'];
      final side = row['unit_code'];
      if (section is String && number is int && side is String) {
        answered.add('$section|$number|$side');
      }
    }
    return expectedSides
        .where(
          (side) => !answered.contains(
            '${side.section.storageValue}|${side.roundNumber}|${side.unitCode}',
          ),
        )
        .toList(growable: false);
  }

  Future<int> getContributorCount(String sheetId) async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'select count(*) from sheet_contributor where sheet_id = ?',
            <Object?>[sheetId],
          ),
        ) ??
        0;
  }

  Future<void> submitSheet({
    required String sheetId,
    required String submittedBy,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Sheet not found.');
      }
      final row = rows.single;
      final clientUuid = row['client_uuid'];
      if (clientUuid is! String) {
        throw const FormatException('Sheet UUID is invalid.');
      }
      final submittedAt = DateTime.now().toUtc().toIso8601String();
      await transaction.update(
        'sheet',
        <String, Object?>{
          'status': SheetStatus.submitted.storageValue,
          'submitted_at': submittedAt,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await _enqueue(
        transaction,
        entityType: 'sheet',
        clientUuid: clientUuid,
        operation: 'update',
        payload: <String, Object?>{
          'client_uuid': clientUuid,
          'status': SheetStatus.submitted.storageValue,
          'submitted_at': submittedAt,
        },
      );
      await _recordAudit(
        transaction,
        sheetId: sheetId,
        action: 'submit',
        changedBy: submittedBy,
        oldValue: <String, Object?>{'status': row['status']},
        newValue: <String, Object?>{
          'status': SheetStatus.submitted.storageValue,
          'submitted_at': submittedAt,
        },
      );
    });
  }

  /// Reopens a submitted sheet before verification, so the originating crew
  /// can correct a reading and submit it again.
  Future<void> reopenSheetForCorrection({
    required String sheetId,
    required String reopenedBy,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Sheet not found.');
      }
      final row = rows.single;
      if (row['status'] == SheetStatus.verified.storageValue) {
        throw const FormatException('A verified sheet cannot be reopened.');
      }
      final clientUuid = row['client_uuid'];
      if (clientUuid is! String) {
        throw const FormatException('Sheet UUID is invalid.');
      }
      const payload = <String, Object?>{
        'status': 'draft',
        'submitted_at': null,
      };
      await transaction.update(
        'sheet',
        <String, Object?>{...payload, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await _enqueue(
        transaction,
        entityType: 'sheet',
        clientUuid: clientUuid,
        operation: 'update',
        payload: <String, Object?>{'client_uuid': clientUuid, ...payload},
      );
      await _recordAudit(
        transaction,
        sheetId: sheetId,
        action: 'reopen_for_correction',
        changedBy: reopenedBy,
        oldValue: <String, Object?>{'status': row['status']},
        newValue: payload,
      );
    });
  }

  /// Allows a foreman, supervisor, or admin to submit an otherwise incomplete
  /// sheet. The full audit fields are kept in the local record and the same
  /// idempotent queue used by normal submission, so this also works offline.
  Future<void> forceSubmitSheet({
    required String sheetId,
    required String reason,
    required String submittedBy,
  }) async {
    final String cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const FormatException(
        'A reason is required for incomplete submission.',
      );
    }
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Sheet not found.');
      }
      final Object? rawClientUuid = rows.single['client_uuid'];
      if (rawClientUuid is! String) {
        throw const FormatException('Sheet UUID is invalid.');
      }
      final String submittedAt = DateTime.now().toUtc().toIso8601String();
      final Map<String, Object?> payload = <String, Object?>{
        'client_uuid': rawClientUuid,
        'status': SheetStatus.submittedIncomplete.storageValue,
        'submitted_at': submittedAt,
        'force_submitted_by': submittedBy,
        'force_submitted_at': submittedAt,
        'force_reason': cleanReason,
      };
      await transaction.update(
        'sheet',
        <String, Object?>{...payload, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await _enqueue(
        transaction,
        entityType: 'sheet',
        clientUuid: rawClientUuid,
        operation: 'update',
        payload: payload,
      );
      await _recordAudit(
        transaction,
        sheetId: sheetId,
        action: 'submit_incomplete_override',
        changedBy: submittedBy,
        oldValue: <String, Object?>{'status': rows.single['status']},
        newValue: payload,
      );
    });
  }

  Future<void> verifySheet({
    required String sheetId,
    required String verifiedBy,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Sheet not found.');
      }
      final row = rows.single;
      if (row['status'] != SheetStatus.submitted.storageValue &&
          row['status'] != SheetStatus.submittedIncomplete.storageValue) {
        throw const FormatException('Only submitted sheets can be verified.');
      }
      final clientUuid = row['client_uuid'];
      if (clientUuid is! String) {
        throw const FormatException('Sheet UUID is invalid.');
      }
      final verifiedAt = DateTime.now().toUtc().toIso8601String();
      final payload = <String, Object?>{
        'client_uuid': clientUuid,
        'status': SheetStatus.verified.storageValue,
        'verified_by': verifiedBy,
        'verified_at': verifiedAt,
      };
      await transaction.update(
        'sheet',
        <String, Object?>{...payload, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await _enqueue(
        transaction,
        entityType: 'sheet',
        clientUuid: clientUuid,
        operation: 'update',
        payload: payload,
      );
      await _recordAudit(
        transaction,
        sheetId: sheetId,
        action: 'verify',
        changedBy: verifiedBy,
        oldValue: <String, Object?>{'status': row['status']},
        newValue: payload,
      );
    });
  }

  Future<void> returnSheetForCorrection({
    required String sheetId,
    required String returnedBy,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const FormatException('A return reason is required.');
    }
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const LocalRecordNotFoundException('Sheet not found.');
      }
      final row = rows.single;
      if (row['status'] != SheetStatus.submitted.storageValue &&
          row['status'] != SheetStatus.submittedIncomplete.storageValue) {
        throw const FormatException('Only submitted sheets can be returned.');
      }
      final clientUuid = row['client_uuid'];
      if (clientUuid is! String) {
        throw const FormatException('Sheet UUID is invalid.');
      }
      final payload = <String, Object?>{
        'client_uuid': clientUuid,
        'status': SheetStatus.returned.storageValue,
      };
      await transaction.update(
        'sheet',
        <String, Object?>{...payload, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await _enqueue(
        transaction,
        entityType: 'sheet',
        clientUuid: clientUuid,
        operation: 'update',
        payload: payload,
      );
      await _recordAudit(
        transaction,
        sheetId: sheetId,
        action: 'return_for_correction',
        changedBy: returnedBy,
        oldValue: <String, Object?>{'status': row['status']},
        newValue: <String, Object?>{...payload, 'reason': cleanReason},
      );
    });
  }

  Future<List<SheetAuditEvent>> getSheetAuditTrail(String sheetId) async {
    final db = await database;
    final rows = await db.query(
      'audit_log',
      where: "entity_type = 'sheet' AND entity_id = ?",
      whereArgs: <Object?>[sheetId],
      orderBy: 'changed_at DESC',
    );
    return rows
        .map(SheetAuditEvent.fromLocalRow)
        .toList(growable: false);
  }

  /// Deletes a local sheet tree only after callers have removed an already
  /// synced parent from Supabase. Pending-only sheets can be removed locally.
  /// SQLite has no cascade constraints in this schema, so children and queued
  /// operations must be explicitly removed to avoid ghost sync attempts.
  Future<void> deleteSheetLocal(String sheetId) async {
    final db = await database;
    await db.transaction((transaction) async {
      final List<Map<String, Object?>> sheets = await transaction.query(
        'sheet',
        columns: const <String>['client_uuid'],
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
        limit: 1,
      );
      if (sheets.isEmpty) return;
      final Set<String> clientUuids = <String>{};
      final Object? sheetClientUuid = sheets.single['client_uuid'];
      if (sheetClientUuid is String) clientUuids.add(sheetClientUuid);
      final List<Map<String, Object?>> rounds = await transaction.query(
        'round',
        columns: const <String>['id', 'client_uuid'],
        where: 'sheet_id = ?',
        whereArgs: <Object?>[sheetId],
      );
      final List<String> roundIds = <String>[];
      for (final Map<String, Object?> round in rounds) {
        final Object? id = round['id'];
        final Object? clientUuid = round['client_uuid'];
        if (id is String) roundIds.add(id);
        if (clientUuid is String) clientUuids.add(clientUuid);
      }
      if (roundIds.isNotEmpty) {
        final String placeholders = List<String>.filled(
          roundIds.length,
          '?',
        ).join(',');
        for (final String table in <String>['unit_status', 'reading']) {
          final List<Map<String, Object?>> children = await transaction.query(
            table,
            columns: const <String>['client_uuid'],
            where: 'round_id IN ($placeholders)',
            whereArgs: roundIds,
          );
          for (final Map<String, Object?> child in children) {
            final Object? clientUuid = child['client_uuid'];
            if (clientUuid is String) clientUuids.add(clientUuid);
          }
          await transaction.delete(
            table,
            where: 'round_id IN ($placeholders)',
            whereArgs: roundIds,
          );
        }
        await transaction.delete(
          'round',
          where: 'sheet_id = ?',
          whereArgs: <Object?>[sheetId],
        );
      }
      await transaction.delete(
        'sheet_contributor',
        where: 'sheet_id = ?',
        whereArgs: <Object?>[sheetId],
      );
      await transaction.delete(
        'sheet',
        where: 'id = ?',
        whereArgs: <Object?>[sheetId],
      );
      if (clientUuids.isNotEmpty) {
        final String placeholders = List<String>.filled(
          clientUuids.length,
          '?',
        ).join(',');
        await transaction.delete(
          'sync_queue',
          where: 'client_uuid IN ($placeholders)',
          whereArgs: clientUuids.toList(growable: false),
        );
      }
      await transaction.delete(
        'sync_queue',
        where: 'entity_type = ? AND payload_json LIKE ?',
        whereArgs: <Object?>['sheet_contributor', '%$sheetId%'],
      );
    });
  }

  Future<List<SyncQueueItem>> getPendingSyncItems({int limit = 50}) async {
    final db = await database;
    final rows = await db.query('sync_queue', orderBy: 'id ASC', limit: limit);
    return rows
        .map((row) => SyncQueueItem.fromLocalRow(row))
        .toList(growable: false);
  }

  /// Determines whether a queued child row can safely be sent to Supabase.
  ///
  /// The local queue may contain rows imported from the legacy application, so
  /// FIFO order alone is not enough to guarantee that a foreign-key parent has
  /// already been accepted by the server.
  Future<SyncParentStatus> getParentSyncStatus(SyncQueueItem item) async {
    final List<(String table, Object? id)> parents = switch (item.entityType) {
      SyncEntityType.sheet => const <(String, Object?)>[],
      SyncEntityType.round => <(String, Object?)>[
        ('sheet', item.payload['sheet_id']),
      ],
      SyncEntityType.unitStatus => <(String, Object?)>[
        ('round', item.payload['round_id']),
      ],
      SyncEntityType.reading => <(String, Object?)>[
        ('round', item.payload['round_id']),
        if (item.payload['unit_status_id'] != null)
          ('unit_status', item.payload['unit_status_id']),
      ],
      SyncEntityType.sheetContributor => <(String, Object?)>[
        ('sheet', item.payload['sheet_id']),
      ],
      SyncEntityType.auditLog => const <(String, Object?)>[],
    };
    if (parents.isEmpty) return SyncParentStatus.root;
    final db = await database;
    var pending = false;
    for (final (table, rawParentId) in parents) {
      if (rawParentId is! String || rawParentId.isEmpty) {
        return SyncParentStatus.missing;
      }
      final rows = await db.query(
        table,
        columns: const <String>['sync_status'],
        where: 'id = ?',
        whereArgs: <Object?>[rawParentId],
        limit: 1,
      );
      if (rows.isEmpty) return SyncParentStatus.missing;
      switch (rows.single['sync_status']) {
        case 'conflict':
          return SyncParentStatus.conflict;
        case 'synced':
          break;
        default:
          pending = true;
      }
    }
    return pending ? SyncParentStatus.pending : SyncParentStatus.synced;
  }

  Future<void> markSyncSuccess(SyncQueueItem item) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'sync_queue',
        where: 'id = ?',
        whereArgs: <Object?>[item.id],
      );
      if (item.entityType == SyncEntityType.sheetContributor) return;
      await transaction.update(
        item.entityType.storageValue,
        <String, Object?>{'sync_status': 'synced'},
        where: 'client_uuid = ?',
        whereArgs: <Object?>[item.clientUuid],
      );
    });
  }

  Future<void> markSyncFailure(SyncQueueItem item, String message) async {
    final db = await database;
    await db.rawUpdate(
      'update sync_queue set attempt_count = attempt_count + 1, last_error = ? where id = ?',
      <Object?>[message, item.id],
    );
  }

  Future<void> markSyncConflict(SyncQueueItem item) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'sync_queue',
        where: 'id = ?',
        whereArgs: <Object?>[item.id],
      );
      if (item.entityType != SyncEntityType.sheetContributor) {
        await transaction.update(
          item.entityType.storageValue,
          <String, Object?>{'sync_status': 'conflict'},
          where: 'client_uuid = ?',
          whereArgs: <Object?>[item.clientUuid],
        );
      }
    });
  }

  Future<void> _enqueue(
    DatabaseExecutor executor, {
    required String entityType,
    required String clientUuid,
    required String operation,
    required Map<String, Object?> payload,
  }) => executor.insert('sync_queue', <String, Object?>{
    'entity_type': entityType,
    'client_uuid': clientUuid,
    'operation': operation,
    'payload_json': jsonEncode(payload),
  });

  Future<void> _recordAudit(
    DatabaseExecutor executor, {
    required String sheetId,
    required String action,
    required String changedBy,
    required Map<String, Object?> oldValue,
    required Map<String, Object?> newValue,
  }) async {
    final id = _uuid.v4();
    final clientUuid = _uuid.v4();
    final changedAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, Object?>{
      'id': id,
      'entity_type': 'sheet',
      'entity_id': sheetId,
      'action': action,
      'old_value': oldValue,
      'new_value': newValue,
      'changed_by': changedBy,
      'changed_at': changedAt,
    };
    await executor.insert('audit_log', <String, Object?>{
      ...payload,
      'client_uuid': clientUuid,
      'old_value': jsonEncode(oldValue),
      'new_value': jsonEncode(newValue),
      'sync_status': 'pending',
    });
    await _enqueue(
      executor,
      entityType: 'audit_log',
      clientUuid: clientUuid,
      operation: 'insert',
      payload: payload,
    );
  }

  Future<void> _ensureRoundEditable(
    DatabaseExecutor executor,
    String roundId,
  ) async {
    final rows = await executor.rawQuery(
      '''
      select s.status from round r
      join sheet s on s.id = r.sheet_id
      where r.id = ?
      ''',
      <Object?>[roundId],
    );
    if (rows.isEmpty) {
      throw const LocalRecordNotFoundException('Inspection round not found.');
    }
    final status = rows.single['status'];
    if (status != SheetStatus.draft.storageValue &&
        status != SheetStatus.returned.storageValue) {
      throw const FormatException(
        'Only draft or returned sheets can be changed.',
      );
    }
  }
}

class SheetAlreadyExistsException implements Exception {
  const SheetAlreadyExistsException();
}

class LocalRecordNotFoundException implements Exception {
  const LocalRecordNotFoundException(this.message);

  final String message;
}
