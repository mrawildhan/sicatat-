import 'dart:convert';

import 'sicatat_types.dart';

enum SyncEntityType {
  sheet,
  round,
  unitStatus,
  reading,
  sheetContributor,
  auditLog,
}

enum SyncOperation { insert, update }

/// Relationship state between a queued row and its local parent record.
/// Child rows must never be sent before their parent has reached Supabase.
enum SyncParentStatus { root, pending, synced, conflict, missing }

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.clientUuid,
    required this.operation,
    required this.payload,
  });

  final int id;
  final SyncEntityType entityType;
  final String clientUuid;
  final SyncOperation operation;
  final JsonMap payload;

  factory SyncQueueItem.fromLocalRow(JsonMap row) {
    final encoded = row.requiredString('payload_json');
    return SyncQueueItem(
      id: row.requiredInt('id'),
      entityType: SyncEntityTypeX.fromStorage(
        row.requiredString('entity_type'),
      ),
      clientUuid: row.requiredString('client_uuid'),
      operation: SyncOperationX.fromStorage(row.requiredString('operation')),
      payload: requireJsonMap(
        jsonDecode(encoded),
        source: 'payload sinkronisasi',
      ),
    );
  }
}

extension SyncEntityTypeX on SyncEntityType {
  static SyncEntityType fromStorage(String value) => switch (value) {
    'sheet' => SyncEntityType.sheet,
    'round' => SyncEntityType.round,
    'unit_status' => SyncEntityType.unitStatus,
    'reading' => SyncEntityType.reading,
    'sheet_contributor' => SyncEntityType.sheetContributor,
    'audit_log' => SyncEntityType.auditLog,
    _ => throw FormatException('Unknown sync entity: $value'),
  };

  String get storageValue => switch (this) {
    SyncEntityType.sheet => 'sheet',
    SyncEntityType.round => 'round',
    SyncEntityType.unitStatus => 'unit_status',
    SyncEntityType.reading => 'reading',
    SyncEntityType.sheetContributor => 'sheet_contributor',
    SyncEntityType.auditLog => 'audit_log',
  };
}

extension SyncOperationX on SyncOperation {
  static SyncOperation fromStorage(String value) => switch (value) {
    'insert' => SyncOperation.insert,
    'update' => SyncOperation.update,
    _ => throw FormatException('Unknown sync operation: $value'),
  };
}
