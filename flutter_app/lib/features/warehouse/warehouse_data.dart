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
  final String clean = code.trim();
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
