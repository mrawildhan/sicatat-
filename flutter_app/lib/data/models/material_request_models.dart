import 'sicatat_types.dart';

enum MaterialRequestArea { lv, drilling }

extension MaterialRequestAreaX on MaterialRequestArea {
  String get storageValue => switch (this) {
    MaterialRequestArea.lv => 'lv',
    MaterialRequestArea.drilling => 'drilling',
  };

  String get label => switch (this) {
    MaterialRequestArea.lv => 'LV',
    MaterialRequestArea.drilling => 'Drilling',
  };

  static MaterialRequestArea fromStorage(String value) => switch (value) {
    'drilling' => MaterialRequestArea.drilling,
    _ => MaterialRequestArea.lv,
  };
}

enum MaterialNeedType { replacement, newItem, repair }

extension MaterialNeedTypeX on MaterialNeedType {
  String get storageValue => switch (this) {
    MaterialNeedType.replacement => 'replacement',
    MaterialNeedType.newItem => 'new_item',
    MaterialNeedType.repair => 'repair',
  };

  String get label => switch (this) {
    MaterialNeedType.replacement => 'Penggantian barang rusak',
    MaterialNeedType.newItem => 'Barang belum tersedia',
    MaterialNeedType.repair => 'Perbaikan barang',
  };

  static MaterialNeedType fromStorage(String value) => switch (value) {
    'new_item' => MaterialNeedType.newItem,
    'repair' => MaterialNeedType.repair,
    _ => MaterialNeedType.replacement,
  };
}

enum MaterialRequestStatus { submitted, processed, rejected }

extension MaterialRequestStatusX on MaterialRequestStatus {
  String get storageValue => switch (this) {
    MaterialRequestStatus.submitted => 'submitted',
    MaterialRequestStatus.processed => 'processed',
    MaterialRequestStatus.rejected => 'rejected',
  };

  String get label => switch (this) {
    MaterialRequestStatus.submitted => 'Diajukan',
    MaterialRequestStatus.processed => 'Diproses',
    MaterialRequestStatus.rejected => 'Ditolak',
  };

  static MaterialRequestStatus fromStorage(String value) => switch (value) {
    'processed' => MaterialRequestStatus.processed,
    'rejected' => MaterialRequestStatus.rejected,
    _ => MaterialRequestStatus.submitted,
  };
}

class MaterialRequest {
  const MaterialRequest({
    required this.id,
    required this.area,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.needType,
    required this.reason,
    required this.status,
    required this.plannerNote,
    required this.requestedBy,
    required this.createdAt,
    this.requesterName,
    this.processedBy,
    this.processedAt,
  });

  final String id;
  final MaterialRequestArea area;
  final String itemName;
  final num quantity;
  final String unit;
  final MaterialNeedType needType;
  final String reason;
  final MaterialRequestStatus status;
  final String plannerNote;
  final String requestedBy;
  final String? requesterName;
  final String? processedBy;
  final DateTime? processedAt;
  final DateTime createdAt;

  factory MaterialRequest.fromJson(JsonMap json) {
    final Object? rawRequester = json['requester'];
    final JsonMap? requester = rawRequester is Map
        ? requireJsonMap(rawRequester, source: 'pemohon barang')
        : null;
    final Object? rawQuantity = json['quantity'];
    if (rawQuantity is! num) {
      throw const FormatException('Jumlah permintaan barang tidak valid.');
    }
    return MaterialRequest(
      id: json.requiredString('id'),
      area: MaterialRequestAreaX.fromStorage(
        json.requiredString('request_area'),
      ),
      itemName: json.requiredString('item_name'),
      quantity: rawQuantity,
      unit: json.requiredString('unit'),
      needType: MaterialNeedTypeX.fromStorage(json.requiredString('need_type')),
      reason: json.requiredString('reason'),
      status: MaterialRequestStatusX.fromStorage(json.requiredString('status')),
      plannerNote: json.optionalString('planner_note') ?? '',
      requestedBy: json.requiredString('requested_by'),
      requesterName: requester?.optionalString('name'),
      processedBy: json.optionalString('processed_by'),
      processedAt: _dateTime(json.optionalString('processed_at')),
      createdAt: _dateTime(json.requiredString('created_at')) ?? DateTime.now(),
    );
  }

  static DateTime? _dateTime(String? value) =>
      value == null || value.isEmpty ? null : DateTime.tryParse(value);
}
