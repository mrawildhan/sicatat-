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

/// Most items one pickup form accepts (the database allows 30).
const int _maxIssueItems = 30;

class WarehouseIssueListScreen extends StatefulWidget {
  const WarehouseIssueListScreen({super.key});

  @override
  State<WarehouseIssueListScreen> createState() =>
      _WarehouseIssueListScreenState();
}

class _WarehouseIssueListScreenState extends State<WarehouseIssueListScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _search = TextEditingController();
  List<_Issue> _issues = const <_Issue>[];
  bool _loading = true;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Object response = await _client
          .from('warehouse_issue')
          .select(
            'id,issued_on,taken_by,job_number,note,created_at,'
            'site:site_id(name),creator:created_by(name),'
            'items:warehouse_issue_item(line_no,item_code,description,uoi,bin_code,quantity)',
          )
          .order('issued_on', ascending: false)
          .order('created_at', ascending: false)
          .limit(150);
      if (response is! List) {
        throw const FormatException('Riwayat pengambilan tidak valid.');
      }
      if (!mounted) return;
      setState(() {
        _issues = response
            .map((Object? row) => _Issue.fromJson(requireJsonMap(row)))
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

  List<_Issue> get _visible {
    final String query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _issues;
    return _issues
        .where((_Issue issue) => issue.searchText.contains(query))
        .toList(growable: false);
  }

  void _openDetails(_Issue issue) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => _IssueDetails(issue: issue),
  );

  @override
  Widget build(BuildContext context) {
    final List<_Issue> visible = _visible;
    return AppBackScope(
      fallbackRoute: '/warehouse',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/warehouse'),
          title: const Text('Pengambilan Barang'),
          actions: <Widget>[
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Muat ulang',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go('/warehouse/issues/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Pengambilan baru'),
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Cari nama pengambil, no. job, kode SC, atau item',
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
                    : visible.isEmpty
                    ? WarehouseMessage(
                        icon: Icons.outbox_outlined,
                        title: _issues.isEmpty
                            ? 'Belum ada pengambilan barang'
                            : 'Tidak ada yang cocok',
                        body: _issues.isEmpty
                            ? 'Catat barang yang diambil dari gudang dengan tombol Pengambilan baru.'
                            : 'Coba kata kunci lain.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, int index) => _IssueCard(
                          issue: visible[index],
                          onTap: () => _openDetails(visible[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue, required this.onTap});

  final _Issue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    issue.takenBy,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.greenDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      warehouseDateText(issue.issuedOn),
                      if (issue.siteName != null) issue.siteName!,
                      if (issue.jobNumber != null) 'Job ${issue.jobNumber}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    issue.items
                        .map(
                          (_IssueItem item) =>
                              item.description ?? item.itemCode,
                        )
                        .join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            WarehouseTag('${issue.items.length} item'),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _IssueDetails extends StatelessWidget {
  const _IssueDetails({required this.issue});

  final _Issue issue;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      children: <Widget>[
        const Text('Pengambilan barang', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 10),
        WarehouseDetailRow('Tanggal', warehouseDateText(issue.issuedOn)),
        WarehouseDetailRow('Site', issue.siteName ?? '-'),
        WarehouseDetailRow('Pengambil', issue.takenBy),
        WarehouseDetailRow('No. job', issue.jobNumber ?? '-'),
        if (issue.note != null) WarehouseDetailRow('Keterangan', issue.note!),
        WarehouseDetailRow('Dicatat oleh', issue.creatorName ?? '-'),
        const SizedBox(height: 12),
        Text('Item (${issue.items.length})', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 6),
        for (final _IssueItem item in issue.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              item.description ?? 'Deskripsi belum tercatat',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              <String>[
                'SC ${item.itemCode}',
                if (item.binCode != null) 'Bin ${item.binCode}',
              ].join(' · '),
            ),
            trailing: Text(
              '${warehouseNumber(item.quantity)} ${item.uoi ?? ''}'.trim(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.greenDark,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Issue {
  const _Issue({
    required this.id,
    required this.issuedOn,
    required this.takenBy,
    required this.items,
    this.jobNumber,
    this.note,
    this.siteName,
    this.creatorName,
  });

  final String id;
  final String issuedOn;
  final String takenBy;
  final String? jobNumber;
  final String? note;
  final String? siteName;
  final String? creatorName;
  final List<_IssueItem> items;

  String get searchText => <String?>[
    takenBy,
    jobNumber,
    note,
    for (final _IssueItem item in items) ...<String?>[
      item.itemCode,
      item.description,
    ],
  ].whereType<String>().join(' ').toLowerCase();

  factory _Issue.fromJson(JsonMap json) {
    final Object? site = json['site'];
    final Object? creator = json['creator'];
    final List<_IssueItem> items =
        ((json['items'] as List<Object?>?) ?? const <Object?>[])
            .map((Object? row) => _IssueItem.fromJson(requireJsonMap(row)))
            .toList()
          ..sort((_IssueItem a, _IssueItem b) => a.lineNo.compareTo(b.lineNo));
    return _Issue(
      id: json.requiredString('id'),
      issuedOn: json.requiredString('issued_on'),
      takenBy: json.requiredString('taken_by'),
      jobNumber: json.optionalString('job_number'),
      note: json.optionalString('note'),
      siteName: site == null
          ? null
          : requireJsonMap(site).optionalString('name'),
      creatorName: creator == null
          ? null
          : requireJsonMap(creator).optionalString('name'),
      items: items,
    );
  }
}

class _IssueItem {
  const _IssueItem({
    required this.lineNo,
    required this.itemCode,
    required this.quantity,
    this.description,
    this.uoi,
    this.binCode,
  });

  final int lineNo;
  final String itemCode;
  final num quantity;
  final String? description;
  final String? uoi;
  final String? binCode;

  factory _IssueItem.fromJson(JsonMap json) => _IssueItem(
    lineNo: json.requiredInt('line_no'),
    itemCode: json.requiredString('item_code'),
    quantity: json['quantity'] as num? ?? 0,
    description: json.optionalString('description'),
    uoi: json.optionalString('uoi'),
    binCode: json.optionalString('bin_code'),
  );
}

// Form -----------------------------------------------------------------------

class WarehouseIssueFormScreen extends ConsumerStatefulWidget {
  const WarehouseIssueFormScreen({super.key});

  @override
  ConsumerState<WarehouseIssueFormScreen> createState() =>
      _WarehouseIssueFormScreenState();
}

class _WarehouseIssueFormScreenState
    extends ConsumerState<WarehouseIssueFormScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _takenBy = TextEditingController();
  final TextEditingController _jobNumber = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_IssueLine> _lines = <_IssueLine>[];
  List<WarehouseSite> _sites = const <WarehouseSite>[];
  WarehouseSite? _site;
  DateTime _date = warehouseDateOnly(DateTime.now());
  bool _loadingSites = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _addLine();
    _loadSites();
  }

  @override
  void dispose() {
    _takenBy.dispose();
    _jobNumber.dispose();
    _note.dispose();
    for (final _IssueLine line in _lines) {
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

  void _addLine() {
    if (_lines.length >= _maxIssueItems) {
      _toast('Maksimal $_maxIssueItems item per pengambilan.');
      return;
    }
    setState(() => _lines.add(_IssueLine(onLookup: _lookup)));
  }

  void _removeLine(_IssueLine line) {
    setState(() => _lines.remove(line));
    line.dispose();
  }

  Future<void> _lookup(_IssueLine line) async {
    final String code = line.code.text.trim();
    final int serial = ++line.serial;
    if (code.isEmpty) {
      setState(() {
        line.hit = null;
        line.notFound = false;
        line.looking = false;
      });
      return;
    }
    setState(() => line.looking = true);
    try {
      final WarehouseStockHit? hit = await lookupWarehouseStockCode(
        _client,
        code,
        siteName: _site?.name,
      );
      if (!mounted || serial != line.serial || !_lines.contains(line)) return;
      setState(() {
        line.hit = hit;
        line.notFound = hit == null;
        line.looking = false;
      });
    } on Object {
      if (!mounted || serial != line.serial || !_lines.contains(line)) return;
      setState(() {
        line.hit = null;
        line.notFound = true;
        line.looking = false;
      });
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
    if (_takenBy.text.trim().isEmpty) {
      _toast('Nama pengambil wajib diisi.');
      return;
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (int i = 0; i < _lines.length; i++) {
      final _IssueLine line = _lines[i];
      final String code = line.code.text.trim();
      if (code.isEmpty && line.quantity.text.trim().isEmpty) continue;
      if (code.isEmpty) {
        _toast('Kode SC item ${i + 1} wajib diisi.');
        return;
      }
      final num? quantity = parseWarehouseQuantity(line.quantity.text);
      if (quantity == null) {
        _toast('Jumlah item ${i + 1} harus lebih dari 0.');
        return;
      }
      items.add(<String, Object?>{
        'item_code': code,
        'description': line.hit?.description,
        'uoi': line.hit?.uoi,
        'bin_code': line.hit?.binCode,
        'quantity': quantity,
      });
    }
    if (items.isEmpty) {
      _toast('Isi minimal satu item.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.rpc<Object?>(
        'warehouse_issue_create',
        params: <String, Object?>{
          'p_site_id': site.id,
          'p_issued_on': warehouseDateParam(_date),
          'p_taken_by': _takenBy.text.trim(),
          'p_job_number': _jobNumber.text.trim(),
          'p_note': _note.text.trim(),
          'p_items': items,
        },
      );
      if (!mounted) return;
      _toast('Pengambilan ${items.length} item tersimpan.');
      context.go('/warehouse/issues');
    } on Object catch (error) {
      if (mounted) _toast('Gagal menyimpan: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/warehouse/issues',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/warehouse/issues'),
        title: const Text('Pengambilan baru'),
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
                  onChanged: (WarehouseSite site) {
                    setState(() => _site = site);
                    for (final _IssueLine line in _lines) {
                      _lookup(line);
                    }
                  },
                ),
                const SizedBox(height: 12),
                WarehouseDateField(
                  label: 'Tanggal',
                  value: _date,
                  enabled: !_saving,
                  onChanged: (DateTime value) => setState(() => _date = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _takenBy,
                  enabled: !_saving,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama pengambil *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _jobNumber,
                  enabled: !_saving,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Nomor job',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Item (${_lines.length})',
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _addLine,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah item'),
                    ),
                  ],
                ),
                const Text(
                  'Ketik kode SC; deskripsi, satuan, bin, dan stok terisi otomatis dari data Gudang.',
                  style: AppTextStyles.supporting,
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < _lines.length; i++) ...<Widget>[
                  _IssueLineCard(
                    index: i,
                    line: _lines[i],
                    enabled: !_saving,
                    onRemove: _lines.length == 1
                        ? null
                        : () => _removeLine(_lines[i]),
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
                  decoration: const InputDecoration(
                    labelText: 'Keterangan / status',
                  ),
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
                  label: const Text('Simpan pengambilan'),
                ),
              ],
            ),
    ),
  );
}

class _IssueLine {
  _IssueLine({required Future<void> Function(_IssueLine) onLookup}) {
    code.addListener(() {
      if (code.text == _lastCode) return;
      _lastCode = code.text;
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 450),
        () => onLookup(this),
      );
    });
  }

  final TextEditingController code = TextEditingController();
  final TextEditingController quantity = TextEditingController();
  WarehouseStockHit? hit;
  bool looking = false;
  bool notFound = false;
  int serial = 0;
  Timer? _debounce;
  String _lastCode = '';

  void dispose() {
    _debounce?.cancel();
    code.dispose();
    quantity.dispose();
  }
}

class _IssueLineCard extends StatelessWidget {
  const _IssueLineCard({
    required this.index,
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  final int index;
  final _IssueLine line;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final WarehouseStockHit? hit = line.hit;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
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
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: line.code,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Kode SC *',
                      suffixIcon: line.looking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
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
                    decoration: InputDecoration(
                      labelText: 'Jumlah *',
                      suffixText: hit?.uoi,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hit != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              hit.description,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              <String>[
                hit.siteLabel,
                if (hit.binCode != null) 'Bin ${hit.binCode}',
                'Stok ${warehouseNumber(hit.stockOnHand)} ${hit.uoi ?? ''}'
                    .trim(),
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: hit.stockOnHand <= 0
                    ? AppColors.danger
                    : AppColors.muted,
              ),
            ),
          ] else if (line.notFound) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'Kode SC tidak ditemukan di data Gudang. Periksa kembali; item tetap bisa disimpan.',
              style: TextStyle(fontSize: 12, color: AppColors.orange),
            ),
          ],
        ],
      ),
    );
  }
}
