import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/purchase_requisition_models.dart';
import '../../../data/services/purchase_requisition_service.dart';

class PurchaseRequisitionScreen extends StatefulWidget {
  const PurchaseRequisitionScreen({this.service, super.key});

  final PurchaseRequisitionService? service;

  @override
  State<PurchaseRequisitionScreen> createState() =>
      _PurchaseRequisitionScreenState();
}

class _PurchaseRequisitionScreenState extends State<PurchaseRequisitionScreen> {
  final TextEditingController _searchController = TextEditingController();
  PurchaseRequisitionService? _service;
  PurchaseRequisitionSnapshot? _snapshot;
  List<PurchaseRequisition> _items = const <PurchaseRequisition>[];
  PurchaseRequisitionSort _sort = PurchaseRequisitionSort.arrivalNewest;
  Timer? _debounce;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  PurchaseRequisitionService? _createService() {
    try {
      return PurchaseRequisitionService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  Future<void> _loadInitial({bool synchronizeSource = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service ??= widget.service ?? _createService();
      final PurchaseRequisitionService? service = _service;
      if (service == null) return;
      PurchaseRequisitionSnapshot? snapshot = await service.loadSnapshot();
      if (synchronizeSource || snapshot == null) {
        await service.synchronize();
        snapshot = await service.loadSnapshot();
      }
      final String query = _searchController.text.trim();
      final List<PurchaseRequisition> items = query.isEmpty
          ? const <PurchaseRequisition>[]
          : await service.search(query, sort: _sort);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _items = items;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Data PR belum dapat dimuat. ${_message(error)}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final PurchaseRequisitionService? service = _service;
    if (service == null) return;
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _items = const <PurchaseRequisition>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final List<PurchaseRequisition> items = await service.search(
        _searchController.text,
        sort: _sort,
      );
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _search);
  }

  void _setSort(PurchaseRequisitionSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _search();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('FormatException: ', '');

  @override
  Widget build(BuildContext context) {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: const Text('Data PR'),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Perbarui data PR',
                    onPressed: _loading
                        ? null
                        : () => _loadInitial(synchronizeSource: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, desktop ? 18 : 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (desktop)
                  _DesktopHeader(
                    onRefresh: _loading
                        ? null
                        : () => _loadInitial(synchronizeSource: true),
                  ),
                _SourceCard(snapshot: _snapshot),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText:
                        'Cari No. PR, No. PO, deskripsi, atau referensi alat',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _search();
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                _ResultHeading(
                  count: _items.length,
                  query: _searchController.text,
                  sort: _sort,
                  onSortChanged: _setSort,
                ),
                const SizedBox(height: 8),
                Expanded(child: _content()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_rounded, color: AppColors.orange),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _loadInitial,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_searchController.text.trim().isEmpty) {
      return const Center(child: _SearchPrompt());
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada data PR yang sesuai.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadInitial(synchronizeSource: true),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) =>
            _PurchaseRequisitionCard(
              item: _items[index],
              onTap: () => _showDetail(_items[index]),
            ),
      ),
    );
  }

  Future<void> _showDetail(PurchaseRequisition item) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext context) =>
            _PurchaseRequisitionDetail(item: item),
      );
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.onRefresh});

  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: <Widget>[
        const Icon(
          Icons.request_quote_outlined,
          color: AppColors.green,
          size: 28,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Data PR',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          tooltip: 'Perbarui data PR',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.snapshot});

  final PurchaseRequisitionSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final PurchaseRequisitionSnapshot? snapshot = this.snapshot;
    return Card(
      color: AppColors.mint,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            const CircleAvatar(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.green,
              child: Icon(Icons.inventory_2_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    snapshot == null
                        ? 'Data PR sedang disiapkan'
                        : '${_number(snapshot.rows)} data PR siap dicari',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snapshot?.syncedAt == null
                        ? 'Sumber: spreadsheet PR'
                        : 'Diperbarui ${DateFormat('dd/MM/yyyy HH:mm').format(snapshot!.syncedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading({
    required this.count,
    required this.query,
    required this.sort,
    required this.onSortChanged,
  });

  final int count;
  final String query;
  final PurchaseRequisitionSort sort;
  final ValueChanged<PurchaseRequisitionSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return Text(
        'Cari data PR',
        style: Theme.of(context).textTheme.titleMedium,
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Hasil pencarian',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        PopupMenuButton<PurchaseRequisitionSort>(
          tooltip: 'Urutkan hasil',
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (BuildContext context) => PurchaseRequisitionSort.values
              .map(
                (PurchaseRequisitionSort item) =>
                    PopupMenuItem<PurchaseRequisitionSort>(
                      value: item,
                      child: Row(
                        children: <Widget>[
                          Icon(
                            item == PurchaseRequisitionSort.arrivalNewest
                                ? Icons.south_rounded
                                : Icons.north_rounded,
                            size: 18,
                            color: item == sort
                                ? AppColors.green
                                : AppColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Text(item.label),
                        ],
                      ),
                    ),
              )
              .toList(growable: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.sort_rounded,
                  size: 17,
                  color: AppColors.green,
                ),
                const SizedBox(width: 5),
                Text(
                  count >= 60 ? '60+ hasil' : '$count hasil',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) => const Card(
    color: AppColors.mint,
    child: Padding(
      padding: EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 23,
            backgroundColor: Colors.white,
            foregroundColor: AppColors.green,
            child: Icon(Icons.manage_search_rounded, size: 27),
          ),
          SizedBox(height: 12),
          Text(
            'Mulai pencarian data PR',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Gunakan No. PR, No. PO, deskripsi, atau referensi alat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _PurchaseRequisitionCard extends StatelessWidget {
  const _PurchaseRequisitionCard({required this.item, required this.onTap});

  final PurchaseRequisition item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.mint,
              foregroundColor: AppColors.green,
              child: Icon(Icons.request_quote_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'PR ${item.noPr}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'No. PO: ${_display(item.noPo)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _display(item.description),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.32),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 5,
                      children: <Widget>[
                        _Meta(
                          icon: Icons.precision_manufacturing_outlined,
                          label: _display(item.equipmentReference),
                        ),
                        _Meta(
                          icon: Icons.local_shipping_outlined,
                          label: 'Datang: ${_dateOrDash(item.closedDate)}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 15, color: AppColors.muted),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    ],
  );
}

class _PurchaseRequisitionDetail extends StatelessWidget {
  const _PurchaseRequisitionDetail({required this.item});

  final PurchaseRequisition item;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .76,
      minChildSize: .48,
      maxChildSize: .94,
      builder: (BuildContext context, ScrollController scrollController) =>
          ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 30),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 23,
                      backgroundColor: Color(0x337FFFFF),
                      foregroundColor: Colors.white,
                      child: Icon(Icons.request_quote_outlined),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'PR ${item.noPr}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Detail purchase requisition',
                            style: TextStyle(color: Color(0xC8FFFFFF)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Deskripsi pekerjaan',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                _display(item.description),
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              Text(
                'Informasi PR',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: Column(
                    children: <Widget>[
                      _DetailRow(
                        icon: Icons.tag_outlined,
                        label: 'No. PR',
                        value: item.noPr,
                      ),
                      _DetailRow(
                        icon: Icons.receipt_long_outlined,
                        label: 'No. PO',
                        value: _display(item.noPo),
                      ),
                      _DetailRow(
                        icon: Icons.precision_manufacturing_outlined,
                        label: 'Referensi alat',
                        value: _display(item.equipmentReference),
                      ),
                      _DetailRow(
                        icon: Icons.local_shipping_outlined,
                        label: 'Barang datang',
                        value: _dateOrDash(item.closedDate),
                        helper: 'Close Date pada spreadsheet',
                      ),
                      _DetailRow(
                        icon: Icons.event_outlined,
                        label: 'Tanggal rilis',
                        value: _dateOrDash(item.releaseDate),
                      ),
                      _DetailRow(
                        icon: Icons.info_outline_rounded,
                        label: 'Status',
                        value: _display(item.status),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 19, color: AppColors.green),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (helper != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      helper!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      if (!isLast) const Divider(height: 1),
    ],
  );
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

String _display(String? value) => _has(value) ? value!.trim() : '—';

String _dateOrDash(DateTime? value) => value == null ? '—' : _date(value);

String _date(DateTime value) =>
    DateFormat('dd/MM/yyyy').format(value.toLocal());

String _number(int value) => NumberFormat.decimalPattern('id_ID').format(value);
