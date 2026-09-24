import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/source_update_card.dart';
import '../../../data/models/sicatat_types.dart';
import '../warehouse_data.dart';

/// Barang dipesan: purchase order lines that are ordered but not received
/// yet, from the Ellipse "Outstanding Purchase Order" report in Drive.
class WarehousePurchaseOrderScreen extends StatefulWidget {
  const WarehousePurchaseOrderScreen({super.key});

  @override
  State<WarehousePurchaseOrderScreen> createState() =>
      _WarehousePurchaseOrderScreenState();
}

class _WarehousePurchaseOrderScreenState
    extends State<WarehousePurchaseOrderScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _search = TextEditingController();
  List<WarehouseOutstandingPo> _lines = const <WarehouseOutstandingPo>[];
  WarehouseDriveStatus? _status;
  bool _loading = true;
  bool _checking = false;
  bool _overdueOnly = false;

  /// Selected "ordered for" name; empty means every requestor.
  String _requestor = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadStored();
    await _check();
  }

  Future<void> _loadStored() async {
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          _client
              .from('warehouse_outstanding_po')
              .select(WarehouseOutstandingPo.columns)
              // Newest orders first; very old overdue lines sit at the end.
              .order('order_date', ascending: false, nullsFirst: false)
              .order('po_no', ascending: false)
              .order('po_item_no', ascending: true)
              .limit(2000),
          loadWarehouseDriveStatus(_client),
        ],
      );
      final Object? rows = responses[0];
      final Map<WarehouseDriveSource, WarehouseDriveStatus> status =
          responses[1]! as Map<WarehouseDriveSource, WarehouseDriveStatus>;
      if (rows is! List) throw const FormatException('Data PO tidak valid.');
      if (!mounted) return;
      setState(() {
        _lines = rows
            .map(
              (Object? row) =>
                  WarehouseOutstandingPo.fromJson(requireJsonMap(row)),
            )
            .toList(growable: false);
        _status = status[WarehouseDriveSource.outstandingPo];
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = warehouseErrorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _check({bool announce = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final Set<WarehouseDriveSource> changed = await checkWarehouseDrive(
        _client,
        const <WarehouseDriveSource>[WarehouseDriveSource.outstandingPo],
      );
      await _loadStored();
      if (!mounted) return;
      if (announce) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                changed.isEmpty
                    ? 'File Outstanding PO di Drive belum berubah.'
                    : 'Barang dipesan diperbarui dari Drive.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();
    final String query = _search.text.trim().toLowerCase();
    final Map<String, int> requestors = <String, int>{
      for (final WarehouseOutstandingPo line in _lines) line.orderedFor: 0,
    };
    for (final WarehouseOutstandingPo line in _lines) {
      requestors[line.orderedFor] = requestors[line.orderedFor]! + 1;
    }
    // Keep the chosen name selectable even if a Drive refresh dropped it.
    if (_requestor.isNotEmpty) requestors.putIfAbsent(_requestor, () => 0);
    final List<String> names = requestors.keys.toList()
      ..sort((String a, String b) {
        // Warehouse restock sits last; people alphabetically.
        if (a == WarehouseOutstandingPo.restockLabel) return 1;
        if (b == WarehouseOutstandingPo.restockLabel) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final List<WarehouseOutstandingPo> ofRequestor = _requestor.isEmpty
        ? _lines
        : _lines
              .where(
                (WarehouseOutstandingPo line) => line.orderedFor == _requestor,
              )
              .toList(growable: false);
    final List<WarehouseOutstandingPo> visible = ofRequestor
        .where(
          (WarehouseOutstandingPo line) =>
              (!_overdueOnly || line.isOverdue(today)) &&
              (query.isEmpty || line.searchText.contains(query)),
        )
        .toList(growable: false);
    final int overdue = ofRequestor
        .where((WarehouseOutstandingPo line) => line.isOverdue(today))
        .length;
    final WarehouseDriveStatus? status = _status;
    return AppBackScope(
      fallbackRoute: '/warehouse',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/warehouse'),
          title: const Text('Barang dipesan'),
        ),
        body: RefreshIndicator(
          onRefresh: () => _check(announce: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              SourceUpdateCard(
                title: 'Pembaruan Outstanding PO',
                updatedAt: status?.modifiedAt,
                checking: _checking,
                error: status?.error,
                onRefresh: () => _check(announce: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Cari PO, barang, SC, supplier, pemesan',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _requestor,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Pemesan',
                  prefixIcon: Icon(Icons.person_search_rounded),
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua pemesan (${_lines.length})'),
                  ),
                  for (final String name in names)
                    DropdownMenuItem<String>(
                      value: name,
                      child: Text(
                        '$name (${requestors[name]})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (String? value) =>
                    setState(() => _requestor = value ?? ''),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: Text('Semua (${ofRequestor.length})'),
                    selected: !_overdueOnly,
                    onSelected: (_) => setState(() => _overdueOnly = false),
                  ),
                  ChoiceChip(
                    label: Text('Lewat jatuh tempo ($overdue)'),
                    selected: _overdueOnly,
                    onSelected: (_) => setState(() => _overdueOnly = true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Data PO tidak dapat dimuat. $_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                )
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    _lines.isEmpty
                        ? 'Belum ada data Outstanding PO.'
                        : 'Tidak ada PO yang cocok.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.supporting,
                  ),
                )
              else
                for (final WarehouseOutstandingPo line in visible) ...<Widget>[
                  _PurchaseOrderCard(line: line, today: today),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseOrderCard extends StatelessWidget {
  const _PurchaseOrderCard({required this.line, required this.today});

  final WarehouseOutstandingPo line;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final bool overdue = line.isOverdue(today);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: overdue
            ? const BorderSide(color: AppColors.danger, width: 1.2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    line.description ?? 'Tanpa deskripsi',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.greenDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                WarehouseTag(
                  line.isService
                      ? 'Jasa'
                      : 'Sisa ${warehouseNumber(line.qtyOutstanding ?? 0)}'
                            '/${warehouseNumber(line.qtyOrder ?? 0)}',
                  color: AppColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                'PO ${line.poNo}${line.poItemNo == null ? '' : '-${line.poItemNo}'}',
                if (line.itemCode != null) 'SC ${line.itemCode}',
                if (line.partNo != null) line.partNo!,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (line.supplierName != null)
              Text(
                line.supplierName!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(
                  line.requestor == null
                      ? Icons.warehouse_outlined
                      : Icons.person_outline_rounded,
                  size: 16,
                  color: AppColors.greenDark,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    line.requestor == null
                        ? 'Pemesan: ${WarehouseOutstandingPo.restockLabel} '
                              '(restock)'
                        : 'Pemesan: ${line.requestor}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (line.orderDate != null)
                  Text(
                    'Dipesan ${warehouseDateLabel(line.orderDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (line.dueDate != null)
                  WarehouseTag(
                    overdue
                        ? 'Lewat tempo ${warehouseDateLabel(line.dueDate!)}'
                        : 'Tempo ${warehouseDateLabel(line.dueDate!)}',
                    color: overdue ? AppColors.danger : AppColors.green,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
