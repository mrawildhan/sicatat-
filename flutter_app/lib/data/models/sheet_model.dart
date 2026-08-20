import 'sicatat_types.dart';

enum SheetStatus { draft, submitted, submittedIncomplete, verified, returned }

enum SheetSyncStatus { pending, synced, conflict }

class CreateSheetCommand {
  const CreateSheetCommand({
    required this.date,
    required this.shiftId,
    required this.teamId,
    required this.moduleId,
    required this.templateVersion,
    required this.createdBy,
  });

  final DateTime date;
  final String shiftId;
  final String teamId;
  final String moduleId;
  final String templateVersion;
  final String createdBy;
}

class SheetModel {
  const SheetModel({
    required this.id,
    required this.clientUuid,
    required this.date,
    required this.shiftId,
    required this.teamId,
    required this.moduleId,
    required this.templateVersion,
    required this.createdBy,
    required this.createdAt,
    required this.status,
    required this.syncStatus,
    this.shiftName,
    this.teamName,
    this.incompleteSides = 0,
  });

  final String id;
  final String clientUuid;
  final DateTime date;
  final String shiftId;
  final String teamId;
  final String moduleId;
  final String templateVersion;
  final String createdBy;
  final DateTime createdAt;
  final SheetStatus status;
  final SheetSyncStatus syncStatus;
  final String? shiftName;
  final String? teamName;
  final int incompleteSides;

  factory SheetModel.fromLocalRow(JsonMap row) {
    return SheetModel(
      id: row.requiredString('id'),
      clientUuid: row.requiredString('client_uuid'),
      date: DateTime.parse(row.requiredString('tanggal')),
      shiftId: row.requiredString('shift_id'),
      teamId: row.requiredString('team_id'),
      moduleId: row.requiredString('module_id'),
      templateVersion: row.requiredString('template_version'),
      createdBy: row.requiredString('created_by'),
      createdAt: DateTime.parse(row.requiredString('created_at')),
      status: SheetStatusX.fromStorage(row.requiredString('status')),
      syncStatus: SheetSyncStatusX.fromStorage(
        row.requiredString('sync_status'),
      ),
    );
  }

  factory SheetModel.fromRemoteRow(JsonMap row) {
    return SheetModel(
      id: row.requiredString('id'),
      clientUuid: row.requiredString('client_uuid'),
      date: DateTime.parse(row.requiredString('tanggal')),
      shiftId: row.requiredString('shift_id'),
      teamId: row.requiredString('team_id'),
      moduleId: row.requiredString('module_id'),
      templateVersion: row.requiredString('template_version'),
      createdBy: row.requiredString('created_by'),
      createdAt: DateTime.parse(row.requiredString('created_at')),
      status: SheetStatusX.fromStorage(row.requiredString('status')),
      syncStatus: SheetSyncStatus.synced,
      shiftName: _relatedName(row['shift']),
      teamName: _relatedName(row['team']),
    );
  }

  static String? _relatedName(Object? value) {
    if (value == null) return null;
    return requireJsonMap(value, source: 'relasi sheet').optionalString('name');
  }
}

class SheetAuditEvent {
  const SheetAuditEvent({
    required this.id,
    required this.action,
    required this.changedAt,
    this.changedBy,
    this.note,
  });

  final String id;
  final String action;
  final DateTime changedAt;
  final String? changedBy;
  final String? note;

  factory SheetAuditEvent.fromLocalRow(JsonMap row) => SheetAuditEvent(
    id: row.requiredString('id'),
    action: row.requiredString('action'),
    changedAt: DateTime.parse(row.requiredString('changed_at')).toLocal(),
    changedBy: row.optionalString('changed_by'),
    note: row.optionalString('new_value'),
  );

  factory SheetAuditEvent.fromRemoteRow(JsonMap row) => SheetAuditEvent(
    id: row.requiredString('id'),
    action: row.requiredString('action'),
    changedAt: DateTime.parse(row.requiredString('changed_at')).toLocal(),
    changedBy: row.optionalString('changed_by'),
    note: row['new_value']?.toString(),
  );
}

extension SheetStatusX on SheetStatus {
  static SheetStatus fromStorage(String value) => switch (value) {
    'draft' => SheetStatus.draft,
    'submitted' => SheetStatus.submitted,
    'submitted_incomplete' => SheetStatus.submittedIncomplete,
    'verified' => SheetStatus.verified,
    'returned' => SheetStatus.returned,
    _ => throw FormatException('Unknown sheet status: $value'),
  };

  String get storageValue => switch (this) {
    SheetStatus.draft => 'draft',
    SheetStatus.submitted => 'submitted',
    SheetStatus.submittedIncomplete => 'submitted_incomplete',
    SheetStatus.verified => 'verified',
    SheetStatus.returned => 'returned',
  };
}

extension SheetSyncStatusX on SheetSyncStatus {
  static SheetSyncStatus fromStorage(String value) => switch (value) {
    'pending' => SheetSyncStatus.pending,
    'synced' => SheetSyncStatus.synced,
    'conflict' => SheetSyncStatus.conflict,
    _ => throw FormatException('Unknown sync status: $value'),
  };
}
