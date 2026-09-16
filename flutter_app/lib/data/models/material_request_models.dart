import 'sicatat_types.dart';

enum MaterialRequestArea { lv, cop, drilling }

extension MaterialRequestAreaX on MaterialRequestArea {
  String get storageValue => switch (this) {
    MaterialRequestArea.lv => 'lv',
    MaterialRequestArea.cop => 'cop',
    MaterialRequestArea.drilling => 'drilling',
  };

  String get label => switch (this) {
    MaterialRequestArea.lv => 'LV',
    MaterialRequestArea.cop => 'COP',
    MaterialRequestArea.drilling => 'Drilling',
  };

  static MaterialRequestArea fromStorage(String value) => switch (value) {
    'cop' => MaterialRequestArea.cop,
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

/// Product links as people actually paste them.
///
/// Crew copy addresses that start with `www.` or nothing at all, so the app
/// completes the scheme instead of refusing the link. Storage always holds a
/// full http(s) address, which is what the check constraint and the launcher
/// expect.
class MaterialRequestProductLink {
  const MaterialRequestProductLink._();

  static const String invalidMessage =
      'Link tidak dikenali. Salin alamat lengkap, misalnya www.tokopedia.com/...';

  /// Returns the address to store, or null when nothing usable was typed.
  static String? normalize(String? raw) {
    final String trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return null;
    final String withScheme =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)
        ? trimmed
        : 'https://$trimmed';
    final Uri? parsed = Uri.tryParse(withScheme);
    if (parsed == null ||
        !parsed.hasAuthority ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        RegExp(r'\s').hasMatch(withScheme) ||
        // A bare word is a typo, not an address.
        !parsed.host.contains('.')) {
      return null;
    }
    return withScheme;
  }

  /// Validation message for a form field, or null when the value is fine.
  static String? validate(String? raw) {
    if ((raw ?? '').trim().isEmpty) return null;
    return normalize(raw) == null ? invalidMessage : null;
  }
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
    this.productUrl,
    this.photoPath,
    this.photoMime,
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

  /// Optional link to the exact product the requester means, so the planner
  /// does not have to guess from the item name.
  final String? productUrl;

  /// Optional picture of the item, stored in `material-request-photos`.
  final String? photoPath;
  final String? photoMime;
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
      productUrl: _trimmedOrNull(json.optionalString('product_url')),
      photoPath: _trimmedOrNull(json.optionalString('photo_path')),
      photoMime: _trimmedOrNull(json.optionalString('photo_mime')),
      status: MaterialRequestStatusX.fromStorage(json.requiredString('status')),
      plannerNote: json.optionalString('planner_note') ?? '',
      requestedBy: json.requiredString('requested_by'),
      requesterName: requester?.optionalString('name'),
      processedBy: json.optionalString('processed_by'),
      processedAt: _dateTime(json.optionalString('processed_at')),
      createdAt: _dateTime(json.requiredString('created_at')) ?? DateTime.now(),
    );
  }

  static String? _trimmedOrNull(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _dateTime(String? value) =>
      value == null || value.isEmpty ? null : DateTime.tryParse(value);
}
