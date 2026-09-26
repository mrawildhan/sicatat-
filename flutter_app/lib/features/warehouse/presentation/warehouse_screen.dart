import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/export/xlsx_export.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/source_update_card.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../auth/application/current_user_provider.dart';
import '../warehouse_data.dart';

class WarehouseScreen extends ConsumerStatefulWidget {
  const WarehouseScreen({super.key});

  @override
  ConsumerState<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends ConsumerState<WarehouseScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  List<_WarehouseStock> _items = const <_WarehouseStock>[];
  List<_WarehouseTool> _tools = const <_WarehouseTool>[];
  Set<String> _toolsOnLoan = const <String>{};
  String? _siteLabel;
  bool _showTools = false;
  bool _hasSearched = false;
  bool _loading = false;
  bool _syncing = false;
  Map<WarehouseDriveSource, WarehouseDriveStatus> _drive =
      const <WarehouseDriveSource, WarehouseDriveStatus>{};
  bool _checkingDrive = false;

  static const String _stockColumns =
      'item_code,description,warehouse_code,warehouse_name,site_label,uoi,'
      'bin_code,unit_price,stock_on_hand,source_updated_on,synced_at,'
      'stock_source,stock_from,part_no,part_no_2,stock_class,expense_element,'
      'last_received_on,last_issued_on';

  /// Rows shown per search. One extra row is requested to know whether the
  /// keyword matches more than this, so the list can say so.
  static const int _pageSize = 100;
  bool _hasMore = false;

  /// Debounced searches can finish out of order; only the newest may render.
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _refreshDrive();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    if (_search.text.trim().length < 2) {
      // Drop any search still in flight so it cannot refill the list.
      _requestSerial++;
      setState(() {
        _hasSearched = false;
        _hasMore = false;
        _loading = false;
        _items = const <_WarehouseStock>[];
        _tools = const <_WarehouseTool>[];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final String query = _search.text.trim().replaceAll(',', ' ');
    final int serial = ++_requestSerial;
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _hasSearched = false;
          _hasMore = false;
          _items = const <_WarehouseStock>[];
          _tools = const <_WarehouseTool>[];
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final Object stockResponse;
      if (_showTools) {
        dynamic request = _client
            .from('warehouse_tool')
            .select(
              'id,registration_code,tool_name,mnemonic,serial_number,tool_status,'
              'condition_status,condition_note,note,last_log_on,site_label',
            );
        if (query.length >= 2) {
          request = request.or(
            'registration_code.ilike.%$query%,tool_name.ilike.%$query%,mnemonic.ilike.%$query%,serial_number.ilike.%$query%',
          );
        }
        final List<Object?> toolResponses = await Future.wait<Object?>(
          <Future<Object?>>[
            request.order('tool_name', ascending: true).limit(_pageSize + 1)
                as Future<Object?>,
            _client.rpc<Object?>('warehouse_tools_on_loan'),
          ],
        );
        stockResponse = toolResponses[0] as Object;
        final Object? onLoan = toolResponses[1];
        _toolsOnLoan = onLoan is List
            ? onLoan
                  .map(
                    (Object? row) =>
                        requireJsonMap(row).requiredString('tool_id'),
                  )
                  .toSet()
            : const <String>{};
      } else {
        dynamic request = _client.from('warehouse_stock').select(_stockColumns);
        if (_siteLabel != null) {
          request = request.eq('site_label', _siteLabel!);
        }
        if (query.length >= 2) {
          request = request.or(
            'item_code.ilike.%${normalizeStockCode(query)}%,description.ilike.%$query%,'
            'bin_code.ilike.%$query%,part_no.ilike.%$query%',
          );
        }
        final Object found =
            (await request
                    .order('description', ascending: true)
                    .limit(_pageSize + 1))
                as Object;
        // A typed stock code lists its own item first, not somewhere among
        // every code that merely contains those digits.
        final String code = normalizeStockCode(query);
        if (found is List && RegExp(r'^\d+$').hasMatch(code)) {
          dynamic exact = _client
              .from('warehouse_stock')
              .select(_stockColumns)
              .eq('item_code', code);
          if (_siteLabel != null) exact = exact.eq('site_label', _siteLabel!);
          final Object exactRows =
              (await exact.order('site_label', ascending: true)) as Object;
          final List<Object?> first = exactRows is List
              ? exactRows.cast<Object?>()
              : const <Object?>[];
          stockResponse = <Object?>[
            ...first,
            ...found.where(
              (Object? row) => requireJsonMap(row)['item_code'] != code,
            ),
          ];
        } else {
          stockResponse = found;
        }
      }
      if (stockResponse is! List) {
        throw const FormatException('Warehouse returned an invalid response.');
      }
      final List<Object?> allRows = stockResponse.cast<Object?>();
      if (!mounted || serial != _requestSerial) return;
      final List<Object?> warehouseRows = allRows.take(_pageSize).toList();
      setState(() {
        _hasMore = allRows.length > _pageSize;
        if (_showTools) {
          _tools = warehouseRows
              .map(
                (Object? item) => _WarehouseTool.fromJson(requireJsonMap(item)),
              )
              .toList(growable: false);
        } else {
          _items = warehouseRows
              .map(
                (Object? item) =>
                    _WarehouseStock.fromJson(requireJsonMap(item)),
              )
              .toList(growable: false);
        }
        _hasSearched = true;
      });
    } on Object catch (error) {
      if (mounted && serial == _requestSerial) {
        _message('Data Gudang tidak dapat dimuat: $error');
      }
    } finally {
      if (mounted && serial == _requestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final FunctionResponse response = await _client.functions
          .invoke('sync-warehouse-data')
          .timeout(const Duration(seconds: 60));
      final JsonMap data = requireJsonMap(
        response.data,
        source: 'warehouse sync',
      );
      if (data['ok'] != true) {
        throw FormatException(
          data.optionalString('error') ?? 'Sinkronisasi ditolak.',
        );
      }
      await _load();
      await _loadDriveStatus();
      if (mounted) {
        _message(
          data['changed'] == false
              ? 'Data Gudang sudah terbaru.'
              : '${data['stock_rows'] ?? 0} data stok tersinkron.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        _message('Sinkronisasi Gudang terlalu lama. Silakan coba lagi.');
      }
    } on Object catch (error) {
      if (mounted) _message('Sinkronisasi Gudang gagal: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _loadDriveStatus() async {
    try {
      final Map<WarehouseDriveSource, WarehouseDriveStatus> status =
          await loadWarehouseDriveStatus(_client);
      if (mounted) setState(() => _drive = status);
    } on Object {
      // Pencarian Gudang tetap tersedia bila status sumber gagal dimuat.
    }
  }

  /// Shows the stored status, then checks the Drive folder for a newer
  /// Warehouse Inventory or LIST ORDER in the background.
  Future<void> _refreshDrive({bool announce = false}) async {
    await _loadDriveStatus();
    if (_checkingDrive || !mounted) return;
    setState(() => _checkingDrive = true);
    try {
      final Set<WarehouseDriveSource> changed = await checkWarehouseDrive(
        _client,
        const <WarehouseDriveSource>[
          WarehouseDriveSource.inventory,
          WarehouseDriveSource.listOrder,
        ],
      );
      await _loadDriveStatus();
      if (!mounted) return;
      if (changed.contains(WarehouseDriveSource.inventory) && _hasSearched) {
        await _load();
      }
      if (announce && mounted) {
        _message(
          changed.isEmpty
              ? 'File Gudang di Drive belum berubah.'
              : '${changed.map((s) => s.label).join(' dan ')} diperbarui dari Drive.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingDrive = false);
    }
  }

  Widget _driveCard() {
    final WarehouseDriveStatus? inventory =
        _drive[WarehouseDriveSource.inventory];
    final WarehouseDriveStatus? listOrder =
        _drive[WarehouseDriveSource.listOrder];
    final List<String> errors = <String>[
      if (inventory?.error != null) 'Inventory: ${inventory!.error}',
      if (listOrder?.error != null) 'LIST ORDER: ${listOrder!.error}',
    ];
    final DateTime? updatedAt =
        <DateTime?>[
          inventory?.modifiedAt,
          listOrder?.modifiedAt,
        ].whereType<DateTime>().fold<DateTime?>(
          null,
          (DateTime? newest, DateTime time) =>
              newest == null || time.isAfter(newest) ? time : newest,
        );
    return SourceUpdateCard(
      title: 'Pembaruan data Gudang',
      updatedAt: updatedAt,
      checking: _checkingDrive,
      error: errors.isEmpty ? null : errors.join(' · '),
      onRefresh: () => _refreshDrive(announce: true),
    );
  }

  void _showStockDetails(_WarehouseStock item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _WarehouseStockDetails(item: item),
    );
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  /// The stock rows now shown, for Excel (owner request 2026-09-26).
  Future<void> _exportExcel() async {
    final DateTime today = DateTime.now();
    await saveExportFile(
      buildXlsx(
        sheetName: 'Stok gudang',
        title: 'Stok gudang · "${_search.text.trim()}"',
        columns: const <XlsxColumn>[
          XlsxColumn('SC', width: 11),
          XlsxColumn('Barang', width: 44),
          XlsxColumn('Lokasi', width: 12),
          XlsxColumn('Gudang', width: 10),
          XlsxColumn('Stok', width: 8),
          XlsxColumn('UOI', width: 6),
          XlsxColumn('Bin', width: 12),
          XlsxColumn('Part no.', width: 18),
          XlsxColumn('Stok per', width: 12),
          XlsxColumn('Sumber stok', width: 16),
        ],
        rows: <List<Object?>>[
          for (final _WarehouseStock item in _items)
            <Object?>[
              item.itemCode,
              item.description,
              item.siteLabel,
              item.warehouseCode,
              item.stockOnHand,
              item.uoi,
              item.binCode,
              item.partNo,
              DateTime.tryParse(item.sourceUpdatedOn ?? ''),
              item.stockFromSheet ? 'Lembar gudang' : 'Laporan Ellipse',
            ],
        ],
      ),
      fileName:
          'Stok gudang ${today.day.toString().padLeft(2, '0')}-${today.month.toString().padLeft(2, '0')}-${today.year}.xlsx',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);
    final bool canSync = user?.role.canManageWarehouse == true;
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/warehouse',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: () => context.go('/warehouse'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Kembali ke menu Gudang',
                ),
                title: const Text('Cari barang'),
                actions: <Widget>[
                  if (canSync)
                    IconButton(
                      onPressed: _syncing ? null : _sync,
                      icon: _syncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      tooltip: 'Sinkronkan sekarang',
                    ),
                  IconButton(
                    onPressed: _items.isEmpty ? null : _exportExcel,
                    icon: const Icon(Icons.table_view_outlined),
                    tooltip: 'Ekspor hasil ke Excel',
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Muat ulang hasil',
                  ),
                ],
              ),
        body: Column(
          children: <Widget>[
            if (useDesktopHeader) _desktopHeader(canSync),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _driveCard(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _search.clear,
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Hapus pencarian',
                        ),
                  hintText: _showTools
                      ? 'Cari alat, kode registrasi, merek, atau nomor seri'
                      : 'Cari nama item, kode SC, part no, atau lokasi bin',
                ),
              ),
            ),
            _WarehouseModeBar(
              showTools: _showTools,
              onChanged: (bool showTools) {
                setState(() {
                  _showTools = showTools;
                  _siteLabel = null;
                  _search.clear();
                });
                _load();
              },
            ),
            if (!_showTools)
              _WarehouseFilterBar(
                selected: _siteLabel,
                onSelected: (String? value) {
                  setState(() => _siteLabel = value);
                  _load();
                },
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : !_hasSearched
                    ? _WarehouseSearchPrompt(showTools: _showTools)
                    : (_showTools ? _tools.isEmpty : _items.isEmpty)
                    ? const _WarehouseEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        itemCount:
                            (_showTools ? _tools.length : _items.length) +
                            (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, int index) =>
                            index ==
                                (_showTools ? _tools.length : _items.length)
                            ? const _WarehouseMoreResultsNotice(
                                shown: _pageSize,
                              )
                            : _showTools
                            ? _WarehouseToolCard(
                                item: _tools[index],
                                onLoan: _toolsOnLoan.contains(_tools[index].id),
                              )
                            : _WarehouseCard(
                                item: _items[index],
                                onTap: () => _showStockDetails(_items[index]),
                              ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopHeader(bool canSync) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
    child: Row(
      children: <Widget>[
        IconButton(
          onPressed: () => context.go('/warehouse'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali ke menu Gudang',
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Text('Cari barang', style: AppTextStyles.pageTitle),
        ),
        if (canSync)
          IconButton(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sinkronkan sekarang',
          ),
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Muat ulang hasil',
        ),
      ],
    ),
  );
}

class _WarehouseFilterBar extends StatelessWidget {
  const _WarehouseFilterBar({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        ChoiceChip(
          label: const Text('Semua site'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        const SizedBox(width: 8),
        for (final String site in warehouseSearchSites) ...<Widget>[
          ChoiceChip(
            label: Text(site),
            selected: selected == site,
            onSelected: (_) => onSelected(site),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _WarehouseModeBar extends StatelessWidget {
  const _WarehouseModeBar({required this.showTools, required this.onChanged});
  final bool showTools;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
    child: SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('Stok & harga'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.handyman_outlined),
          label: Text('Alat'),
        ),
      ],
      selected: <bool>{showTools},
      onSelectionChanged: (Set<bool> value) => onChanged(value.first),
    ),
  );
}

class _WarehouseSearchPrompt extends StatelessWidget {
  const _WarehouseSearchPrompt({required this.showTools});
  final bool showTools;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(36, 48, 36, 28),
    children: <Widget>[
      Icon(
        showTools ? Icons.handyman_outlined : Icons.manage_search_rounded,
        size: 56,
        color: AppColors.green,
      ),
      const SizedBox(height: 16),
      Text(
        showTools ? 'Cari alat terlebih dahulu' : 'Cari item terlebih dahulu',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      const SizedBox(height: 8),
      Text(
        showTools
            ? 'Masukkan minimal dua huruf dari nama alat, kode registrasi, atau nomor seri.'
            : 'Masukkan minimal dua huruf dari nama item, kode SC, atau lokasi bin. Hasil akan muncul setelah pencarian.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, height: 1.35),
      ),
    ],
  );
}

class _WarehouseEmptyState extends StatelessWidget {
  const _WarehouseEmptyState();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(36),
    children: const <Widget>[
      Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.muted),
      SizedBox(height: 14),
      Text(
        'Data Gudang tidak ditemukan',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      SizedBox(height: 6),
      Text(
        'Coba nama item, kode SC, atau filter lokasi lain.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
    ],
  );
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({required this.item, required this.onTap});
  final _WarehouseStock item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: AppColors.greenDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      'SC ${item.itemCode}',
                      item.warehouseCode == null
                          ? item.siteLabel
                          : '${item.siteLabel} (${item.warehouseCode})',
                      if (item.binCode != null) item.binCode!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _StockPill(stock: item.stockOnHand, uoi: item.uoi),
                if (item.unitPrice != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    _priceLabel(item.unitPrice),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.greenDark,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _WarehouseStockDetails extends StatefulWidget {
  const _WarehouseStockDetails({required this.item});
  final _WarehouseStock item;

  @override
  State<_WarehouseStockDetails> createState() => _WarehouseStockDetailsState();
}

class _WarehouseStockDetailsState extends State<_WarehouseStockDetails> {
  final SupabaseClient _client = Supabase.instance.client;
  List<WarehousePickup>? _pickups;
  List<WarehouseOutstandingPo>? _orders;
  String? _error;

  _WarehouseStock get item => widget.item;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        loadRecentPickups(_client, item.itemCode),
        loadOutstandingPoFor(_client, item.itemCode),
      ]);
      if (!mounted) return;
      setState(() {
        _pickups = results[0] as List<WarehousePickup>;
        _orders = results[1] as List<WarehouseOutstandingPo>;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = warehouseErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            item.description,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            item.fromInventory
                ? 'Detail dari laporan Warehouse Inventory (Ellipse)'
                : 'Detail dari data Gudang di Google Sheet',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _detailRow('Kode SC', item.itemCode),
          _detailRow(
            'Gudang',
            item.warehouseName == null
                ? item.siteLabel
                : '${item.warehouseName}'
                      '${item.warehouseCode == null ? '' : ' (${item.warehouseCode})'}',
          ),
          if (item.partNo != null)
            _detailRow(
              'Part no',
              <String>[
                item.partNo!,
                if (item.partNo2 != null) item.partNo2!,
              ].join(' / '),
            ),
          _detailRow('Lokasi bin', item.binCode ?? 'Belum tercatat'),
          _detailRow('Satuan', item.uoi ?? 'Belum tercatat'),
          _detailRow('Stok tersedia', _stockLabel(item.stockOnHand, item.uoi)),
          // The newest of the two stock sources wins (owner request
          // 2026-09-25); say which one and from which day.
          _detailRow(
            'Stok per',
            '${item.sourceUpdatedOn == null ? 'tanggal belum tercatat' : _formatDate(item.sourceUpdatedOn!)}'
                ' · ${item.stockFromSheet ? 'lembar Warehouse Inventory gudang' : 'laporan Ellipse'}',
          ),
          _detailRow('Harga unit', _priceLabel(item.unitPrice)),
          if (item.stockClass != null)
            _detailRow('Kelas stok', item.stockClass!),
          if (item.expenseElement != null)
            _detailRow('Kategori', item.expenseElement!),
          if (item.fromInventory) ...<Widget>[
            _detailRow(
              'Terakhir diterima',
              item.lastReceivedOn == null
                  ? 'Belum pernah'
                  : _formatDate(item.lastReceivedOn!),
            ),
            _detailRow(
              'Terakhir dikeluarkan',
              item.lastIssuedOn == null
                  ? 'Belum pernah'
                  : _formatDate(item.lastIssuedOn!),
            ),
          ],
          const SizedBox(height: 14),
          ..._ordersSection(),
          const SizedBox(height: 14),
          ..._pickupsSection(),
        ],
      ),
    ),
  );

  List<Widget> _ordersSection() {
    final List<WarehouseOutstandingPo>? orders = _orders;
    final DateTime today = DateTime.now();
    return <Widget>[
      const Text('Sedang dipesan', style: AppTextStyles.sectionTitle),
      const SizedBox(height: 6),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: AppColors.danger))
      else if (orders == null)
        const LinearProgressIndicator()
      else if (orders.isEmpty)
        const Text(
          'Tidak ada PO outstanding untuk kode SC ini.',
          style: AppTextStyles.supporting,
        )
      else
        for (final WarehouseOutstandingPo po in orders)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'PO ${po.poNo} · sisa '
              '${warehouseNumber(po.qtyOutstanding ?? 0)} dari '
              '${warehouseNumber(po.qtyOrder ?? 0)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              <String>[
                if (po.supplierName != null) po.supplierName!,
                if (po.orderDate != null)
                  'Dipesan ${warehouseDateLabel(po.orderDate!)}',
              ].join(' · '),
            ),
            trailing: po.dueDate == null
                ? null
                : WarehouseTag(
                    'Tempo ${warehouseDateLabel(po.dueDate!)}',
                    color: po.isOverdue(today)
                        ? AppColors.danger
                        : AppColors.green,
                  ),
          ),
    ];
  }

  List<Widget> _pickupsSection() {
    final List<WarehousePickup>? pickups = _pickups;
    return <Widget>[
      const Text('5 pengambilan terakhir', style: AppTextStyles.sectionTitle),
      const SizedBox(height: 6),
      if (_error != null)
        const SizedBox.shrink()
      else if (pickups == null)
        const LinearProgressIndicator()
      else if (pickups.isEmpty)
        const Text(
          'Belum ada pengambilan tercatat untuk kode SC ini.',
          style: AppTextStyles.supporting,
        )
      else
        for (final WarehousePickup pickup in pickups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              pickup.userName ?? 'Pengambil tidak tercatat',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              <String>[
                pickup.issuedOn == null
                    ? 'Tanggal tidak tercatat'
                    : warehouseDateLabel(pickup.issuedOn!),
                if (pickup.group != null && pickup.group != pickup.userName)
                  pickup.group!,
                if (pickup.reference != null)
                  pickup.fromSicatat
                      ? 'Job ${pickup.reference}'
                      // IR numbers look like "B16764"; notes such as
                      // "Belum IR" are shown as written.
                      : RegExp(r'^[A-Z]\d{3,}$').hasMatch(pickup.reference!)
                      ? 'IR ${pickup.reference}'
                      : pickup.reference!,
              ].join(' · '),
            ),
            trailing: Text(
              '${pickup.quantity ?? '-'} ${pickup.uoi ?? ''}'.trim(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.greenDark,
              ),
            ),
          ),
    ];
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 142,
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

class _WarehouseToolCard extends StatelessWidget {
  const _WarehouseToolCard({required this.item, required this.onLoan});
  final _WarehouseTool item;
  final bool onLoan;

  @override
  Widget build(BuildContext context) {
    // A SICATAT loan or recorded condition is newer than the sheet status.
    final String? status = onLoan
        ? 'dipinjam'
        : item.conditionStatus ?? item.toolStatus;
    final String? note = item.conditionNote ?? item.note;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.toolName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: <Widget>[
                _chip(Icons.qr_code_rounded, item.registrationCode),
                _chip(Icons.location_on_outlined, item.siteLabel),
                if (status != null)
                  _chip(
                    Icons.verified_outlined,
                    warehouseConditionLabel(status),
                    color: warehouseConditionColor(status),
                  ),
                if (item.mnemonic != null)
                  _chip(Icons.sell_outlined, item.mnemonic!),
                if (item.serialNumber != null)
                  _chip(Icons.numbers_rounded, item.serialNumber!),
              ],
            ),
            if (note != null && note.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(note, style: const TextStyle(color: AppColors.muted)),
            ],
            if (item.lastLogOn != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Catatan alat terakhir ${_formatDate(item.lastLogOn!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color?.withValues(alpha: .12) ?? AppColors.mint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color ?? AppColors.green),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.greenDark,
          ),
        ),
      ],
    ),
  );
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.stock, required this.uoi});
  final num stock;
  final String? uoi;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: stock <= 0
          ? AppColors.danger.withValues(alpha: .10)
          : AppColors.mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '${stock % 1 == 0 ? stock.toInt() : stock} ${uoi ?? ''}'.trim(),
      style: TextStyle(
        fontWeight: FontWeight.w900,
        color: stock <= 0 ? AppColors.danger : AppColors.greenDark,
      ),
    ),
  );
}

class _WarehouseStock {
  const _WarehouseStock({
    required this.itemCode,
    required this.description,
    required this.siteLabel,
    required this.stockOnHand,
    required this.fromInventory,
    this.stockFromSheet = false,
    this.warehouseCode,
    this.warehouseName,
    this.uoi,
    this.binCode,
    this.unitPrice,
    this.sourceUpdatedOn,
    this.syncedAt,
    this.partNo,
    this.partNo2,
    this.stockClass,
    this.expenseElement,
    this.lastReceivedOn,
    this.lastIssuedOn,
  });
  final String itemCode;
  final String description;
  final String siteLabel;
  final num stockOnHand;

  /// From the Warehouse Inventory report rather than the old stock sheet.
  final bool fromInventory;

  /// Stock on hand came from the warehouse's Google Sheet, which was newer
  /// than the Ellipse report.
  final bool stockFromSheet;
  final String? warehouseCode;
  final String? warehouseName;
  final String? uoi;
  final String? binCode;
  final num? unitPrice;
  final String? sourceUpdatedOn;
  final String? syncedAt;
  final String? partNo;
  final String? partNo2;
  final String? stockClass;
  final String? expenseElement;
  final String? lastReceivedOn;
  final String? lastIssuedOn;

  factory _WarehouseStock.fromJson(JsonMap json) => _WarehouseStock(
    itemCode: json.requiredString('item_code'),
    description: json.requiredString('description'),
    siteLabel: json.requiredString('site_label'),
    stockOnHand: json['stock_on_hand'] as num? ?? 0,
    fromInventory: json['stock_source'] == 'inventory',
    stockFromSheet: json['stock_from'] == 'sheet',
    warehouseCode: json.optionalString('warehouse_code'),
    warehouseName: json.optionalString('warehouse_name'),
    uoi: json.optionalString('uoi'),
    binCode: json.optionalString('bin_code'),
    unitPrice: json['unit_price'] as num?,
    sourceUpdatedOn: json.optionalString('source_updated_on'),
    syncedAt: json.optionalString('synced_at'),
    partNo: json.optionalString('part_no'),
    partNo2: json.optionalString('part_no_2'),
    stockClass: json.optionalString('stock_class'),
    expenseElement: json.optionalString('expense_element'),
    lastReceivedOn: json.optionalString('last_received_on'),
    lastIssuedOn: json.optionalString('last_issued_on'),
  );
}

class _WarehouseTool {
  const _WarehouseTool({
    required this.id,
    required this.registrationCode,
    required this.toolName,
    required this.siteLabel,
    this.mnemonic,
    this.serialNumber,
    this.toolStatus,
    this.conditionStatus,
    this.conditionNote,
    this.note,
    this.lastLogOn,
  });
  final String id;
  final String registrationCode;
  final String toolName;
  final String siteLabel;
  final String? mnemonic;
  final String? serialNumber;
  final String? toolStatus;
  final String? conditionStatus;
  final String? conditionNote;
  final String? note;
  final String? lastLogOn;

  factory _WarehouseTool.fromJson(JsonMap json) => _WarehouseTool(
    id: json.requiredString('id'),
    conditionStatus: json.optionalString('condition_status'),
    conditionNote: json.optionalString('condition_note'),
    registrationCode: json.requiredString('registration_code'),
    toolName: json.requiredString('tool_name'),
    siteLabel: json.requiredString('site_label'),
    mnemonic: json.optionalString('mnemonic'),
    serialNumber: json.optionalString('serial_number'),
    toolStatus: json.optionalString('tool_status'),
    note: json.optionalString('note'),
    lastLogOn: json.optionalString('last_log_on'),
  );
}

String _formatDate(String value) {
  final DateTime? date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _priceLabel(num? value) => value == null
    ? 'Harga belum tercatat'
    : 'Harga ${value.toStringAsFixed(2)}';

String _stockLabel(num value, String? uoi) =>
    '${value % 1 == 0 ? value.toInt() : value} ${uoi ?? ''}'.trim();

class _WarehouseMoreResultsNotice extends StatelessWidget {
  const _WarehouseMoreResultsNotice({required this.shown});
  final int shown;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: <Widget>[
        Icon(
          Icons.info_outline_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Menampilkan $shown hasil pertama. Masih ada hasil lain; '
            'perjelas kata kunci atau pilih gudang untuk mempersempit.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
