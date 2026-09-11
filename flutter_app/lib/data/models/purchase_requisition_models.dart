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
    required this.syncedAt,
  });

  factory PurchaseRequisitionSnapshot.fromJson(JsonMap json) =>
      PurchaseRequisitionSnapshot(
        rows: (json['snapshot_rows'] as num?)?.toInt() ?? 0,
        syncedAt: DateTime.tryParse(json.optionalString('completed_at') ?? ''),
      );

  final int rows;
  final DateTime? syncedAt;
}
