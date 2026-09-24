import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/app_user.dart';
import '../../data/models/sicatat_types.dart';

/// Sites that run a warehouse. Admin and Supervisor SMG choose one of these;
/// a warehouseman always records for their own site.
const List<String> warehouseSiteNames = <String>['Asamasam', 'Kintap'];

/// Tool conditions shared by registration, return, and condition changes.
/// The stored values are the ones the warehouse Google Sheet already uses.
const List<(String, String)> warehouseToolConditions = <(String, String)>[
  ('ready to use', 'Siap pakai'),
  ('ready with note', 'Siap pakai dengan catatan'),
  ('rusak', 'Rusak'),
  ('hilang', 'Hilang'),
];

/// A loan older than this many days is shown as overdue, as in the warehouse
/// team's original app.
const int warehouseLoanOverdueDays = 3;

String warehouseConditionLabel(String? value) {
  final String key = (value ?? '').trim().toLowerCase();
  if (key == 'dipinjam') return 'Dipinjam';
  for (final (String stored, String label) in warehouseToolConditions) {
    if (stored == key) return label;
  }
  return key.isEmpty ? 'Belum tercatat' : value!.trim();
}

Color warehouseConditionColor(String? value) =>
    switch ((value ?? '').trim().toLowerCase()) {
      'rusak' || 'hilang' => AppColors.danger,
      'dipinjam' => AppColors.orange,
      'ready with note' => const Color(0xFFB7791F),
      _ => AppColors.green,
    };

class WarehouseSite {
  const WarehouseSite({required this.id, required this.name});
  final String id;
  final String name;
}

/// Loads the sites [user] may record transactions for.
Future<List<WarehouseSite>> loadWarehouseSites(
  SupabaseClient client,
  AppUser user,
) async {
  if (user.role == UserRole.warehouseman) {
    final String? id = user.siteId;
    if (id == null) return const <WarehouseSite>[];
    return <WarehouseSite>[
      WarehouseSite(id: id, name: user.siteName ?? 'Site saya'),
    ];
  }
  final Object response = await client
      .from('site')
      .select('id,name')
      .inFilter('name', warehouseSiteNames)
      .eq('is_active', true)
      .order('name', ascending: true);
  if (response is! List) {
    throw const FormatException('Daftar site tidak valid.');
  }
  return response
      .map((Object? row) => requireJsonMap(row))
      .map(
        (JsonMap row) => WarehouseSite(
          id: row.requiredString('id'),
          name: row.requiredString('name'),
        ),
      )
      .toList(growable: false);
}

/// One stock row found for a stock code (SC).
class WarehouseStockHit {
  const WarehouseStockHit({
    required this.itemCode,
    required this.description,
    required this.siteLabel,
    required this.stockOnHand,
    this.uoi,
    this.binCode,
  });

  final String itemCode;
  final String description;
  final String siteLabel;
  final num stockOnHand;
  final String? uoi;
  final String? binCode;

  factory WarehouseStockHit.fromJson(JsonMap json) => WarehouseStockHit(
    itemCode: json.requiredString('item_code'),
    description: json.requiredString('description'),
    siteLabel: json.requiredString('site_label'),
    stockOnHand: json['stock_on_hand'] as num? ?? 0,
    uoi: json.optionalString('uoi'),
    binCode: json.optionalString('bin_code'),
  );
}

/// Finds a stock code, preferring the row of [siteName] when the same SC is
/// stocked in several warehouses.
Future<WarehouseStockHit?> lookupWarehouseStockCode(
  SupabaseClient client,
  String code, {
  String? siteName,
}) async {
  final String clean = normalizeStockCode(code);
  if (clean.isEmpty || clean.contains(RegExp(r'[%_,()]'))) return null;
  final Object response = await client
      .from('warehouse_stock')
      .select('item_code,description,site_label,stock_on_hand,uoi,bin_code')
      .ilike('item_code', clean)
      .order('site_label', ascending: true)
      .limit(5);
  if (response is! List || response.isEmpty) return null;
  final List<WarehouseStockHit> hits = response
      .map((Object? row) => WarehouseStockHit.fromJson(requireJsonMap(row)))
      .toList(growable: false);
  return hits.firstWhere(
    (WarehouseStockHit hit) =>
        siteName != null &&
        hit.siteLabel.toLowerCase() == siteName.toLowerCase(),
    orElse: () => hits.first,
  );
}

/// Site filters of Cari barang, matching `warehouse_stock.site_label`.
const List<String> warehouseSearchSites = <String>[
  'Asamasam',
  'Kintap',
  'NPLCT',
  'Senakin',
  'Satui',
];

/// "000004675" and "4675" are the same stock code.
String normalizeStockCode(String value) {
  final String clean = value.trim().toUpperCase();
  return RegExp(r'^\d+$').hasMatch(clean)
      ? clean.replaceFirst(RegExp(r'^0+(?=\d)'), '')
      : clean;
}

/// A workbook in the owner's Drive folder "Gudang", imported by the Edge
/// Function `sync-warehouse-drive`.
enum WarehouseDriveSource {
  inventory('inventory', 'Warehouse Inventory'),
  listOrder('list_order', 'LIST ORDER'),
  outstandingPo('outstanding_po', 'Outstanding PO');

  const WarehouseDriveSource(this.storage, this.label);

  final String storage;
  final String label;
}

class WarehouseDriveStatus {
  const WarehouseDriveStatus({
    required this.source,
    this.fileName,
    this.reportAt,
    this.rowCount = 0,
    this.modifiedAt,
    this.changedAt,
    this.checkedAt,
    this.error,
  });

  final WarehouseDriveSource source;
  final String? fileName;

  /// Run time printed in the Ellipse report (inventory only).
  final DateTime? reportAt;
  final int rowCount;

  /// Drive "Date modified" of the file (Last-Modified header).
  final DateTime? modifiedAt;

  /// First check that saw the current file content.
  final DateTime? changedAt;
  final DateTime? checkedAt;
  final String? error;

  factory WarehouseDriveStatus.fromJson(
    WarehouseDriveSource source,
    JsonMap json,
  ) {
    DateTime? time(String key) =>
        DateTime.tryParse(json.optionalString(key) ?? '')?.toLocal();
    return WarehouseDriveStatus(
      source: source,
      fileName: json.optionalString('file_name'),
      reportAt: time('report_at'),
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      modifiedAt: time('modified_at'),
      changedAt: time('changed_at'),
      checkedAt: time('checked_at'),
      error: json.optionalString('error'),
    );
  }
}

Future<Map<WarehouseDriveSource, WarehouseDriveStatus>>
loadWarehouseDriveStatus(SupabaseClient client) async {
  final Object response = await client
      .from('warehouse_drive_source')
      .select(
        'source,file_name,report_at,row_count,modified_at,changed_at,'
        'checked_at,error',
      );
  final Map<WarehouseDriveSource, WarehouseDriveStatus> result =
      <WarehouseDriveSource, WarehouseDriveStatus>{};
  if (response is! List) return result;
  for (final Object? row in response) {
    final JsonMap json = requireJsonMap(row);
    for (final WarehouseDriveSource source in WarehouseDriveSource.values) {
      if (source.storage == json['source']) {
        result[source] = WarehouseDriveStatus.fromJson(source, json);
      }
    }
  }
  return result;
}

/// Checks [sources] in the Drive folder, one Edge Function call each (in
/// parallel, so every call stays inside the CPU budget). Returns the sources
/// whose file changed; a failed source is recorded server-side and shows up
/// in [loadWarehouseDriveStatus].
Future<Set<WarehouseDriveSource>> checkWarehouseDrive(
  SupabaseClient client,
  List<WarehouseDriveSource> sources,
) async {
  final List<bool> changed = await Future.wait<bool>(<Future<bool>>[
    for (final WarehouseDriveSource source in sources)
      client.functions
          .invoke(
            'sync-warehouse-drive',
            body: <String, Object?>{'source': source.storage},
          )
          .then((FunctionResponse response) {
            final Object? data = response.data;
            return data is Map && data['ok'] == true && data['changed'] == true;
          })
          .catchError((Object _) => false),
  ]);
  return <WarehouseDriveSource>{
    for (int i = 0; i < sources.length; i++)
      if (changed[i]) sources[i],
  };
}

/// One past pickup of a stock code, from LIST ORDER or from SICATAT.
class WarehousePickup {
  const WarehousePickup({
    required this.fromSicatat,
    this.issuedOn,
    this.userName,
    this.quantity,
    this.uoi,
    this.reference,
    this.group,
  });

  final bool fromSicatat;
  final DateTime? issuedOn;
  final String? userName;
  final String? quantity;
  final String? uoi;

  /// IR number (LIST ORDER) or job number (SICATAT).
  final String? reference;

  /// LIST ORDER sheet (crew or department), or "SICATAT".
  final String? group;
}

/// The latest [limit] pickups of [itemCode], newest first. SICATAT's own
/// pickups are only readable by warehouse managers; others see LIST ORDER.
Future<List<WarehousePickup>> loadRecentPickups(
  SupabaseClient client,
  String itemCode, {
  int limit = 5,
}) async {
  final String code = normalizeStockCode(itemCode);
  final List<Object?> responses = await Future.wait<Object?>(<Future<Object?>>[
    client
        .from('warehouse_issue_history')
        .select(
          'issued_on,user_name,quantity,quantity_text,uoi,ir_no,sheet_name',
        )
        .eq('item_code', code)
        .order('issued_on', ascending: false, nullsFirst: false)
        .order('row_no', ascending: false)
        .limit(limit),
    client
        .from('warehouse_issue_item')
        .select(
          'quantity,uoi,issue:issue_id!inner(issued_on,taken_by,job_number)',
        )
        .eq('item_code', code)
        .limit(limit)
        .then<Object?>((Object? value) => value)
        .catchError((Object _) => const <Object?>[]),
  ]);
  final List<WarehousePickup> pickups = <WarehousePickup>[];
  final Object? sheet = responses[0];
  if (sheet is List) {
    for (final Object? row in sheet) {
      final JsonMap json = requireJsonMap(row);
      final num? quantity = json['quantity'] as num?;
      pickups.add(
        WarehousePickup(
          fromSicatat: false,
          issuedOn: DateTime.tryParse(json.optionalString('issued_on') ?? ''),
          userName: json.optionalString('user_name'),
          quantity: quantity == null
              ? json.optionalString('quantity_text')
              : warehouseNumber(quantity),
          uoi: json.optionalString('uoi'),
          reference: json.optionalString('ir_no'),
          group: json.optionalString('sheet_name'),
        ),
      );
    }
  }
  final Object? own = responses[1];
  if (own is List) {
    for (final Object? row in own) {
      final JsonMap json = requireJsonMap(row);
      final JsonMap issue = requireJsonMap(json['issue']);
      final num? quantity = json['quantity'] as num?;
      pickups.add(
        WarehousePickup(
          fromSicatat: true,
          issuedOn: DateTime.tryParse(issue.optionalString('issued_on') ?? ''),
          userName: issue.optionalString('taken_by'),
          quantity: quantity == null ? null : warehouseNumber(quantity),
          uoi: json.optionalString('uoi'),
          reference: issue.optionalString('job_number'),
          group: 'SICATAT',
        ),
      );
    }
  }
  pickups.sort((WarehousePickup a, WarehousePickup b) {
    final DateTime? x = a.issuedOn;
    final DateTime? y = b.issuedOn;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return pickups.take(limit).toList(growable: false);
}

/// A purchase order line that has been ordered but not fully received.
class WarehouseOutstandingPo {
  const WarehouseOutstandingPo({
    required this.poNo,
    this.poItemNo,
    this.supplierName,
    this.itemCode,
    this.requestor,
    this.description,
    this.partNo,
    this.qtyOrder,
    this.qtyOutstanding,
    this.orderDate,
    this.dueDate,
  });

  static const String columns =
      'po_no,po_item_no,supplier_name,item_code,requestor,description,'
      'part_no,qty_order,qty_outstanding,order_date,due_date';

  final String poNo;
  final String? poItemNo;
  final String? supplierName;
  final String? itemCode;
  final String? requestor;
  final String? description;
  final String? partNo;
  final num? qtyOrder;
  final num? qtyOutstanding;
  final DateTime? orderDate;
  final DateTime? dueDate;

  /// Service POs are ordered with quantity 0.
  bool get isService => (qtyOrder ?? 0) == 0;

  bool isOverdue(DateTime today) =>
      dueDate != null && dueDate!.isBefore(warehouseDateOnly(today));

  /// Label shown for lines without a requestor: in the Ellipse report these
  /// are exactly the stock-coded lines, i.e. warehouse restock orders.
  static const String restockLabel = 'Stok gudang';

  /// Who the line was ordered for: the requestor, or the warehouse itself.
  String get orderedFor => requestor ?? restockLabel;

  String get searchText => <String?>[
    poNo,
    supplierName,
    itemCode,
    orderedFor,
    description,
    partNo,
  ].whereType<String>().join(' ').toLowerCase();

  factory WarehouseOutstandingPo.fromJson(JsonMap json) =>
      WarehouseOutstandingPo(
        poNo: json.requiredString('po_no'),
        poItemNo: json.optionalString('po_item_no'),
        supplierName: json.optionalString('supplier_name'),
        itemCode: json.optionalString('item_code'),
        requestor: json.optionalString('requestor'),
        description: json.optionalString('description'),
        partNo: json.optionalString('part_no'),
        qtyOrder: json['qty_order'] as num?,
        qtyOutstanding: json['qty_outstanding'] as num?,
        orderDate: DateTime.tryParse(json.optionalString('order_date') ?? ''),
        dueDate: DateTime.tryParse(json.optionalString('due_date') ?? ''),
      );
}

Future<List<WarehouseOutstandingPo>> loadOutstandingPoFor(
  SupabaseClient client,
  String itemCode,
) async {
  final Object response = await client
      .from('warehouse_outstanding_po')
      .select(WarehouseOutstandingPo.columns)
      .eq('item_code', normalizeStockCode(itemCode))
      .order('due_date', ascending: true);
  if (response is! List) return const <WarehouseOutstandingPo>[];
  return response
      .map(
        (Object? row) => WarehouseOutstandingPo.fromJson(requireJsonMap(row)),
      )
      .toList(growable: false);
}

String warehouseErrorText(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is FormatException) return error.message;
  return '$error';
}

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

DateTime warehouseDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String warehouseDateLabel(DateTime value) =>
    '${value.day} ${_monthNames[value.month - 1]} ${value.year}';

String warehouseDateText(String? value) {
  final DateTime? date = value == null ? null : DateTime.tryParse(value);
  return date == null ? (value ?? '-') : warehouseDateLabel(date.toLocal());
}

String warehouseDateParam(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String warehouseNumber(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();

/// Parses a quantity typed with either a decimal comma or point.
num? parseWarehouseQuantity(String value) {
  final num? parsed = num.tryParse(value.trim().replaceAll(',', '.'));
  return parsed == null || parsed <= 0 ? null : parsed;
}

/// Whole days between [loanedOn] and today.
int warehouseLoanAgeDays(DateTime loanedOn, {DateTime? now}) =>
    warehouseDateOnly(now ?? DateTime.now())
        .difference(warehouseDateOnly(loanedOn))
        .inDays;

/// Site selector shown only when the user may record for several sites.
class WarehouseSitePicker extends StatelessWidget {
  const WarehouseSitePicker({
    required this.sites,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<WarehouseSite> sites;
  final WarehouseSite? selected;
  final ValueChanged<WarehouseSite> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (sites.length <= 1) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Site gudang'),
        child: Text(
          selected?.name ?? 'Akun belum punya site',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: selected?.id,
      decoration: const InputDecoration(labelText: 'Site gudang'),
      items: <DropdownMenuItem<String>>[
        for (final WarehouseSite site in sites)
          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
      ],
      onChanged: enabled
          ? (String? id) {
              if (id == null) return;
              onChanged(sites.firstWhere((WarehouseSite s) => s.id == id));
            }
          : null,
    );
  }
}

/// Date field that opens a date picker; used by every warehouse form.
class WarehouseDateField extends StatelessWidget {
  const WarehouseDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: !enabled
        ? null
        : () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              helpText: label,
            );
            if (picked != null) onChanged(warehouseDateOnly(picked));
          },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.event_rounded),
      ),
      child: Text(
        warehouseDateLabel(value),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// Small rounded label used for statuses and codes in warehouse lists.
class WarehouseTag extends StatelessWidget {
  const WarehouseTag(this.label, {this.color = AppColors.green, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

/// Centered message for empty lists and load errors.
class WarehouseMessage extends StatelessWidget {
  const WarehouseMessage({
    required this.icon,
    required this.title,
    this.body,
    this.onRetry,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(36, 48, 36, 28),
    children: <Widget>[
      Icon(icon, size: 52, color: AppColors.muted),
      const SizedBox(height: 14),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      if (body != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(
          body!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.35),
        ),
      ],
      if (onRetry != null) ...<Widget>[
        const SizedBox(height: 12),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ),
      ],
    ],
  );
}

/// Label/value row used in detail sheets.
class WarehouseDetailRow extends StatelessWidget {
  const WarehouseDetailRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
