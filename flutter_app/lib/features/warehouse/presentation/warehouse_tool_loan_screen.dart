import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/source_update_card.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../auth/application/current_user_provider.dart';
import '../warehouse_data.dart';

const int _maxLoanTools = 20;

/// A registered tool with the status SICATAT shows for it: on loan first,
/// then the condition recorded in SICATAT, then the Google Sheet status.
class WarehouseToolRecord {
  const WarehouseToolRecord({
    required this.id,
    required this.registrationCode,
    required this.toolName,
    required this.siteLabel,
    this.siteId,
    this.mnemonic,
    this.serialNumber,
    this.sheetStatus,
    this.conditionStatus,
    this.conditionNote,
    this.note,
  });

  final String id;
  final String registrationCode;
  final String toolName;
  final String siteLabel;
  final String? siteId;
  final String? mnemonic;
  final String? serialNumber;
  final String? sheetStatus;
  final String? conditionStatus;
  final String? conditionNote;
  final String? note;

  static const String columns =
      'id,registration_code,tool_name,site_label,site_id,mnemonic,'
      'serial_number,tool_status,condition_status,condition_note,note';

  String status({required bool onLoan}) => onLoan
      ? 'dipinjam'
      : (conditionStatus ?? sheetStatus ?? '').toLowerCase();

  bool canLend({required bool onLoan}) {
    final String value = status(onLoan: onLoan);
    return value != 'dipinjam' && value != 'rusak' && value != 'hilang';
  }

  String get searchText => <String?>[
    registrationCode,
    toolName,
    mnemonic,
    serialNumber,
  ].whereType<String>().join(' ').toLowerCase();

  factory WarehouseToolRecord.fromJson(JsonMap json) => WarehouseToolRecord(
    id: json.requiredString('id'),
    registrationCode: json.requiredString('registration_code'),
    toolName: json.requiredString('tool_name'),
    siteLabel: json.requiredString('site_label'),
    siteId: json.optionalString('site_id'),
    mnemonic: json.optionalString('mnemonic'),
    serialNumber: json.optionalString('serial_number'),
    sheetStatus: json.optionalString('tool_status'),
    conditionStatus: json.optionalString('condition_status'),
    conditionNote: json.optionalString('condition_note'),
    note: json.optionalString('note'),
  );
}

class _LoanItem {
  const _LoanItem({
    required this.id,
    required this.toolId,
    required this.registrationCode,
    required this.toolName,
    required this.quantity,
    required this.borrowerName,
    required this.workArea,
    required this.loanedOn,
    this.numberColour,
    this.loanNote,
    this.siteName,
    this.creatorName,
    this.returnedAt,
    this.returnCondition,
    this.returnNote,
    this.returnedByName,
  });

  final String id;
  final String toolId;
  final String registrationCode;
  final String toolName;
  final int quantity;
  final String borrowerName;
  final String workArea;
  final DateTime loanedOn;
  final String? numberColour;
  final String? loanNote;
  final String? siteName;
  final String? creatorName;
  final String? returnedAt;
  final String? returnCondition;
  final String? returnNote;
  final String? returnedByName;

  static const String columns =
      'id,tool_id,registration_code,tool_name,quantity,number_colour,'
      'returned_at,return_condition,return_note,returner:returned_by(name),'
      'loan:loan_id(borrower_name,work_area,loaned_on,note,'
      'site:site_id(name),creator:created_by(name))';

  String get searchText => <String?>[
    registrationCode,
    toolName,
    borrowerName,
    workArea,
    numberColour,
  ].whereType<String>().join(' ').toLowerCase();

  factory _LoanItem.fromJson(JsonMap json) {
    final JsonMap loan = requireJsonMap(json['loan'], source: 'loan');
    final Object? site = loan['site'];
    final Object? creator = loan['creator'];
    final Object? returner = json['returner'];
    return _LoanItem(
      id: json.requiredString('id'),
      toolId: json.requiredString('tool_id'),
      registrationCode: json.requiredString('registration_code'),
      toolName: json.requiredString('tool_name'),
      quantity: json.requiredInt('quantity'),
      numberColour: json.optionalString('number_colour'),
      borrowerName: loan.requiredString('borrower_name'),
      workArea: loan.requiredString('work_area'),
      loanedOn: DateTime.parse(loan.requiredString('loaned_on')),
      loanNote: loan.optionalString('note'),
      siteName: site == null
          ? null
          : requireJsonMap(site).optionalString('name'),
      creatorName: creator == null
          ? null
          : requireJsonMap(creator).optionalString('name'),
      returnedAt: json.optionalString('returned_at'),
      returnCondition: json.optionalString('return_condition'),
      returnNote: json.optionalString('return_note'),
      returnedByName: returner == null
          ? null
          : requireJsonMap(returner).optionalString('name'),
    );
  }
}

class WarehouseToolLoanScreen extends ConsumerStatefulWidget {
  const WarehouseToolLoanScreen({super.key});

  @override
  ConsumerState<WarehouseToolLoanScreen> createState() =>
      _WarehouseToolLoanScreenState();
}

class _WarehouseToolLoanScreenState
    extends ConsumerState<WarehouseToolLoanScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _search = TextEditingController();
  List<_LoanItem> _open = const <_LoanItem>[];
  List<_LoanItem> _history = const <_LoanItem>[];
  List<WarehouseToolRecord> _tools = const <WarehouseToolRecord>[];
  bool _loading = true;
  String? _error;

  /// Loans kept in the LIST ORDER workbook (Drive), read-only here.
  List<_SheetLoan> _sheetOpen = const <_SheetLoan>[];
  List<_SheetLoan> _sheetReturned = const <_SheetLoan>[];
  WarehouseDriveStatus? _sheetStatus;
  bool _checkingSheet = false;
  DateTime? _sheetCheckedAt;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    _checkSheet();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppUser? user = ref.read(currentUserProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      dynamic toolRequest = _client
          .from('warehouse_tool')
          .select(WarehouseToolRecord.columns);
      // A warehouseman manages only their own site's tools.
      if (user?.role == UserRole.warehouseman && user?.siteId != null) {
        toolRequest = toolRequest.eq('site_id', user!.siteId!);
      }
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          _client
              .from('warehouse_tool_loan_item')
              .select(_LoanItem.columns)
              .isFilter('returned_at', null)
              .limit(500),
          _client
              .from('warehouse_tool_loan_item')
              .select(_LoanItem.columns)
              .not('returned_at', 'is', null)
              .order('returned_at', ascending: false)
              .limit(100),
          (toolRequest.order('tool_name', ascending: true).limit(2000)
              as Future<Object?>),
          _client
              .from('warehouse_list_order_loan')
              .select(_SheetLoan.columns)
              .eq('returned', false)
              .order('loaned_on', ascending: false, nullsFirst: false)
              .order('row_no', ascending: false)
              .limit(500),
          _client
              .from('warehouse_list_order_loan')
              .select(_SheetLoan.columns)
              .eq('returned', true)
              .order('loaned_on', ascending: false, nullsFirst: false)
              .order('row_no', ascending: false)
              .limit(50),
        ],
      );
      for (final Object? response in responses) {
        if (response is! List) {
          throw const FormatException('Data peminjaman alat tidak valid.');
        }
      }
      if (!mounted) return;
      setState(() {
        _open =
            (responses[0]! as List<Object?>)
                .map((Object? row) => _LoanItem.fromJson(requireJsonMap(row)))
                .toList()
              ..sort(
                (_LoanItem a, _LoanItem b) => a.loanedOn.compareTo(b.loanedOn),
              );
        _history = (responses[1]! as List<Object?>)
            .map((Object? row) => _LoanItem.fromJson(requireJsonMap(row)))
            .toList(growable: false);
        _tools = (responses[2]! as List<Object?>)
            .map(
              (Object? row) =>
                  WarehouseToolRecord.fromJson(requireJsonMap(row)),
            )
            .toList(growable: false);
        _sheetOpen = (responses[3]! as List<Object?>)
            .map((Object? row) => _SheetLoan.fromJson(requireJsonMap(row)))
            .toList(growable: false);
        _sheetReturned = (responses[4]! as List<Object?>)
            .map((Object? row) => _SheetLoan.fromJson(requireJsonMap(row)))
            .toList(growable: false);
        _loading = false;
      });
      await _loadSheetStatus();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = warehouseErrorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadSheetStatus() async {
    try {
      final Map<WarehouseDriveSource, WarehouseDriveStatus> status =
          await loadWarehouseDriveStatus(_client);
      if (mounted) {
        setState(() => _sheetStatus = status[WarehouseDriveSource.listOrder]);
      }
    } on Object {
      // The loans still show without their source status.
    }
  }

  /// Checks the LIST ORDER workbook in Drive; reloads when it changed.
  Future<void> _checkSheet({bool announce = false}) async {
    if (_checkingSheet) return;
    setState(() => _checkingSheet = true);
    try {
      final Set<WarehouseDriveSource> changed = await checkWarehouseDrive(
        _client,
        const <WarehouseDriveSource>[WarehouseDriveSource.listOrder],
      );
      if (changed.isNotEmpty) {
        await _load();
      } else {
        await _loadSheetStatus();
      }
      if (!mounted) return;
      setState(() => _sheetCheckedAt = DateTime.now());
      if (announce) {
        _toast(
          changed.isEmpty
              ? 'File LIST ORDER di Drive belum berubah.'
              : 'Pinjaman LIST ORDER diperbarui dari Drive.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingSheet = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _return(_LoanItem item) async {
    final (String, String)? result = await _conditionDialog(
      context,
      title: 'Pengembalian alat',
      subtitle:
          '${item.toolName} (${item.registrationCode})\nDipinjam ${item.borrowerName} · ${warehouseDateLabel(item.loanedOn)}',
      noteLabel: 'Catatan kondisi saat diterima *',
      noteRequired: true,
      confirmLabel: 'Simpan pengembalian',
    );
    if (result == null) return;
    try {
      await _client.rpc<Object?>(
        'warehouse_tool_return',
        params: <String, Object?>{
          'p_item_id': item.id,
          'p_condition': result.$1,
          'p_note': result.$2,
        },
      );
      _toast('${item.toolName} sudah dikembalikan.');
      await _load();
    } on Object catch (error) {
      _toast('Pengembalian gagal: ${warehouseErrorText(error)}');
    }
  }

  Future<void> _changeCondition(WarehouseToolRecord tool) async {
    final (String, String)? result = await _conditionDialog(
      context,
      title: 'Ubah kondisi alat',
      subtitle: '${tool.toolName} (${tool.registrationCode})',
      initialStatus: tool.conditionStatus ?? tool.sheetStatus,
      noteLabel: 'Catatan',
      noteRequired: false,
      confirmLabel: 'Simpan kondisi',
    );
    if (result == null) return;
    try {
      await _client.rpc<Object?>(
        'warehouse_tool_set_condition',
        params: <String, Object?>{
          'p_tool_id': tool.id,
          'p_status': result.$1,
          'p_note': result.$2,
        },
      );
      _toast('Kondisi ${tool.toolName} diperbarui.');
      await _load();
    } on Object catch (error) {
      _toast('Gagal menyimpan kondisi: ${warehouseErrorText(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String query = _search.text.trim().toLowerCase();
    final Set<String> onLoan = _open.map((_LoanItem i) => i.toolId).toSet();
    final List<_LoanItem> open = _open
        .where((_LoanItem i) => query.isEmpty || i.searchText.contains(query))
        .toList(growable: false);
    final List<_LoanItem> history = _history
        .where((_LoanItem i) => query.isEmpty || i.searchText.contains(query))
        .toList(growable: false);
    final List<WarehouseToolRecord> tools = _tools
        .where(
          (WarehouseToolRecord t) =>
              query.isEmpty || t.searchText.contains(query),
        )
        .toList(growable: false);
    return AppBackScope(
      fallbackRoute: '/warehouse',
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            leading: const AppBackButton(fallbackRoute: '/warehouse'),
            title: const Text('Peminjaman Alat'),
            actions: <Widget>[
              IconButton(
                onPressed: () => context.go('/warehouse/tools/new'),
                icon: const Icon(Icons.app_registration_rounded),
                tooltip: 'Registrasi alat baru',
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Muat ulang',
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              dividerColor: Colors.transparent,
              tabs: <Widget>[
                Tab(text: 'Dipinjam (${_open.length})'),
                const Tab(text: 'Daftar alat'),
                const Tab(text: 'Riwayat'),
                Tab(text: 'List Order (${_sheetOpen.length})'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.go('/warehouse/tool-loans/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Pinjam alat'),
          ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Cari alat, kode registrasi, atau peminjam',
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? WarehouseMessage(
                        icon: Icons.cloud_off_rounded,
                        title: 'Data tidak dapat dimuat',
                        body: _error,
                        onRetry: _load,
                      )
                    : TabBarView(
                        children: <Widget>[
                          _list(
                            itemCount: open.length,
                            empty: const WarehouseMessage(
                              icon: Icons.handyman_outlined,
                              title: 'Tidak ada alat yang sedang dipinjam',
                            ),
                            itemBuilder: (int index) => _OpenLoanCard(
                              item: open[index],
                              onReturn: () => _return(open[index]),
                            ),
                          ),
                          _list(
                            itemCount: tools.length,
                            empty: const WarehouseMessage(
                              icon: Icons.handyman_outlined,
                              title: 'Alat tidak ditemukan',
                              body: 'Daftarkan alat baru dengan tombol registrasi di atas.',
                            ),
                            itemBuilder: (int index) => _ToolCard(
                              tool: tools[index],
                              onLoan: onLoan.contains(tools[index].id),
                              onChangeCondition:
                                  onLoan.contains(tools[index].id)
                                  ? null
                                  : () => _changeCondition(tools[index]),
                            ),
                          ),
                          _list(
                            itemCount: history.length,
                            empty: const WarehouseMessage(
                              icon: Icons.history_rounded,
                              title: 'Belum ada pengembalian',
                            ),
                            itemBuilder: (int index) =>
                                _ReturnedCard(item: history[index]),
                          ),
                          _listOrderTab(query),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listOrderTab(String query) {
    bool matches(_SheetLoan loan) =>
        query.isEmpty || loan.searchText.contains(query);
    final List<_SheetLoan> open = _sheetOpen
        .where(matches)
        .toList(growable: false);
    final List<_SheetLoan> returned = _sheetReturned
        .where(matches)
        .toList(growable: false);
    final WarehouseDriveStatus? status = _sheetStatus;
    return RefreshIndicator(
      onRefresh: () => _checkSheet(announce: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: <Widget>[
          SourceUpdateCard(
            title: 'Pinjaman di LIST ORDER (AMWH)',
            changes: <String>[
              status?.changedAt == null
                  ? 'File LIST ORDER belum terbaca'
                  : 'File berubah ${sourceUpdateStamp(status!.changedAt!)}',
            ],
            checking: _checkingSheet,
            checkedAt: _sheetCheckedAt ?? status?.checkedAt,
            error: status?.error,
            onRefresh: () => _checkSheet(announce: true),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dicatat tim gudang di LIST ORDER, hanya dibaca di sini. '
            'Kondisi akhir yang kosong berarti belum dikembalikan.',
            style: AppTextStyles.supporting,
          ),
          const SizedBox(height: 14),
          Text(
            'Belum kembali (${open.length})',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 6),
          if (open.isEmpty)
            const Text('Tidak ada.', style: AppTextStyles.supporting),
          for (final _SheetLoan loan in open) ...<Widget>[
            _SheetLoanCard(loan: loan),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 14),
          const Text(
            'Sudah kembali (50 terakhir)',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 6),
          for (final _SheetLoan loan in returned) ...<Widget>[
            _SheetLoanCard(loan: loan),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _list({
    required int itemCount,
    required Widget empty,
    required Widget Function(int index) itemBuilder,
  }) => RefreshIndicator(
    onRefresh: _load,
    child: itemCount == 0
        ? empty
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, int index) => itemBuilder(index),
          ),
  );
}

class _OpenLoanCard extends StatelessWidget {
  const _OpenLoanCard({required this.item, required this.onReturn});

  final _LoanItem item;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final int days = warehouseLoanAgeDays(item.loanedOn);
    final bool overdue = days > warehouseLoanOverdueDays;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: overdue
            ? const BorderSide(color: AppColors.danger, width: 1.4)
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
                    item.toolName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.greenDark,
                    ),
                  ),
                ),
                WarehouseTag(
                  overdue
                      ? '$days hari'
                      : (days == 0 ? 'Hari ini' : '$days hari'),
                  color: overdue ? AppColors.danger : AppColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                item.registrationCode,
                'Qty ${item.quantity}',
                if (item.numberColour != null) item.numberColour!,
                if (item.siteName != null) item.siteName!,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              '${item.borrowerName} · ${item.workArea}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Dipinjam ${warehouseDateLabel(item.loanedOn)}'
              '${item.creatorName == null ? '' : ' · dicatat ${item.creatorName}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (item.loanNote != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(item.loanNote!, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onReturn,
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Kembalikan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.onLoan,
    required this.onChangeCondition,
  });

  final WarehouseToolRecord tool;
  final bool onLoan;
  final VoidCallback? onChangeCondition;

  @override
  Widget build(BuildContext context) {
    final String status = tool.status(onLoan: onLoan);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChangeCondition,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tool.toolName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        tool.registrationCode,
                        tool.siteLabel,
                        if (tool.serialNumber != null)
                          'S/N ${tool.serialNumber}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    if ((tool.conditionNote ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        tool.conditionNote!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              WarehouseTag(
                warehouseConditionLabel(status),
                color: warehouseConditionColor(status),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tool loan row of the LIST ORDER sheet "PEMINJAMAN & OUTSTANDING TOOLS".
class _SheetLoan {
  const _SheetLoan({
    required this.toolName,
    required this.returned,
    this.loanedOn,
    this.quantity,
    this.numberColour,
    this.location,
    this.borrower,
    this.warehouseman,
    this.conditionStart,
    this.conditionEnd,
  });

  static const String columns =
      'loaned_on,tool_name,quantity,number_colour,location,borrower,'
      'warehouseman,condition_start,condition_end,returned';

  final String toolName;
  final bool returned;
  final DateTime? loanedOn;
  final String? quantity;
  final String? numberColour;
  final String? location;
  final String? borrower;
  final String? warehouseman;
  final String? conditionStart;
  final String? conditionEnd;

  String get searchText => <String?>[
    toolName,
    borrower,
    location,
    warehouseman,
    numberColour,
  ].whereType<String>().join(' ').toLowerCase();

  factory _SheetLoan.fromJson(JsonMap json) => _SheetLoan(
    toolName: json.requiredString('tool_name'),
    returned: json['returned'] == true,
    loanedOn: DateTime.tryParse(json.optionalString('loaned_on') ?? ''),
    quantity: json.optionalString('quantity'),
    numberColour: json.optionalString('number_colour'),
    location: json.optionalString('location'),
    borrower: json.optionalString('borrower'),
    warehouseman: json.optionalString('warehouseman'),
    conditionStart: json.optionalString('condition_start'),
    conditionEnd: json.optionalString('condition_end'),
  );
}

class _SheetLoanCard extends StatelessWidget {
  const _SheetLoanCard({required this.loan});

  final _SheetLoan loan;

  @override
  Widget build(BuildContext context) {
    final int? days = loan.loanedOn == null
        ? null
        : warehouseLoanAgeDays(loan.loanedOn!);
    final bool overdue =
        !loan.returned && days != null && days > warehouseLoanOverdueDays;
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
              children: <Widget>[
                Expanded(
                  child: Text(
                    loan.toolName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.greenDark,
                    ),
                  ),
                ),
                if (loan.returned)
                  WarehouseTag(
                    loan.conditionEnd ?? 'Kembali',
                    color: warehouseConditionColor(
                      loan.conditionEnd?.toLowerCase().contains('rusak') == true
                          ? 'rusak'
                          : null,
                    ),
                  )
                else if (days != null)
                  WarehouseTag(
                    days == 0 ? 'Hari ini' : '$days hari',
                    color: overdue ? AppColors.danger : AppColors.orange,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                if (loan.quantity != null) 'Qty ${loan.quantity}',
                if (loan.numberColour != null) loan.numberColour!,
                if (loan.location != null) loan.location!,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            Text(
              <String>[
                loan.borrower ?? 'Peminjam tidak tercatat',
                if (loan.loanedOn != null)
                  'dipinjam ${warehouseDateLabel(loan.loanedOn!)}',
                if (loan.warehouseman != null) 'WH ${loan.warehouseman}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnedCard extends StatelessWidget {
  const _ReturnedCard({required this.item});

  final _LoanItem item;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.toolName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              WarehouseTag(
                warehouseConditionLabel(item.returnCondition),
                color: warehouseConditionColor(item.returnCondition),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${item.registrationCode} · ${item.borrowerName} · ${item.workArea}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          Text(
            'Dipinjam ${warehouseDateLabel(item.loanedOn)} · kembali ${warehouseDateText(item.returnedAt)}'
            '${item.returnedByName == null ? '' : ' (${item.returnedByName})'}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (item.returnNote != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(item.returnNote!, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    ),
  );
}

/// Asks for a tool condition and a note. Returns (condition, note).
Future<(String, String)?> _conditionDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String noteLabel,
  required bool noteRequired,
  required String confirmLabel,
  String? initialStatus,
}) {
  final TextEditingController note = TextEditingController();
  String status = warehouseToolConditions
      .map(((String, String) c) => c.$1)
      .firstWhere(
        (String value) => value == (initialStatus ?? '').toLowerCase(),
        orElse: () => warehouseToolConditions.first.$1,
      );
  return showDialog<(String, String)>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(subtitle, style: AppTextStyles.supporting),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Kondisi'),
                items: <DropdownMenuItem<String>>[
                  for (final (String value, String label)
                      in warehouseToolConditions)
                    DropdownMenuItem<String>(value: value, child: Text(label)),
                ],
                onChanged: (String? value) {
                  if (value != null) setState(() => status = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: noteLabel),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: noteRequired && note.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (status, note.text.trim())),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

// Loan form -----------------------------------------------------------------

class WarehouseToolLoanFormScreen extends ConsumerStatefulWidget {
  const WarehouseToolLoanFormScreen({super.key});

  @override
  ConsumerState<WarehouseToolLoanFormScreen> createState() =>
      _WarehouseToolLoanFormScreenState();
}

class _WarehouseToolLoanFormScreenState
    extends ConsumerState<WarehouseToolLoanFormScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _borrower = TextEditingController();
  final TextEditingController _workArea = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_LoanLine> _lines = <_LoanLine>[];
  List<WarehouseSite> _sites = const <WarehouseSite>[];
  WarehouseSite? _site;
  List<WarehouseToolRecord> _tools = const <WarehouseToolRecord>[];
  Set<String> _onLoan = const <String>{};
  DateTime _date = warehouseDateOnly(DateTime.now());
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _borrower.dispose();
    _workArea.dispose();
    _note.dispose();
    for (final _LoanLine line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final AppUser? user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          loadWarehouseSites(_client, user),
          _client
              .from('warehouse_tool')
              .select(WarehouseToolRecord.columns)
              .order('tool_name', ascending: true)
              .limit(2000),
          _client.rpc<Object?>('warehouse_tools_on_loan'),
        ],
      );
      final List<WarehouseSite> sites = responses[0]! as List<WarehouseSite>;
      final Object? tools = responses[1];
      final Object? onLoan = responses[2];
      if (tools is! List || onLoan is! List) {
        throw const FormatException('Daftar alat tidak valid.');
      }
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _site = sites.isEmpty ? null : sites.first;
        _tools = tools
            .map(
              (Object? row) =>
                  WarehouseToolRecord.fromJson(requireJsonMap(row)),
            )
            .toList(growable: false);
        _onLoan = onLoan
            .map((Object? row) => requireJsonMap(row).requiredString('tool_id'))
            .toSet();
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Data alat gagal dimuat: ${warehouseErrorText(error)}');
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  List<WarehouseToolRecord> get _siteTools => _tools
      .where((WarehouseToolRecord t) => t.siteId == _site?.id)
      .toList(growable: false);

  Future<void> _pickTool() async {
    if (_lines.length >= _maxLoanTools) {
      _toast('Maksimal $_maxLoanTools alat per peminjaman.');
      return;
    }
    final Set<String> chosen = _lines.map((_LoanLine l) => l.tool.id).toSet();
    final WarehouseToolRecord? tool =
        await showModalBottomSheet<WarehouseToolRecord>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) =>
              _ToolPicker(tools: _siteTools, onLoan: _onLoan, chosen: chosen),
        );
    if (tool == null || !mounted) return;
    setState(() => _lines.add(_LoanLine(tool)));
  }

  Future<void> _save() async {
    final WarehouseSite? site = _site;
    if (site == null) {
      _toast('Pilih site gudang terlebih dahulu.');
      return;
    }
    if (_borrower.text.trim().isEmpty || _workArea.text.trim().isEmpty) {
      _toast('Nama peminjam dan area kerja wajib diisi.');
      return;
    }
    if (_lines.isEmpty) {
      _toast('Pilih minimal satu alat.');
      return;
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (final _LoanLine line in _lines) {
      final int? quantity = int.tryParse(line.quantity.text.trim());
      if (quantity == null || quantity <= 0) {
        _toast('Qty ${line.tool.toolName} harus bilangan bulat lebih dari 0.');
        return;
      }
      items.add(<String, Object?>{
        'tool_id': line.tool.id,
        'quantity': quantity,
        'number_colour': line.numberColour.text.trim(),
      });
    }
    setState(() => _saving = true);
    try {
      await _client.rpc<Object?>(
        'warehouse_tool_loan_create',
        params: <String, Object?>{
          'p_site_id': site.id,
          'p_borrower_name': _borrower.text.trim(),
          'p_work_area': _workArea.text.trim(),
          'p_loaned_on': warehouseDateParam(_date),
          'p_note': _note.text.trim(),
          'p_items': items,
        },
      );
      if (!mounted) return;
      _toast('Peminjaman ${items.length} alat tercatat.');
      context.go('/warehouse/tool-loans');
    } on Object catch (error) {
      if (mounted) _toast('Gagal menyimpan: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/warehouse/tool-loans',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/warehouse/tool-loans'),
        title: const Text('Pinjam alat'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: <Widget>[
                WarehouseSitePicker(
                  sites: _sites,
                  selected: _site,
                  enabled: !_saving && _lines.isEmpty,
                  onChanged: (WarehouseSite site) =>
                      setState(() => _site = site),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _borrower,
                  enabled: !_saving,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama peminjam *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _workArea,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Area kerja *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                WarehouseDateField(
                  label: 'Tanggal pinjam',
                  value: _date,
                  enabled: !_saving,
                  onChanged: (DateTime value) => setState(() => _date = value),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Alat (${_lines.length})',
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving || _site == null ? null : _pickTool,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Pilih alat'),
                    ),
                  ],
                ),
                if (_lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Belum ada alat dipilih. Alat yang sedang dipinjam, rusak, atau hilang tidak bisa dipilih.',
                      style: AppTextStyles.supporting,
                    ),
                  ),
                for (final _LoanLine line in _lines) ...<Widget>[
                  _LoanLineCard(
                    line: line,
                    enabled: !_saving,
                    onRemove: () {
                      setState(() => _lines.remove(line));
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
                  decoration: const InputDecoration(
                    labelText: 'Catatan peminjaman',
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
                  label: const Text('Simpan peminjaman'),
                ),
              ],
            ),
    ),
  );
}

class _LoanLine {
  _LoanLine(this.tool);

  final WarehouseToolRecord tool;
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController numberColour = TextEditingController();

  void dispose() {
    quantity.dispose();
    numberColour.dispose();
  }
}

class _LoanLineCard extends StatelessWidget {
  const _LoanLineCard({
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  final _LoanLine line;
  final bool enabled;
  final VoidCallback onRemove;

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
                '${line.tool.toolName} · ${line.tool.registrationCode}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Hapus alat',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 90,
                child: TextField(
                  controller: line.quantity,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.numberColour,
                  enabled: enabled,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nomor / warna',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ToolPicker extends StatefulWidget {
  const _ToolPicker({
    required this.tools,
    required this.onLoan,
    required this.chosen,
  });

  final List<WarehouseToolRecord> tools;
  final Set<String> onLoan;
  final Set<String> chosen;

  @override
  State<_ToolPicker> createState() => _ToolPickerState();
}

class _ToolPickerState extends State<_ToolPicker> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String query = _search.text.trim().toLowerCase();
    final List<WarehouseToolRecord> tools = widget.tools
        .where(
          (WarehouseToolRecord t) =>
              query.isEmpty || t.searchText.contains(query),
        )
        .toList(growable: false);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Cari nama alat atau kode registrasi',
              ),
            ),
          ),
          Expanded(
            child: tools.isEmpty
                ? const WarehouseMessage(
                    icon: Icons.handyman_outlined,
                    title: 'Alat tidak ditemukan di site ini',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: tools.length,
                    itemBuilder: (_, int index) {
                      final WarehouseToolRecord tool = tools[index];
                      final bool onLoan = widget.onLoan.contains(tool.id);
                      final bool chosen = widget.chosen.contains(tool.id);
                      final String status = tool.status(onLoan: onLoan);
                      final bool available =
                          !chosen && tool.canLend(onLoan: onLoan);
                      return ListTile(
                        enabled: available,
                        title: Text(tool.toolName),
                        subtitle: Text(
                          <String>[
                            tool.registrationCode,
                            if (tool.mnemonic != null) tool.mnemonic!,
                          ].join(' · '),
                        ),
                        trailing: WarehouseTag(
                          chosen ? 'Dipilih' : warehouseConditionLabel(status),
                          color: chosen
                              ? AppColors.muted
                              : warehouseConditionColor(status),
                        ),
                        onTap: available
                            ? () => Navigator.pop(context, tool)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Registration ---------------------------------------------------------------

class WarehouseToolRegisterScreen extends ConsumerStatefulWidget {
  const WarehouseToolRegisterScreen({super.key});

  @override
  ConsumerState<WarehouseToolRegisterScreen> createState() =>
      _WarehouseToolRegisterScreenState();
}

class _WarehouseToolRegisterScreenState
    extends ConsumerState<WarehouseToolRegisterScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _mnemonic = TextEditingController();
  final TextEditingController _serial = TextEditingController();
  final TextEditingController _note = TextEditingController();
  List<WarehouseSite> _sites = const <WarehouseSite>[];
  WarehouseSite? _site;
  String _status = warehouseToolConditions.first.$1;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _mnemonic.dispose();
    _serial.dispose();
    _note.dispose();
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
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Site gagal dimuat: ${warehouseErrorText(error)}');
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
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      _toast('Kode registrasi dan nama alat wajib diisi.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _client.rpc<Object?>(
        'warehouse_tool_register',
        params: <String, Object?>{
          'p_site_id': site.id,
          'p_registration_code': _code.text.trim(),
          'p_tool_name': _name.text.trim(),
          'p_mnemonic': _mnemonic.text.trim(),
          'p_serial_number': _serial.text.trim(),
          'p_status': _status,
          'p_note': _note.text.trim(),
        },
      );
      if (!mounted) return;
      _toast('${_name.text.trim()} terdaftar.');
      context.go('/warehouse/tool-loans');
    } on Object catch (error) {
      if (mounted) _toast('Gagal mendaftarkan: ${warehouseErrorText(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/warehouse/tool-loans',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/warehouse/tool-loans'),
        title: const Text('Registrasi alat'),
      ),
      body: _loading
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
                TextField(
                  controller: _code,
                  enabled: !_saving,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Kode registrasi *',
                    hintText: 'Contoh: REG-001',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Nama alat *',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mnemonic,
                  enabled: !_saving,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Mnemonic / kode singkat',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serial,
                  enabled: !_saving,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nomor seri',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Kondisi awal'),
                  items: <DropdownMenuItem<String>>[
                    for (final (String value, String label)
                        in warehouseToolConditions)
                      DropdownMenuItem<String>(
                        value: value,
                        child: Text(label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (String? value) {
                          if (value != null) setState(() => _status = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  enabled: !_saving,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Catatan / spesifikasi',
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
                  label: const Text('Daftarkan alat'),
                ),
              ],
            ),
    ),
  );
}
