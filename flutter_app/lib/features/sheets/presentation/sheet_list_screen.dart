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
      if (user != null) {
        final shared = await ref
            .read(sicatatRepositoryProvider)
            .listSharedSheets(
              teamId: user.role == UserRole.foreman ? user.teamId : null,
              createdBy: user.role == UserRole.crew ? user.id : null,
            );
        await LocalDatabase.instance.cacheRemoteSheets(shared);
      }
      final localSheets = await LocalDatabase.instance.listSheets();
      final sheets = switch (user?.role) {
        UserRole.admin || UserRole.supervisor => localSheets,
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
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
        _shiftNames = names;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Local sheet list could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final title =
        user?.role == UserRole.admin || user?.role == UserRole.supervisor
        ? 'All sheets'
        : user?.role == UserRole.foreman
        ? 'Team sheets'
        : 'My sheets';
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
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
              tooltip: 'Filter sheets',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go('/sheets/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New sheet'),
        ),
        body: RefreshIndicator(
          onRefresh: _loadSheets,
          child: _buildBody(context),
        ),
      ),
    );
  }

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
                  ? 'No sheets match this filter'
                  : 'No inspection sheets yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _hasFilter
                  ? 'Change or clear the filter to see other sheets.'
                  : 'Create a new sheet to start recording temperatures.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
      itemCount: sheets.length + (_hasFilter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (_hasFilter && index == 0) return _filterSummary(sheets.length);
        return _sheet(context, sheets[index - (_hasFilter ? 1 : 0)]);
      },
    );
  }

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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Wrap(
              runSpacing: 12,
              children: <Widget>[
                const Text(
                  'Filter sheets',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                _filterDateTile(
                  context,
                  'From date',
                  from,
                  (value) => setModalState(() => from = value),
                ),
                _filterDateTile(
                  context,
                  'To date',
                  to,
                  (value) => setModalState(() => to = value),
                ),
                DropdownButtonFormField<_SheetListStatusFilter>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Sheet status'),
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
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => setModalState(() {
                        from = null;
                        to = null;
                        status = _SheetListStatusFilter.all;
                      }),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed:
                          from != null && to != null && from!.isAfter(to!)
                          ? null
                          : () {
                              setState(() {
                                _fromDate = from;
                                _toDate = to;
                                _statusFilter = status;
                              });
                              Navigator.pop(dialogContext);
                            },
                      child: const Text('Apply filters'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
              Text(
                displayShiftName(_shiftNames[sheet.shiftId] ?? 'Saved shift'),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 9),
              Text(
                detail,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SheetListStatusFilter { all, draft, submitted }
