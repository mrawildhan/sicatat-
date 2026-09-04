import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../auth/application/current_user_provider.dart';

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
  String? _warehouseCode;
  bool _showTools = false;
  bool _hasSearched = false;
  bool _loading = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
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
      setState(() {
        _hasSearched = false;
        _items = const <_WarehouseStock>[];
        _tools = const <_WarehouseTool>[];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final String query = _search.text.trim().replaceAll(',', ' ');
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _hasSearched = false;
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
              'registration_code,tool_name,mnemonic,serial_number,tool_status,note,last_log_on,site_label',
            );
        if (query.length >= 2) {
          request = request.or(
            'registration_code.ilike.%$query%,tool_name.ilike.%$query%,mnemonic.ilike.%$query%,serial_number.ilike.%$query%',
          );
        }
        stockResponse = (await request.order('tool_name').limit(100)) as Object;
      } else {
        dynamic request = _client
            .from('warehouse_stock')
            .select(
              'item_code,description,warehouse_code,site_label,uoi,bin_code,unit_price,stock_on_hand,source_updated_on,synced_at',
            );
        if (_warehouseCode != null) {
          request = request.eq('warehouse_code', _warehouseCode!);
        }
        if (query.length >= 2) {
          request = request.or(
            'item_code.ilike.%$query%,description.ilike.%$query%,bin_code.ilike.%$query%',
          );
        }
        stockResponse =
            (await request.order('description').limit(100)) as Object;
      }
      if (stockResponse is! List) {
        throw const FormatException('Warehouse returned an invalid response.');
      }
      final List<Object?> warehouseRows = stockResponse.cast<Object?>();
      if (!mounted) return;
      setState(() {
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
      if (mounted) _message('Data Gudang tidak dapat dimuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      if (mounted) {
        _message('${data['stock_rows'] ?? 0} data stok tersinkron.');
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

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);
    final bool canSync = user?.role.canManageWarehouse == true;
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Kembali ke menu',
                ),
                title: const Text('Gudang'),
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
                      tooltip: 'Sinkronkan Google Sheets',
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
                      : 'Cari nama item, kode SC, atau lokasi bin',
                ),
              ),
            ),
            _WarehouseModeBar(
              showTools: _showTools,
              onChanged: (bool showTools) {
                setState(() {
                  _showTools = showTools;
                  _warehouseCode = null;
                  _search.clear();
                });
                _load();
              },
            ),
            if (!_showTools)
              _WarehouseFilterBar(
                selected: _warehouseCode,
                onSelected: (String? value) {
                  setState(() => _warehouseCode = value);
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
                        itemCount: _showTools ? _tools.length : _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, int index) => _showTools
                            ? _WarehouseToolCard(item: _tools[index])
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
        const Expanded(
          child: Text(
            'Gudang',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
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
            tooltip: 'Sinkronkan Google Sheets',
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
        for (final (String code, String label) in <(String, String)>[
          ('AMWH', 'Asamasam'),
          ('KMWH', 'Kintap'),
          ('MAIN', 'Utama'),
        ]) ...<Widget>[
          ChoiceChip(
            label: Text(label),
            selected: selected == code,
            onSelected: (_) => onSelected(code),
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
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
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
        'Coba nama item, kode SC, atau filter site lain.',
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
                    'SC ${item.itemCode} · ${item.siteLabel}${item.binCode == null ? '' : ' · ${item.binCode}'}',
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

class _WarehouseStockDetails extends StatelessWidget {
  const _WarehouseStockDetails({required this.item});
  final _WarehouseStock item;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const Text(
            'Detail dari data Warehouse Google Sheet',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _detailRow('Kode SC', item.itemCode),
          _detailRow('Site', item.siteLabel),
          _detailRow('Lokasi bin', item.binCode ?? 'Belum tercatat'),
          _detailRow('Satuan', item.uoi ?? 'Belum tercatat'),
          _detailRow('Stok tersedia', _stockLabel(item.stockOnHand, item.uoi)),
          _detailRow('Harga unit', _priceLabel(item.unitPrice)),
          _detailRow(
            'Tanggal update sheet',
            item.sourceUpdatedOn == null
                ? 'Belum tercatat'
                : _formatDate(item.sourceUpdatedOn!),
          ),
          _detailRow(
            'Terakhir tersinkron',
            item.syncedAt == null
                ? 'Belum tercatat'
                : _formatDate(item.syncedAt!),
          ),
        ],
      ),
    ),
  );

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
  const _WarehouseToolCard({required this.item});
  final _WarehouseTool item;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.toolName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: <Widget>[
              _chip(Icons.qr_code_rounded, item.registrationCode),
              _chip(Icons.location_on_outlined, item.siteLabel),
              if (item.toolStatus != null)
                _chip(Icons.verified_outlined, item.toolStatus!),
              if (item.mnemonic != null)
                _chip(Icons.sell_outlined, item.mnemonic!),
              if (item.serialNumber != null)
                _chip(Icons.numbers_rounded, item.serialNumber!),
            ],
          ),
          if (item.note != null && item.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(item.note!, style: const TextStyle(color: AppColors.muted)),
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

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: AppColors.green),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.greenDark,
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
    this.uoi,
    this.binCode,
    this.unitPrice,
    this.sourceUpdatedOn,
    this.syncedAt,
  });
  final String itemCode;
  final String description;
  final String siteLabel;
  final num stockOnHand;
  final String? uoi;
  final String? binCode;
  final num? unitPrice;
  final String? sourceUpdatedOn;
  final String? syncedAt;

  factory _WarehouseStock.fromJson(JsonMap json) => _WarehouseStock(
    itemCode: json.requiredString('item_code'),
    description: json.requiredString('description'),
    siteLabel: json.requiredString('site_label'),
    stockOnHand: json['stock_on_hand'] as num? ?? 0,
    uoi: json.optionalString('uoi'),
    binCode: json.optionalString('bin_code'),
    unitPrice: json['unit_price'] as num?,
    sourceUpdatedOn: json.optionalString('source_updated_on'),
    syncedAt: json.optionalString('synced_at'),
  );
}

class _WarehouseTool {
  const _WarehouseTool({
    required this.registrationCode,
    required this.toolName,
    required this.siteLabel,
    this.mnemonic,
    this.serialNumber,
    this.toolStatus,
    this.note,
    this.lastLogOn,
  });
  final String registrationCode;
  final String toolName;
  final String siteLabel;
  final String? mnemonic;
  final String? serialNumber;
  final String? toolStatus;
  final String? note;
  final String? lastLogOn;

  factory _WarehouseTool.fromJson(JsonMap json) => _WarehouseTool(
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
