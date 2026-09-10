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
      final List<PurchaseRequisition> items = await service.search(
        _searchController.text,
      );
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
    setState(() => _loading = true);
    try {
      final List<PurchaseRequisition> items = await service.search(
        _searchController.text,
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
  const _ResultHeading({required this.count, required this.query});

  final int count;
  final String query;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(
        query.trim().isEmpty ? 'PR terbaru' : 'Hasil pencarian',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const Spacer(),
      Text(
        count >= 60 ? '60+' : '$count hasil',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ],
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
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CircleAvatar(
              radius: 20,
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
                    item.noPr,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (_has(item.noPo)) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      'No. PO ${item.noPo}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  if (_has(item.description)) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (_has(item.equipmentReference) ||
                      item.releaseDate != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: <Widget>[
                        if (_has(item.equipmentReference))
                          _Meta(
                            icon: Icons.precision_manufacturing_outlined,
                            label: item.equipmentReference!,
                          ),
                        if (item.releaseDate != null)
                          _Meta(
                            icon: Icons.event_outlined,
                            label: _date(item.releaseDate!),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
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
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.noPr, style: Theme.of(context).textTheme.titleLarge),
          if (_has(item.description)) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              item.description!,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 18),
          _DetailRow(label: 'No. PO', value: item.noPo),
          _DetailRow(label: 'Referensi alat', value: item.equipmentReference),
          _DetailRow(
            label: 'Tanggal ditutup',
            value: item.closedDate == null ? null : _date(item.closedDate!),
          ),
          _DetailRow(
            label: 'Tanggal rilis',
            value: item.releaseDate == null ? null : _date(item.releaseDate!),
          ),
          _DetailRow(label: 'Status', value: item.status),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (!_has(value)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 124,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(child: Text(value!)),
        ],
      ),
    );
  }
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

String _date(DateTime value) =>
    DateFormat('dd/MM/yyyy').format(value.toLocal());

String _number(int value) => NumberFormat.decimalPattern('id_ID').format(value);
