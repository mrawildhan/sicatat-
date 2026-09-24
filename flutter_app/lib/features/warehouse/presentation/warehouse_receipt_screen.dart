import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../auth/application/current_user_provider.dart';
import '../warehouse_data.dart';

const int _maxReceiptItems = 50;

/// One received line, from SICATAT or from the warehouse Google Sheet
/// (PENERIMAAN), shown the same way in Cek PO and the PO history.
class _ReceivedLine {
  const _ReceivedLine({
    required this.fromSheet,
    this.receivedOn,
    this.poNumber,
    this.deliveryNote,
    this.supplier,
    this.itemNo,
    this.stockCode,
    this.description,
    this.requestor,
    this.quantity,
    this.uoi,
  });

  final bool fromSheet;
  final String? receivedOn;
  final String? poNumber;
  final String? deliveryNote;
  final String? supplier;
  final String? itemNo;
  final String? stockCode;
  final String? description;
  final String? requestor;
  final num? quantity;
  final String? uoi;

  static const String sheetColumns =
      'received_on,po_number,item_code,stock_code,description,quantity,uoi,'
      'delivery_note,supplier,requested_by';

  static const String sicatatColumns =
      'item_no,stock_code,description,requestor,quantity,uoi,'
      'receipt:receipt_id!inner(received_on,po_number,delivery_note,supplier)';

  factory _ReceivedLine.fromSheet(JsonMap json) => _ReceivedLine(
    fromSheet: true,
    receivedOn: _sheetText(json, 'received_on'),
    poNumber: _sheetText(json, 'po_number'),
    deliveryNote: _sheetText(json, 'delivery_note'),
    supplier: _sheetText(json, 'supplier'),
    itemNo: _sheetText(json, 'item_code'),
    stockCode: _sheetText(json, 'stock_code'),
    description: _sheetText(json, 'description'),
    requestor: _sheetText(json, 'requested_by'),
    quantity: json['quantity'] as num?,
    uoi: _sheetText(json, 'uoi'),
  );

  /// The PENERIMAAN sheet repeats its header ("ITEM NAME", "USER") inside
  /// the data; those rows are not deliveries.
  bool get isSheetHeader =>
      fromSheet &&
      ((description ?? '').toUpperCase() == 'ITEM NAME' ||
          (requestor ?? '').toUpperCase() == 'USER');

  factory _ReceivedLine.fromSicatat(JsonMap json) {
    final JsonMap receipt = requireJsonMap(json['receipt'], source: 'receipt');
    return _ReceivedLine(
      fromSheet: false,
      receivedOn: receipt.optionalString('received_on'),
      poNumber: receipt.optionalString('po_number'),
      deliveryNote: receipt.optionalString('delivery_note'),
      supplier: receipt.optionalString('supplier'),
      itemNo: json.optionalString('item_no'),
      stockCode: json.optionalString('stock_code'),
      description: json.optionalString('description'),
      requestor: json.optionalString('requestor'),
      quantity: json['quantity'] as num?,
      uoi: json.optionalString('uoi'),
    );
  }
}

class _PurchaseRequisition {
  const _PurchaseRequisition({
    required this.noPr,
    this.noPo,
    this.description,
    this.status,
    this.releaseDate,
    this.closedDate,
  });

  final String noPr;
  final String? noPo;
  final String? description;
  final String? status;
  final String? releaseDate;
  final String? closedDate;

  factory _PurchaseRequisition.fromJson(JsonMap json) => _PurchaseRequisition(
    noPr: json.requiredString('no_pr'),
    noPo: json.optionalString('no_po'),
    description: json.optionalString('description'),
    status: json.optionalString('status'),
    releaseDate: json.optionalString('release_date'),
    closedDate: json.optionalString('closed_date'),
  );
}

List<_ReceivedLine> _sortedLines(Iterable<_ReceivedLine> lines) =>
    lines.toList()..sort(
      (_ReceivedLine a, _ReceivedLine b) =>
          (b.receivedOn ?? '').compareTo(a.receivedOn ?? ''),
    );

List<_ReceivedLine> _parseLines(Object? response, {required bool sheet}) {
  if (response is! List) {
    throw const FormatException('Data penerimaan tidak valid.');
  }
  return response
      .map((Object? row) => requireJsonMap(row))
      .map(sheet ? _ReceivedLine.fromSheet : _ReceivedLine.fromSicatat)
      .where((_ReceivedLine line) => !line.isSheetHeader)
      .toList(growable: false);
}

/// Sheet cells hold spreadsheet leftovers such as "null", "#N/A" or "-".
String? _sheetText(JsonMap json, String key) {
  final String? value = json.optionalString(key)?.trim();
  if (value == null) return null;
  return const <String>{
        '',
        '-',
        'null',
        'null - null',
        '#n/a',
        '#ref!',
        '#value!',
      }.contains(value.toLowerCase())
      ? null
      : value;
}

/// Escapes a keyword for an ILIKE pattern and PostgREST filter syntax.
String _likeValue(String keyword) =>
    keyword.replaceAll(RegExp(r'[%_,()\\]'), ' ').trim();

class WarehouseReceiptScreen extends StatefulWidget {
  const WarehouseReceiptScreen({super.key});

  @override
  State<WarehouseReceiptScreen> createState() => _WarehouseReceiptScreenState();
}

class _WarehouseReceiptScreenState extends State<WarehouseReceiptScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _historySearch = TextEditingController();
  final TextEditingController _keyword = TextEditingController();
  List<_Receipt> _receipts = const <_Receipt>[];
  bool _loading = true;
  String? _error;

  String _category = 'po';
  bool _checking = false;
  bool _checked = false;
  List<_PurchaseRequisition> _requisitions = const <_PurchaseRequisition>[];
  List<_ReceivedLine> _lines = const <_ReceivedLine>[];
  List<WarehouseStockHit> _stock = const <WarehouseStockHit>[];

  @override
  void initState() {
    super.initState();
    _historySearch.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _historySearch.dispose();
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Object response = await _client
          .from('warehouse_goods_receipt')
          .select(
            'id,received_on,po_number,delivery_note,supplier,note,'
            'site:site_id(name),creator:created_by(name),'
            'items:warehouse_goods_receipt_item(line_no,item_no,stock_code,description,requestor,quantity,uoi)',
          )
          .order('received_on', ascending: false)
          .order('created_at', ascending: false)
          .limit(150);
      if (response is! List) {
        throw const FormatException('Riwayat penerimaan tidak valid.');
      }
      if (!mounted) return;
      setState(() {
        _receipts = response
            .map((Object? row) => _Receipt.fromJson(requireJsonMap(row)))
            .toList(growable: false);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = warehouseErrorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _check() async {
    final String keyword = _likeValue(_keyword.text);
    if (keyword.length < 2) {
      _toast('Masukkan minimal dua karakter.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _checking = true);
    final String pattern = '%$keyword%';
    try {
      final (String sheetColumn, String sicatatColumn) = switch (_category) {
        'requestor' => ('requested_by', 'requestor'),
        'stockcode' => ('stock_code', 'stock_code'),
        _ => ('po_number', 'receipt.po_number'),
      };
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          _client
              .from('warehouse_receipt')
              .select(_ReceivedLine.sheetColumns)
              .ilike(sheetColumn, pattern)
              .order('received_on', ascending: false)
              .limit(200),
          _client
              .from('warehouse_goods_receipt_item')
              .select(_ReceivedLine.sicatatColumns)
              .ilike(sicatatColumn, pattern)
              .limit(200),
          if (_category == 'po')
            _client
                .from('purchase_requisition')
                .select(
                  'no_pr,no_po,description,status,release_date,closed_date',
                )
                .ilike('no_po', pattern)
                .order('release_date', ascending: false)
                .limit(50),
          if (_category == 'stockcode')
            _client
                .from('warehouse_stock')
                .select(
                  'item_code,description,site_label,stock_on_hand,uoi,bin_code',
                )
                .ilike('item_code', pattern)
                .order('item_code', ascending: true)
                .limit(20),
        ],
      );
      if (!mounted) return;
      setState(() {
        _lines = _sortedLines(<_ReceivedLine>[
          ..._parseLines(responses[0], sheet: true),
          ..._parseLines(responses[1], sheet: false),
        ]);
        _requisitions = _category == 'po' && responses[2] is List
            ? (responses[2]! as List<Object?>)
                  .map(
                    (Object? row) =>
                        _PurchaseRequisition.fromJson(requireJsonMap(row)),
                  )
                  .toList(growable: false)
            : const <_PurchaseRequisition>[];
        _stock = _category == 'stockcode' && responses[2] is List
            ? (responses[2]! as List<Object?>)
                  .map(
                    (Object? row) =>
                        WarehouseStockHit.fromJson(requireJsonMap(row)),
                  )
                  .toList(growable: false)
            : const <WarehouseStockHit>[];
        _checked = true;
      });
    } on Object catch (error) {
      if (mounted) _toast('Pencarian gagal: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final String query = _historySearch.text.trim().toLowerCase();
    final List<_Receipt> receipts = _receipts
        .where((_Receipt r) => query.isEmpty || r.searchText.contains(query))
        .toList(growable: false);
    return AppBackScope(
      fallbackRoute: '/warehouse',
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            leading: const AppBackButton(fallbackRoute: '/warehouse'),
            title: const Text('Penerimaan Barang'),
            actions: <Widget>[
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Muat ulang',
              ),
            ],
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              dividerColor: Colors.transparent,
              tabs: <Widget>[
                Tab(text: 'Riwayat'),
                Tab(text: 'Cek PO / PR / stok'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.go('/warehouse/receipts/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Penerimaan baru'),
          ),
          body: TabBarView(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                    child: TextField(
                      controller: _historySearch,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Cari PO, DO, supplier, SC, atau item',
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                          ? WarehouseMessage(
                              icon: Icons.cloud_off_rounded,
                              title: 'Riwayat tidak dapat dimuat',
                              body: _error,
                              onRetry: _load,
                            )
                          : receipts.isEmpty
                          ? WarehouseMessage(
                              icon: Icons.move_to_inbox_outlined,
                              title: _receipts.isEmpty
                                  ? 'Belum ada penerimaan di SICATAT'
                                  : 'Tidak ada yang cocok',
                              body: _receipts.isEmpty
                                  ? 'Penerimaan lama dari Google Sheet bisa dicari di tab Cek PO / PR / stok.'
                                  : null,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                              itemCount: receipts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, int index) =>
                                  _ReceiptCard(receipt: receipts[index]),
                            ),
                    ),
                  ),
                ],
              ),
              _checkTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkTab() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
    children: <Widget>[
      SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'po', label: Text('No. PO')),
          ButtonSegment<String>(value: 'requestor', label: Text('Requestor')),
          ButtonSegment<String>(value: 'stockcode', label: Text('Stock code')),
        ],
        selected: <String>{_category},
        onSelectionChanged: (Set<String> value) => setState(() {
          _category = value.first;
          _checked = false;
        }),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _keyword,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _check(),
        decoration: InputDecoration(
          hintText: switch (_category) {
            'requestor' => 'Nama requestor',
            'stockcode' => 'Kode SC',
            _ => 'Nomor PO',
          },
          suffixIcon: _checking
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _check,
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Cari',
                ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Mencari di penerimaan SICATAT, riwayat penerimaan Google Sheet, Data PR, dan stok Gudang. '
        'Qty outstanding PO belum tersedia karena data baris PO belum ada di sumber mana pun.',
        style: AppTextStyles.supporting,
      ),
      if (_checked) ...<Widget>[
        if (_category == 'stockcode') ...<Widget>[
          const SizedBox(height: 18),
          Text('Stok (${_stock.length})', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 6),
          if (_stock.isEmpty)
            const Text(
              'Kode SC tidak ada di data stok.',
              style: AppTextStyles.supporting,
            ),
          for (final WarehouseStockHit hit in _stock)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(hit.description),
              subtitle: Text(
                <String>[
                  'SC ${hit.itemCode}',
                  hit.siteLabel,
                  if (hit.binCode != null) 'Bin ${hit.binCode}',
                ].join(' · '),
              ),
              trailing: Text(
                '${warehouseNumber(hit.stockOnHand)} ${hit.uoi ?? ''}'.trim(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: hit.stockOnHand <= 0
                      ? AppColors.danger
                      : AppColors.greenDark,
                ),
              ),
            ),
        ],
        if (_category == 'po') ...<Widget>[
          const SizedBox(height: 18),
          Text(
            'Data PR (${_requisitions.length})',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 6),
          if (_requisitions.isEmpty)
            const Text(
              'Tidak ada PR dengan nomor PO ini.',
              style: AppTextStyles.supporting,
            ),
          for (final _PurchaseRequisition pr in _requisitions)
            _RequisitionTile(pr: pr),
        ],
        const SizedBox(height: 18),
        Text(
          'Riwayat penerimaan (${_lines.length})',
          style: AppTextStyles.sectionTitle,
        ),
        const SizedBox(height: 6),
        if (_lines.isEmpty)
          const Text(
            'Belum ada penerimaan yang cocok.',
            style: AppTextStyles.supporting,
          ),
        for (final _ReceivedLine line in _lines) ...<Widget>[
          _ReceivedLineTile(line: line),
          const Divider(height: 1),
        ],
      ],
    ],
  );
}

class _RequisitionTile extends StatelessWidget {
  const _RequisitionTile({required this.pr});

  final _PurchaseRequisition pr;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      pr.description ?? 'PR ${pr.noPr}',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      <String>[
        'PR ${pr.noPr}',
        if (pr.noPo != null) 'PO ${pr.noPo}',
        if (pr.releaseDate != null)
          'Rilis ${warehouseDateText(pr.releaseDate)}',
        if (pr.closedDate != null) 'Tutup ${warehouseDateText(pr.closedDate)}',
      ].join(' · '),
    ),
    trailing: pr.status == null ? null : WarehouseTag(pr.status!),
  );
}

class _ReceivedLineTile extends StatelessWidget {
  const _ReceivedLineTile({required this.line, this.onAdd});

  final _ReceivedLine line;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      line.description ?? 'Tanpa deskripsi',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      <String>[
        if (line.receivedOn != null) warehouseDateText(line.receivedOn),
        if (line.poNumber != null) 'PO ${line.poNumber}',
        if (line.stockCode != null) 'SC ${line.stockCode}',
        if (line.deliveryNote != null) 'DO ${line.deliveryNote}',
        if (line.supplier != null) line.supplier!,
        if (line.requestor != null) 'Req. ${line.requestor}',
        line.fromSheet ? 'Google Sheet' : 'SICATAT',
      ].join(' · '),
    ),
    trailing: onAdd != null
        ? IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Tambahkan sebagai item',
          )
        : Text(
            line.quantity == null
                ? '-'
                : '${warehouseNumber(line.quantity!)} ${line.uoi ?? ''}'.trim(),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
  );
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final _Receipt receipt;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        'PO ${receipt.poNumber}',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.greenDark,
        ),
      ),
      subtitle: Text(
        <String>[
          warehouseDateText(receipt.receivedOn),
          'DO ${receipt.deliveryNote}',
          if (receipt.supplier != null) receipt.supplier!,
          if (receipt.siteName != null) receipt.siteName!,
          '${receipt.items.length} item',
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: <Widget>[
        for (final _ReceiptItem item in receipt.items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item.description),
            subtitle: Text(
              <String>[
                if (item.itemNo != null) 'Item ${item.itemNo}',
                if (item.stockCode != null) 'SC ${item.stockCode}',
                if (item.requestor != null) 'Req. ${item.requestor}',
              ].join(' · '),
            ),
            trailing: Text(
              '${warehouseNumber(item.quantity)} ${item.uoi ?? ''}'.trim(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        if (receipt.note != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(receipt.note!, style: AppTextStyles.supporting),
          ),
        if (receipt.creatorName != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Dicatat oleh ${receipt.creatorName}',
              style: AppTextStyles.supporting,
            ),
          ),
      ],
    ),
  );
}

class _Receipt {
  const _Receipt({
    required this.receivedOn,
    required this.poNumber,
    required this.deliveryNote,
    required this.items,
    this.supplier,
    this.note,
    this.siteName,
    this.creatorName,
  });

  final String receivedOn;
  final String poNumber;
  final String deliveryNote;
  final String? supplier;
  final String? note;
  final String? siteName;
  final String? creatorName;
  final List<_ReceiptItem> items;

  String get searchText => <String?>[
    poNumber,
    deliveryNote,
    supplier,
    for (final _ReceiptItem item in items) ...<String?>[
      item.stockCode,
      item.description,
      item.requestor,
    ],
  ].whereType<String>().join(' ').toLowerCase();

  factory _Receipt.fromJson(JsonMap json) {
    final Object? site = json['site'];
    final Object? creator = json['creator'];
    return _Receipt(
      receivedOn: json.requiredString('received_on'),
      poNumber: json.requiredString('po_number'),
      deliveryNote: json.requiredString('delivery_note'),
      supplier: json.optionalString('supplier'),
      note: json.optionalString('note'),
      siteName: site == null
          ? null
          : requireJsonMap(site).optionalString('name'),
      creatorName: creator == null
          ? null
          : requireJsonMap(creator).optionalString('name'),
      items:
          ((json['items'] as List<Object?>?) ?? const <Object?>[])
              .map((Object? row) => _ReceiptItem.fromJson(requireJsonMap(row)))
              .toList()
            ..sort(
              (_ReceiptItem a, _ReceiptItem b) => a.lineNo.compareTo(b.lineNo),
            ),
    );
  }
}

class _ReceiptItem {
  const _ReceiptItem({
    required this.lineNo,
    required this.description,
    required this.quantity,
    this.itemNo,
    this.stockCode,
    this.requestor,
    this.uoi,
  });

  final int lineNo;
  final String description;
  final num quantity;
  final String? itemNo;
  final String? stockCode;
  final String? requestor;
  final String? uoi;

  factory _ReceiptItem.fromJson(JsonMap json) => _ReceiptItem(
    lineNo: json.requiredInt('line_no'),
    description: json.requiredString('description'),
    quantity: json['quantity'] as num? ?? 0,
    itemNo: json.optionalString('item_no'),
    stockCode: json.optionalString('stock_code'),
    requestor: json.optionalString('requestor'),
    uoi: json.optionalString('uoi'),
  );
}

// Form -----------------------------------------------------------------------

class WarehouseReceiptFormScreen extends ConsumerStatefulWidget {
  const WarehouseReceiptFormScreen({super.key});

  @override
  ConsumerState<WarehouseReceiptFormScreen> createState() =>
      _WarehouseReceiptFormScreenState();
}

class _WarehouseReceiptFormScreenState
    extends ConsumerState<WarehouseReceiptFormScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _po = TextEditingController();
  final TextEditingController _deliveryNote = TextEditingController();
  final TextEditingController _supplier = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_ReceiptLine> _lines = <_ReceiptLine>[];
  List<WarehouseSite> _sites = const <WarehouseSite>[];
  WarehouseSite? _site;
  DateTime _date = warehouseDateOnly(DateTime.now());
  bool _loadingSites = true;
  bool _saving = false;

  bool _poLoading = false;
  String? _poChecked;
  List<_ReceivedLine> _poHistory = const <_ReceivedLine>[];
  List<_PurchaseRequisition> _poRequisitions = const <_PurchaseRequisition>[];

  @override
  void initState() {
    super.initState();
    _addLine();
    _loadSites();
  }

  @override
  void dispose() {
    _po.dispose();
    _deliveryNote.dispose();
    _supplier.dispose();
    _note.dispose();
    for (final _ReceiptLine line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSites() async {
    final AppUser? user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final List<WarehouseSite> sites = await loadWarehouseSites(_client, user);
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _site = sites.isEmpty ? null : sites.first;
        _loadingSites = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadingSites = false);
      _toast('Site gagal dimuat: ${warehouseErrorText(error)}');
    }
  }

  /// Loads what is already known about the PO: earlier deliveries (sheet and
  /// SICATAT), its supplier, and its PR rows.
  Future<void> _checkPo() async {
    final String po = _likeValue(_po.text);
    if (po.isEmpty || po == _poChecked) return;
    setState(() => _poLoading = true);
    try {
      final List<Object?>
      responses = await Future.wait<Object?>(<Future<Object?>>[
        _client
            .from('warehouse_receipt')
            .select(_ReceivedLine.sheetColumns)
            .ilike('po_number', po)
            .limit(200),
        _client
            .from('warehouse_goods_receipt_item')
            .select(_ReceivedLine.sicatatColumns)
            .ilike('receipt.po_number', po)
            .limit(200),
        _client
            .from('purchase_requisition')
            .select('no_pr,no_po,description,status,release_date,closed_date')
            // No. PO in Data PR is free text, e.g. "P52925 SPL / P52932 KTM /".
            .ilike('no_po', '%$po%')
            .limit(30),
      ]);
      final List<_ReceivedLine> history = _sortedLines(<_ReceivedLine>[
        ..._parseLines(responses[0], sheet: true),
        ..._parseLines(responses[1], sheet: false),
      ]);
      final Object? prs = responses[2];
      if (!mounted) return;
      setState(() {
        _poChecked = po;
        _poHistory = history;
        _poRequisitions = prs is List
            ? prs
                  .map(
                    (Object? row) =>
                        _PurchaseRequisition.fromJson(requireJsonMap(row)),
                  )
                  .toList(growable: false)
            : const <_PurchaseRequisition>[];
        if (_supplier.text.trim().isEmpty) {
          final String? supplier = history
              .map((_ReceivedLine l) => l.supplier)
              .firstWhere(
                (String? s) => s != null && s.isNotEmpty,
                orElse: () => null,
              );
          if (supplier != null) _supplier.text = supplier;
        }
      });
    } on Object catch (error) {
      if (mounted) _toast('Data PO gagal dimuat: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _poLoading = false);
    }
  }

  void _addLine([_ReceivedLine? from]) {
    if (_lines.length >= _maxReceiptItems) {
      _toast('Maksimal $_maxReceiptItems item per penerimaan.');
      return;
    }
    // Replace the first untouched blank line instead of adding below it.
    final int blank = _lines.indexWhere((_ReceiptLine l) => l.isBlank);
    final _ReceiptLine line = _ReceiptLine(onLookup: _lookup, from: from);
    setState(() {
      if (from != null && blank >= 0) {
        _lines[blank].dispose();
        _lines[blank] = line;
      } else {
        _lines.add(line);
      }
    });
  }

  Future<void> _lookup(_ReceiptLine line) async {
    final String code = line.stockCode.text.trim();
    if (code.isEmpty || line.description.text.trim().isNotEmpty) return;
    try {
      final WarehouseStockHit? hit = await lookupWarehouseStockCode(
        _client,
        code,
        siteName: _site?.name,
      );
      if (!mounted || hit == null || !_lines.contains(line)) return;
      if (line.description.text.trim().isEmpty) {
        line.description.text = hit.description;
      }
      if (line.uoi.text.trim().isEmpty && hit.uoi != null) {
        line.uoi.text = hit.uoi!;
      }
    } on Object {
      // Deskripsi tetap bisa diketik manual bila pencarian SC gagal.
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final WarehouseSite? site = _site;
    if (site == null) {
      _toast('Pilih site gudang terlebih dahulu.');
      return;
    }
    if (_po.text.trim().isEmpty || _deliveryNote.text.trim().isEmpty) {
      _toast('Nomor PO dan nomor DO wajib diisi.');
      return;
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (int i = 0; i < _lines.length; i++) {
      final _ReceiptLine line = _lines[i];
      if (line.isBlank) continue;
      if (line.description.text.trim().isEmpty) {
        _toast('Deskripsi item ${i + 1} wajib diisi.');
        return;
      }
      final num? quantity = parseWarehouseQuantity(line.quantity.text);
      if (quantity == null) {
        _toast('Qty diterima item ${i + 1} harus lebih dari 0.');
        return;
      }
      items.add(<String, Object?>{
        'item_no': line.itemNo.text.trim(),
        'stock_code': line.stockCode.text.trim(),
        'description': line.description.text.trim(),
        'requestor': line.requestor.text.trim(),
        'quantity': quantity,
        'uoi': line.uoi.text.trim(),
      });
    }
    if (items.isEmpty) {
      _toast('Isi minimal satu item yang diterima.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.rpc<Object?>(
        'warehouse_goods_receipt_create',
        params: <String, Object?>{
          'p_site_id': site.id,
          'p_received_on': warehouseDateParam(_date),
          'p_po_number': _po.text.trim(),
          'p_delivery_note': _deliveryNote.text.trim(),
          'p_supplier': _supplier.text.trim(),
          'p_note': _note.text.trim(),
          'p_items': items,
        },
      );
      if (!mounted) return;
      _toast('Penerimaan ${items.length} item tersimpan.');
      context.go('/warehouse/receipts');
    } on Object catch (error) {
      if (mounted) _toast('Gagal menyimpan: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/warehouse/receipts',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/warehouse/receipts'),
        title: const Text('Penerimaan baru'),
      ),
      body: _loadingSites
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: <Widget>[
                WarehouseSitePicker(
                  sites: _sites,
                  selected: _site,
                  enabled: !_saving,
                  onChanged: (WarehouseSite site) =>
                      setState(() => _site = site),
                ),
                const SizedBox(height: 12),
                WarehouseDateField(
                  label: 'Tanggal terima',
                  value: _date,
                  enabled: !_saving,
                  onChanged: (DateTime value) => setState(() => _date = value),
                ),
                const SizedBox(height: 12),
                Focus(
                  onFocusChange: (bool focused) {
                    if (!focused) _checkPo();
                  },
                  child: TextField(
                    controller: _po,
                    enabled: !_saving,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _checkPo(),
                    decoration: InputDecoration(
                      labelText: 'Nomor PO *',
                      counterText: '',
                      suffixIcon: _poLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: _checkPo,
                              icon: const Icon(Icons.manage_search_rounded),
                              tooltip: 'Muat data PO',
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deliveryNote,
                  enabled: !_saving,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nomor DO / surat jalan *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _supplier,
                  enabled: !_saving,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    helperText: 'Terisi otomatis dari penerimaan PO yang sama bila ada.',
                    counterText: '',
                  ),
                ),
                if (_poChecked != null) _poContext(),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Item diterima (${_lines.length})',
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : () => _addLine(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah item'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (int i = 0; i < _lines.length; i++) ...<Widget>[
                  _ReceiptLineCard(
                    index: i,
                    line: _lines[i],
                    enabled: !_saving,
                    onRemove: _lines.length == 1
                        ? null
                        : () {
                            final _ReceiptLine line = _lines[i];
                            setState(() => _lines.removeAt(i));
                            line.dispose();
                          },
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                TextField(
                  controller: _note,
                  enabled: !_saving,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Catatan'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving || _site == null ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Simpan penerimaan'),
                ),
              ],
            ),
    ),
  );

  Widget _poContext() => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
    decoration: BoxDecoration(
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'PO $_poChecked',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        if (_poRequisitions.isEmpty && _poHistory.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Belum ada data PR atau penerimaan sebelumnya untuk PO ini. Isi item secara manual.',
              style: AppTextStyles.supporting,
            ),
          ),
        for (final _PurchaseRequisition pr in _poRequisitions)
          _RequisitionTile(pr: pr),
        if (_poHistory.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          const Text(
            'Penerimaan sebelumnya — ketuk + untuk memakai item yang sama',
            style: AppTextStyles.supporting,
          ),
          for (final _ReceivedLine line in _poHistory.take(30))
            _ReceivedLineTile(
              line: line,
              onAdd: _saving ? null : () => _addLine(line),
            ),
        ],
      ],
    ),
  );
}

class _ReceiptLine {
  _ReceiptLine({
    required Future<void> Function(_ReceiptLine) onLookup,
    _ReceivedLine? from,
  }) {
    itemNo.text = from?.itemNo ?? '';
    stockCode.text = from?.stockCode ?? '';
    description.text = from?.description ?? '';
    requestor.text = from?.requestor ?? '';
    uoi.text = from?.uoi ?? '';
    _lastCode = stockCode.text;
    stockCode.addListener(() {
      if (stockCode.text == _lastCode) return;
      _lastCode = stockCode.text;
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 500),
        () => onLookup(this),
      );
    });
  }

  final TextEditingController itemNo = TextEditingController();
  final TextEditingController stockCode = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController requestor = TextEditingController();
  final TextEditingController quantity = TextEditingController();
  final TextEditingController uoi = TextEditingController();
  Timer? _debounce;
  String _lastCode = '';

  bool get isBlank => <TextEditingController>[
    itemNo,
    stockCode,
    description,
    requestor,
    quantity,
    uoi,
  ].every((TextEditingController c) => c.text.trim().isEmpty);

  void dispose() {
    _debounce?.cancel();
    for (final TextEditingController c in <TextEditingController>[
      itemNo,
      stockCode,
      description,
      requestor,
      quantity,
      uoi,
    ]) {
      c.dispose();
    }
  }
}

class _ReceiptLineCard extends StatelessWidget {
  const _ReceiptLineCard({
    required this.index,
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  final int index;
  final _ReceiptLine line;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Item ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.green,
                ),
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Hapus item',
              ),
          ],
        ),
        // Keeps the floating field labels clear of the "Item N" heading.
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 104,
                    child: TextField(
                      controller: line.itemNo,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'No. item'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: line.stockCode,
                      enabled: enabled,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Stock code',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: line.description,
                enabled: enabled,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Deskripsi *'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: line.requestor,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Requestor'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: line.quantity,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Qty *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: line.uoi,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'UOI'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
