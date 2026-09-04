import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/local/local_database.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/dashboard_activity.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class SheetListScreen extends ConsumerStatefulWidget {
  const SheetListScreen({super.key});

  @override
  ConsumerState<SheetListScreen> createState() => _SheetListScreenState();
}

class _SheetListScreenState extends ConsumerState<SheetListScreen> {
  List<SheetModel> _sheets = const <SheetModel>[];
  Map<String, String> _shiftNames = const <String, String>{};
  DashboardActivity? _todayActivity;
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _fromDate;
  DateTime? _toDate;
  _SheetListStatusFilter _statusFilter = _SheetListStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _loadSheets();
  }

  Future<void> _loadSheets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      List<SheetModel>? serverSheets;
      if (user != null) {
        final repository = ref.read(sicatatRepositoryProvider);
        // A freshly installed app has no locally cached shift names yet. Refresh
        // them with the sheet list so cards never fall back to "Saved shift".
        try {
          final shifts = await repository.getActiveShifts();
          await LocalDatabase.instance.cacheShifts(shifts);
        } catch (_) {
          // The already-cached names remain usable if master data is unavailable.
        }
        serverSheets = await repository.listSharedSheets(
          teamId: user.role.isTeamScopedTemperature ? user.teamId : null,
          createdBy: user.role == UserRole.crew ? user.id : null,
        );
        await LocalDatabase.instance.cacheRemoteSheets(serverSheets);
      }
      // Temperature sheets are online-only. Prefer the RLS-scoped server
      // response so a user who changes role/site never sees a stale sheet
      // cached under a broader previous scope.
      final localSheets =
          serverSheets ?? await LocalDatabase.instance.listSheets();
      final sheets = switch (user?.role) {
        UserRole.admin ||
        UserRole.supervisorSmg ||
        UserRole.supervisorCop => localSheets,
        UserRole.foreman =>
          localSheets
              .where((sheet) => sheet.teamId == user?.teamId)
              .toList(growable: false),
        _ =>
          localSheets
              .where((sheet) => sheet.createdBy == user?.id)
              .toList(growable: false),
      };
      final ids = sheets.map((sheet) => sheet.shiftId).toSet();
      final names = <String, String>{};
      for (final id in ids) {
        final name = await LocalDatabase.instance.getCachedShiftName(id);
        if (name != null) names[id] = name;
      }
      final activity = await LocalDatabase.instance.getDashboardActivity(
        DateTime.now(),
        createdBy: user?.role.isGlobalTemperatureManager == true
            ? null
            : user?.id,
      );
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
        _shiftNames = names;
        _todayActivity = activity;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Daftar sheet lokal tidak dapat dimuat.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    final title =
        user?.role.isGlobalTemperatureManager == true ||
            user?.role.isSiteScopedTemperature == true
        ? 'Semua sheet'
        : user?.role == UserRole.foreman
        ? 'Sheet tim'
        : 'Sheet saya';
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: <Widget>[
                  IconButton(
                    onPressed: _isLoading ? null : _loadSheets,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : _showFilters,
                    icon: Badge(
                      isLabelVisible: _hasFilter,
                      child: const Icon(Icons.tune_rounded),
                    ),
                    tooltip: 'Filter sheet',
                  ),
                ],
              ),
        floatingActionButton: user?.role.canCreateTemperatureSheet == true
            ? FloatingActionButton.extended(
                onPressed: () => context.go('/sheets/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Sheet baru'),
              )
            : null,
        body: useDesktopHeader
            ? Column(
                children: <Widget>[
                  _desktopHeader(title),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadSheets,
                      child: _buildBody(context),
                    ),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: _loadSheets,
                child: _buildBody(context),
              ),
      ),
    );
  }

  Widget _desktopHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          tooltip: 'Muat ulang sheet',
          onPressed: _isLoading ? null : _loadSheets,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Filter sheet',
          onPressed: _isLoading ? null : _showFilters,
          icon: Badge(
            isLabelVisible: _hasFilter,
            child: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    ),
  );

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage case final message?) {
      return ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      );
    }
    final sheets = _filteredSheets;
    if (sheets.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          _temperatureSummary(),
          const SizedBox(height: 80),
          const Icon(
            Icons.description_outlined,
            size: 58,
            color: AppColors.muted,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _hasFilter
                  ? 'Tidak ada sheet yang cocok dengan filter ini'
                  : 'Belum ada sheet inspeksi',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _hasFilter
                  ? 'Ubah atau hapus filter untuk melihat sheet lain.'
                  : 'Buat sheet baru untuk mulai mencatat suhu.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
      itemCount: sheets.length + (_hasFilter ? 1 : 0) + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) return _temperatureSummary();
        if (_hasFilter && index == 1) return _filterSummary(sheets.length);
        final sheetIndex = index - 1 - (_hasFilter ? 1 : 0);
        return _sheet(context, sheets[sheetIndex]);
      },
    );
  }

  Widget _temperatureSummary() {
    final activity = _todayActivity;
    return Row(
      children: <Widget>[
        _temperatureSummaryTile(
          label: 'Draf',
          count: activity?.draftCount ?? 0,
          color: AppColors.orange,
          icon: Icons.edit_note_rounded,
          onTap: () =>
              setState(() => _statusFilter = _SheetListStatusFilter.draft),
        ),
        const SizedBox(width: 10),
        _temperatureSummaryTile(
          label: 'Terkirim',
          count: activity?.syncedCount ?? 0,
          color: AppColors.green,
          icon: Icons.cloud_done_rounded,
          onTap: () =>
              setState(() => _statusFilter = _SheetListStatusFilter.submitted),
        ),
        const SizedBox(width: 10),
        _temperatureSummaryTile(
          label: 'Suhu tinggi',
          count: activity?.highTemperatureCount ?? 0,
          color: AppColors.danger,
          icon: Icons.thermostat_rounded,
          onTap:
              ref.read(currentUserProvider)?.role.canReviewTemperature == true
              ? () => context.go('/high-temperature')
              : null,
        ),
      ],
    );
  }

  Widget _temperatureSummaryTile({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required VoidCallback? onTap,
  }) => Expanded(
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 108,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 5),
              Text(
                '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  bool get _hasFilter =>
      _fromDate != null ||
      _toDate != null ||
      _statusFilter != _SheetListStatusFilter.all;

  List<SheetModel> get _filteredSheets => _sheets
      .where((sheet) {
        final date = DateUtils.dateOnly(sheet.date);
        if (_fromDate != null &&
            date.isBefore(DateUtils.dateOnly(_fromDate!))) {
          return false;
        }
        if (_toDate != null && date.isAfter(DateUtils.dateOnly(_toDate!))) {
          return false;
        }
        return switch (_statusFilter) {
          _SheetListStatusFilter.all => true,
          _SheetListStatusFilter.draft =>
            sheet.status == SheetStatus.draft ||
                sheet.status == SheetStatus.returned,
          _SheetListStatusFilter.submitted =>
            sheet.status == SheetStatus.submitted ||
                sheet.status == SheetStatus.submittedIncomplete ||
                sheet.status == SheetStatus.verified,
        };
      })
      .toList(growable: false);

  Widget _filterSummary(int count) => Card(
    color: AppColors.mint,
    child: ListTile(
      leading: const Icon(Icons.filter_alt_rounded, color: AppColors.green),
      title: Text(
        '$count sheet(s) shown',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(_filterDescription),
      trailing: TextButton(
        onPressed: () => setState(() {
          _fromDate = null;
          _toDate = null;
          _statusFilter = _SheetListStatusFilter.all;
        }),
        child: const Text('Clear'),
      ),
    ),
  );

  String get _filterDescription {
    final date = _fromDate == null && _toDate == null
        ? 'Any date'
        : '${_fromDate == null ? 'Start' : DateFormat('dd MMM yyyy').format(_fromDate!)} – ${_toDate == null ? 'Today' : DateFormat('dd MMM yyyy').format(_toDate!)}';
    final status = switch (_statusFilter) {
      _SheetListStatusFilter.all => 'All statuses',
      _SheetListStatusFilter.draft => 'Draft / not submitted',
      _SheetListStatusFilter.submitted => 'Submitted',
    };
    return '$date · $status';
  }

  Future<void> _showFilters() async {
    DateTime? from = _fromDate;
    DateTime? to = _toDate;
    _SheetListStatusFilter status = _statusFilter;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Filter sheets'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _filterDateTile(
                    context,
                    'From date',
                    from,
                    (value) => setModalState(() => from = value),
                  ),
                  const SizedBox(height: 12),
                  _filterDateTile(
                    context,
                    'To date',
                    to,
                    (value) => setModalState(() => to = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_SheetListStatusFilter>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Sheet status',
                    ),
                    items: const <DropdownMenuItem<_SheetListStatusFilter>>[
                      DropdownMenuItem(
                        value: _SheetListStatusFilter.all,
                        child: Text('All statuses'),
                      ),
                      DropdownMenuItem(
                        value: _SheetListStatusFilter.draft,
                        child: Text('Draft / not submitted'),
                      ),
                      DropdownMenuItem(
                        value: _SheetListStatusFilter.submitted,
                        child: Text('Submitted'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => status = value ?? status),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => setModalState(() {
                from = null;
                to = null;
                status = _SheetListStatusFilter.all;
              }),
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: from != null && to != null && from!.isAfter(to!)
                  ? null
                  : () {
                      setState(() {
                        _fromDate = from;
                        _toDate = to;
                        _statusFilter = status;
                      });
                      Navigator.pop(dialogContext);
                    },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterDateTile(
    BuildContext context,
    String title,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) => Card(
    child: ListTile(
      leading: const Icon(Icons.calendar_month_rounded, color: AppColors.green),
      title: Text(title),
      subtitle: Text(
        value == null ? 'Any date' : DateFormat('dd MMM yyyy').format(value),
      ),
      trailing: value == null
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () => onChanged(null),
            ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: DateTime(2040),
          initialDate: value ?? DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
    ),
  );

  Widget _sheet(BuildContext context, SheetModel sheet) {
    final state = switch (sheet.syncStatus) {
      SheetSyncStatus.pending => SyncState.pending,
      SheetSyncStatus.synced => SyncState.synced,
      SheetSyncStatus.conflict => SyncState.conflict,
    };
    final detail = switch (sheet.status) {
      SheetStatus.draft => 'Draft - continue entry',
      SheetStatus.submitted => 'Submitted - tap to view or revise',
      SheetStatus.submittedIncomplete => 'Submitted as incomplete',
      SheetStatus.verified => 'Verified',
      SheetStatus.returned => 'Returned for correction',
    };
    final destination =
        sheet.status == SheetStatus.draft ||
            sheet.status == SheetStatus.returned
        ? '/temperature?sheetId=${sheet.id}'
        : '/summary?sheetId=${sheet.id}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go(destination),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd/MM/yyyy').format(sheet.date),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  SyncChip(state),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          displayShiftName(
                            _shiftNames[sheet.shiftId] ?? 'Shift tersimpan',
                          ),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SheetListStatusFilter { all, draft, submitted }
