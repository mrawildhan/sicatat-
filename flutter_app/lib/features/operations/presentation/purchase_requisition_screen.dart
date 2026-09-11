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
  List<PurchaseRequisition> _items = const <PurchaseRequisition>[];
  PurchaseRequisitionSort _sort = PurchaseRequisitionSort.arrivalNewest;
  int? _releaseYear;
  int? _releaseMonth;
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
      final List<PurchaseRequisition> items = !_hasSearchCriteria
          ? const <PurchaseRequisition>[]
          : await _find(service);
      if (!mounted) return;
      setState(() => _items = items);
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
    if (!_hasSearchCriteria) {
      setState(() {
        _items = const <PurchaseRequisition>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final List<PurchaseRequisition> items = await _find(service);
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

  bool get _hasSearchCriteria =>
      _searchController.text.trim().isNotEmpty || _releaseYear != null;

  Future<List<PurchaseRequisition>> _find(PurchaseRequisitionService service) =>
      service.search(
        _searchController.text,
        sort: _sort,
        releaseYear: _releaseYear,
        releaseMonth: _releaseMonth,
      );

  String get _releasePeriodLabel {
    if (_releaseYear == null) return 'Filter periode rilis';
    if (_releaseMonth == null) return 'Tahun $_releaseYear';
    return '${_monthName(_releaseMonth!)} $_releaseYear';
  }

  Future<void> _pickReleasePeriod() async {
    final _ReleasePeriod? period = await showDialog<_ReleasePeriod>(
      context: context,
      builder: (BuildContext context) =>
          _ReleasePeriodPicker(year: _releaseYear, month: _releaseMonth),
    );
    if (period == null || !mounted) return;
    setState(() {
      _releaseYear = period.year;
      _releaseMonth = period.month;
    });
    await _search();
  }

  void _clearReleasePeriod() {
    setState(() {
      _releaseYear = null;
      _releaseMonth = null;
    });
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
                const SizedBox(height: 10),
                _ReleasePeriodBar(
                  label: _releasePeriodLabel,
                  active: _releaseYear != null,
                  onPressed: _pickReleasePeriod,
                  onClear: _releaseYear == null ? null : _clearReleasePeriod,
                ),
                const SizedBox(height: 12),
                _ResultHeading(
                  count: _items.length,
                  hasCriteria: _hasSearchCriteria,
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
    if (!_hasSearchCriteria) {
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
        const Expanded(child: Text('Data PR', style: AppTextStyles.pageTitle)),
        IconButton(
          tooltip: 'Perbarui data PR',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading({
    required this.count,
    required this.hasCriteria,
    required this.sort,
    required this.onSortChanged,
  });

  final int count;
  final bool hasCriteria;
  final PurchaseRequisitionSort sort;
  final ValueChanged<PurchaseRequisitionSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    if (!hasCriteria) {
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

class _ReleasePeriodBar extends StatelessWidget {
  const _ReleasePeriodBar({
    required this.label,
    required this.active,
    required this.onPressed,
    required this.onClear,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            Icons.calendar_month_outlined,
            size: 19,
            color: active ? AppColors.green : AppColors.muted,
          ),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppColors.green : AppColors.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(color: active ? AppColors.green : AppColors.line),
          ),
        ),
      ),
      if (onClear != null) ...<Widget>[
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Hapus filter periode',
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ],
  );
}

class _ReleasePeriod {
  const _ReleasePeriod({this.year, this.month});

  final int? year;
  final int? month;
}

class _ReleasePeriodPicker extends StatefulWidget {
  const _ReleasePeriodPicker({required this.year, required this.month});

  final int? year;
  final int? month;

  @override
  State<_ReleasePeriodPicker> createState() => _ReleasePeriodPickerState();
}

class _ReleasePeriodPickerState extends State<_ReleasePeriodPicker> {
  late int _year = widget.year ?? 0;
  late int _month = widget.month ?? 0;

  List<int> get _years => List<int>.generate(
    DateTime.now().year - 2019,
    (int index) => DateTime.now().year - index,
  );

  @override
  Widget build(BuildContext context) => Dialog(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Filter tanggal rilis',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          const Text(
            'Pilih tahun untuk melihat seluruh PR dalam setahun. Tambahkan bulan bila diperlukan.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            initialValue: _year,
            decoration: const InputDecoration(labelText: 'Tahun rilis'),
            items: <DropdownMenuItem<int>>[
              const DropdownMenuItem<int>(value: 0, child: Text('Pilih tahun')),
              ..._years.map(
                (int year) =>
                    DropdownMenuItem<int>(value: year, child: Text('$year')),
              ),
            ],
            onChanged: (int? value) => setState(() {
              _year = value ?? 0;
              if (_year == 0) _month = 0;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Bulan rilis'),
            items: <DropdownMenuItem<int>>[
              const DropdownMenuItem<int>(value: 0, child: Text('Semua bulan')),
              ...List<int>.generate(12, (int index) => index + 1).map(
                (int month) => DropdownMenuItem<int>(
                  value: month,
                  child: Text(_monthName(month)),
                ),
              ),
            ],
            onChanged: _year == 0
                ? null
                : (int? value) => setState(() => _month = value ?? 0),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, const _ReleasePeriod()),
                child: const Text('Hapus filter'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _year == 0
                    ? null
                    : () => Navigator.pop(
                        context,
                        _ReleasePeriod(
                          year: _year,
                          month: _month == 0 ? null : _month,
                        ),
                      ),
                child: const Text('Tampilkan PR'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
            'Gunakan kata kunci, atau pilih periode rilis untuk melihat daftar PR.',
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
          crossAxisAlignment: CrossAxisAlignment.center,
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
                    'PR ${item.noPr}  |  PO ${_display(item.noPo)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
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

String _monthName(int month) => const <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
][month - 1];

String _date(DateTime value) =>
    DateFormat('dd/MM/yyyy').format(value.toLocal());
