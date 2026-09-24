import 'sicatat_types.dart';

enum PurchaseRequisitionSort {
  prNewest,
  prOldest;

  String get label => switch (this) {
    PurchaseRequisitionSort.prNewest => 'No. PR terbaru',
    PurchaseRequisitionSort.prOldest => 'No. PR terlama',
  };

  bool get ascending => this == PurchaseRequisitionSort.prOldest;
}

class PurchaseRequisition {
  const PurchaseRequisition({
    required this.id,
    required this.noPr,
    required this.noPo,
    required this.description,
    required this.equipmentReference,
    required this.closedDate,
    required this.releaseDate,
    required this.status,
  });

  factory PurchaseRequisition.fromJson(JsonMap json) => PurchaseRequisition(
    id: json.requiredString('id'),
    noPr: json.requiredString('no_pr'),
    noPo: json.optionalString('no_po'),
    description: json.optionalString('description'),
    equipmentReference: json.optionalString('equip_ref'),
    closedDate: DateTime.tryParse(json.optionalString('closed_date') ?? ''),
    releaseDate: DateTime.tryParse(json.optionalString('release_date') ?? ''),
    status: json.optionalString('status'),
  );

  final String id;
  final String noPr;
  final String? noPo;
  final String? description;
  final String? equipmentReference;
  final DateTime? closedDate;
  final DateTime? releaseDate;
  final String? status;
}

class PurchaseRequisitionSnapshot {
  const PurchaseRequisitionSnapshot({
    required this.rows,
    required this.checkedAt,
    required this.changedAt,
    this.lastError,
  });

  /// [newestLogs] are `purchase_requisition_sync_log` rows, newest first;
  /// every check logs one, changed or not. [changedAt] comes from the PR rows
  /// themselves, which are only rewritten when the spreadsheet changed.
  /// Returns null before the first import.
  static PurchaseRequisitionSnapshot? fromLog(
    List<JsonMap> newestLogs, {
    required DateTime? changedAt,
  }) {
    final JsonMap? completed = newestLogs
        .where((JsonMap row) => row['status'] == 'completed')
        .firstOrNull;
    if (completed == null) return null;
    final JsonMap newest = newestLogs.first;
    return PurchaseRequisitionSnapshot(
      rows: (completed['snapshot_rows'] as num?)?.toInt() ?? 0,
      checkedAt: DateTime.tryParse(
        completed.optionalString('completed_at') ?? '',
      )?.toLocal(),
      changedAt: changedAt?.toLocal(),
      lastError: newest['status'] == 'failed'
          ? newest.optionalString('detail') ?? 'Pemeriksaan gagal.'
          : null,
    );
  }

  final int rows;

  /// Last successful check of the spreadsheet, changed or not.
  final DateTime? checkedAt;

  /// When the spreadsheet content now in SICATAT was first imported. Only as
  /// precise as the checks: an edit shows up at the first check after it.
  final DateTime? changedAt;

  /// Set when the newest check failed; the older snapshot is still shown.
  final String? lastError;
}
