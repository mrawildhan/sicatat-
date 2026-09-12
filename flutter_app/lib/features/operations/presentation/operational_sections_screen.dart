import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/platform/file_download.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/material_request_models.dart';
import '../../../data/models/meeting_minute_models.dart';
import '../../../data/models/operational_budget_models.dart';
import '../../../data/models/preventive_maintenance_models.dart';
import '../../../data/reports/meeting_minute_service.dart';
import '../../../data/services/material_request_service.dart';
import '../../../data/services/operational_budget_service.dart';
import '../../../data/services/preventive_maintenance_service.dart';
import '../../auth/application/current_user_provider.dart';
import 'budget_item_sections.dart';

const TextStyle _budgetSectionTitleStyle = AppTextStyles.sectionTitle;
const TextStyle _budgetCardTitleStyle = AppTextStyles.cardTitle;
const TextStyle _budgetLabelStyle = AppTextStyles.supporting;
const TextStyle _budgetAmountStyle = AppTextStyles.metric;

class BudgetOverviewScreen extends StatefulWidget {
  const BudgetOverviewScreen({this.service, super.key});

  final OperationalBudgetService? service;

  @override
  State<BudgetOverviewScreen> createState() => _BudgetOverviewScreenState();
}

class _BudgetOverviewScreenState extends State<BudgetOverviewScreen> {
  OperationalBudgetService? _service;
  OperationalBudgetSummary? _summary;
  List<OperationalBudgetItem> _items = const <OperationalBudgetItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  OperationalBudgetService? _createService() {
    try {
      return OperationalBudgetService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  Future<void> _load({bool synchronizeSource = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service ??= widget.service ?? _createService();
      final OperationalBudgetService? service = _service;
      if (service == null) return;
      OperationalBudgetSummary summary = await service.loadSummary();
      List<OperationalBudgetItem> items = await service.loadItems();
      // The approved workbook is imported to the server as a snapshot. Reading
      // that snapshot keeps this screen fast and avoids reprocessing large
      // Excel files whenever the user opens the page.
      if (synchronizeSource || summary.months.isEmpty || items.isEmpty) {
        await service.synchronize();
        summary = await service.loadSummary();
        items = await service.loadItems();
      }
      if (mounted) {
        setState(() {
          _summary = summary;
          _items = items;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        final String message = error.toString().replaceFirst(
          'FormatException: ',
          '',
        );
        setState(() => _error = 'Anggaran belum dapat diperbarui. $message');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _OperationalSectionPage(
    title: 'Anggaran Operasional',
    icon: Icons.account_balance_wallet_rounded,
    child: _BudgetOverviewBody(
      summary: _summary,
      items: _items,
      loading: _loading,
      error: _error,
      onRefresh: _refreshSource,
      onBrowseItems: _browseItems,
      onOpenItem: _openItem,
      onOpenMonthly: _openMonthly,
    ),
  );

  Future<void> _browseItems() async {
    final OperationalBudgetItem? item = await showBudgetItemBrowser(
      context,
      _items,
    );
    if (item != null && mounted) await showBudgetItemDetail(context, item);
  }

  Future<void> _openItem(OperationalBudgetItem item) =>
      showBudgetItemDetail(context, item);

  Future<void> _openMonthly() async {
    final OperationalBudgetSummary? summary = _summary;
    if (summary != null) await showBudgetMonthlyDetail(context, summary);
  }

  Future<void> _refreshSource() => _load(synchronizeSource: true);
}

class MaterialRequestOverviewScreen extends ConsumerStatefulWidget {
  const MaterialRequestOverviewScreen({this.service, super.key});

  final MaterialRequestService? service;

  @override
  ConsumerState<MaterialRequestOverviewScreen> createState() =>
      _MaterialRequestOverviewScreenState();
}

class MaterialRequestFormScreen extends ConsumerStatefulWidget {
  const MaterialRequestFormScreen({this.service, super.key});

  final MaterialRequestService? service;

  @override
  ConsumerState<MaterialRequestFormScreen> createState() =>
      _MaterialRequestFormScreenState();
}

class _MaterialRequestOverviewScreenState
    extends ConsumerState<MaterialRequestOverviewScreen> {
  MaterialRequestService? _service;
  List<MaterialRequest> _items = const <MaterialRequest>[];
  bool _loading = true;
  String? _error;
  MaterialRequestStatus? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  MaterialRequestService? _createService() {
    try {
      return MaterialRequestService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service ??= widget.service ?? _createService();
      final MaterialRequestService? service = _service;
      if (service == null) {
        if (mounted) setState(() => _items = const <MaterialRequest>[]);
        return;
      }
      final List<MaterialRequest> items = await service.loadAll();
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Permintaan barang tidak dapat dimuat. Periksa koneksi lalu coba lagi.\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _process(MaterialRequest item, AppUser user) async {
    final _MaterialRequestDecision? decision =
        await showModalBottomSheet<_MaterialRequestDecision>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _MaterialRequestProcessSheet(item: item),
        );
    if (decision == null || !mounted) return;
    try {
      await (_service ??= widget.service ?? _createService())!.updateStatus(
        id: item.id,
        plannerId: user.id,
        status: decision.status,
        plannerNote: decision.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status ${decision.status.label.toLowerCase()} disimpan.',
          ),
        ),
      );
      await _load();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status belum tersimpan: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);
    return _OperationalSectionPage(
      title: 'Permintaan Barang',
      icon: Icons.handyman_outlined,
      child: _MaterialRequestOverviewBody(
        items: _items,
        loading: _loading,
        error: _error,
        selectedStatus: _selectedStatus,
        isPlanner: user?.role.canManageMaterialRequests == true,
        onRefresh: _load,
        onSelectStatus: (MaterialRequestStatus status) {
          setState(
            () => _selectedStatus = _selectedStatus == status ? null : status,
          );
        },
        onClearStatus: () => setState(() => _selectedStatus = null),
        onCreate: user == null
            ? null
            : () => context.go('/material-requests/new'),
        onProcess: user == null ? null : (item) => _process(item, user),
      ),
    );
  }
}

class OutstandingMaintenanceScreen extends StatefulWidget {
  const OutstandingMaintenanceScreen({this.service, super.key});

  final PreventiveMaintenanceService? service;

  @override
  State<OutstandingMaintenanceScreen> createState() =>
      _OutstandingMaintenanceScreenState();
}

class _OutstandingMaintenanceScreenState
    extends State<OutstandingMaintenanceScreen> {
  PreventiveMaintenanceService? _service;
  List<PreventiveMaintenanceWorkOrder> _items =
      const <PreventiveMaintenanceWorkOrder>[];
  List<CorrectiveMaintenanceWorkOrder> _correctiveItems =
      const <CorrectiveMaintenanceWorkOrder>[];
  bool _loading = true;
  String? _error;
  DateTime? _syncedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  PreventiveMaintenanceService? _createService() {
    try {
      return PreventiveMaintenanceService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service ??= widget.service ?? _createService();
      final PreventiveMaintenanceService? service = _service;
      if (service == null) {
        if (mounted) {
          setState(() => _items = const <PreventiveMaintenanceWorkOrder>[]);
        }
        return;
      }
      final PreventiveMaintenanceSyncResult sync = await service.synchronize();
      final List<PreventiveMaintenanceWorkOrder> items = await service
          .loadOutstanding();
      final List<CorrectiveMaintenanceWorkOrder> correctiveItems = await service
          .loadCorrectiveOutstanding();
      if (mounted) {
        setState(() {
          _items = items;
          _correctiveItems = correctiveItems;
          _syncedAt = sync.updatedAt;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Data PM belum dapat diperbarui. Periksa koneksi lalu coba lagi.\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPmSection(String crew, String site) {
    final List<PreventiveMaintenanceWorkOrder> items = _items
        .where((item) => item.crew == crew && item.site == site)
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PreventiveMaintenanceListSheet(
        title: 'PM Crew $crew · $site',
        items: items,
      ),
    );
  }

  void _openCmSection(String site) {
    final List<CorrectiveMaintenanceWorkOrder> items = _correctiveItems
        .where((item) => item.site == site)
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CorrectiveMaintenanceListSheet(site: site, items: items),
    );
  }

  @override
  Widget build(BuildContext context) => _OperationalSectionPage(
    title: 'Outstanding PM & CM',
    icon: Icons.pending_actions_outlined,
    child: _OutstandingMaintenanceBody(
      items: _items,
      correctiveItems: _correctiveItems,
      loading: _loading,
      error: _error,
      syncedAt: _syncedAt,
      onRefresh: _load,
      onOpenPmSection: _openPmSection,
      onOpenCmSection: _openCmSection,
    ),
  );
}

class MeetingMinutesScreen extends ConsumerStatefulWidget {
  const MeetingMinutesScreen({this.service, super.key});

  final MeetingMinuteService? service;

  @override
  ConsumerState<MeetingMinutesScreen> createState() =>
      _MeetingMinutesScreenState();
}

class _MeetingMinutesScreenState extends ConsumerState<MeetingMinutesScreen> {
  MeetingMinuteService? _service;
  List<MeetingMinute> _items = const <MeetingMinute>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _service ??= widget.service ?? _createService();
      final MeetingMinuteService? service = _service;
      if (service == null) {
        if (mounted) setState(() => _items = const <MeetingMinute>[]);
        return;
      }
      final List<MeetingMinute> items = await service.loadAll();
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to load meeting minutes. Check your connection and try again.\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  MeetingMinuteService? _createService() {
    try {
      return MeetingMinuteService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int draftCount = _items
        .where((MeetingMinute item) => item.status == MeetingMinuteStatus.draft)
        .length;
    final int completedCount = _items.length - draftCount;
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: const Text('Meeting Minutes'),
              ),
        floatingActionButton: _loading
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.go('/meeting-minutes/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create minutes'),
              ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              desktop ? 18 : 20,
              20,
              130 + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              if (desktop) ...<Widget>[
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.assignment_rounded,
                      color: AppColors.green,
                      size: 28,
                    ),
                    SizedBox(width: 10),
                    Text('Meeting Minutes', style: AppTextStyles.pageTitle),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              const Text(
                'Inspection and field meeting minutes',
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 6),
              const Text(
                'Create minutes, save a draft, then complete and export to Excel. Due dates are optional.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _MeetingStatusChip(
                    label: 'Draft',
                    count: '$draftCount',
                    color: AppColors.orange,
                  ),
                  _MeetingStatusChip(
                    label: 'Completed',
                    count: '$completedCount',
                    color: AppColors.green,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _MeetingNotice(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load minutes',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _load,
                )
              else if (_items.isEmpty)
                _MeetingNotice(
                  icon: Icons.edit_note_rounded,
                  title: 'No meeting minutes yet',
                  message: 'Record meeting details, attendees, issues and action plans.',
                  actionLabel: 'Start minutes',
                  onAction: () => context.go('/meeting-minutes/new'),
                )
              else
                ..._items.map(
                  (MeetingMinute item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MeetingMinuteTile(
                      item: item,
                      onTap: () => context.go('/meeting-minutes/${item.id}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationalSectionPage extends StatelessWidget {
  const _OperationalSectionPage({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useDesktopHeader = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: Text(title),
              ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            useDesktopHeader ? 18 : 20,
            20,
            120 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            if (useDesktopHeader) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: AppColors.green, size: 28),
                  const SizedBox(width: 10),
                  Text(title, style: AppTextStyles.pageTitle),
                ],
              ),
              const SizedBox(height: 20),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _BudgetOverviewBody extends StatelessWidget {
  const _BudgetOverviewBody({
    required this.summary,
    required this.items,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onBrowseItems,
    required this.onOpenItem,
    required this.onOpenMonthly,
  });

  final OperationalBudgetSummary? summary;
  final List<OperationalBudgetItem> items;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onBrowseItems;
  final ValueChanged<OperationalBudgetItem> onOpenItem;
  final Future<void> Function() onOpenMonthly;

  @override
  Widget build(BuildContext context) {
    final OperationalBudgetSummary? summary = this.summary;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return _BudgetNotice(message: error!, onRefresh: onRefresh);
    }
    if (summary == null || summary.months.isEmpty) {
      return _BudgetNotice(
        message: 'Data anggaran Asam-Asam belum tersedia.',
        onRefresh: onRefresh,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Asam-Asam', style: _budgetSectionTitleStyle),
                  SizedBox(height: 4),
                  Text(
                    'Budget dan aktual USD · Januari–Juni 2026',
                    style: _budgetLabelStyle,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Perbarui data',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BudgetMetricLayout(
          budget: summary.budgetUsd,
          actual: summary.actualUsd,
        ),
        const SizedBox(height: 18),
        const Text('Ringkasan per lokasi', style: _budgetSectionTitleStyle),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _BudgetSiteCard(
                site: 'CPP',
                months: summary.forSite('CPP'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BudgetSiteCard(
                site: 'PORT',
                months: summary.forSite('PORT'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _BudgetActionCard(
          icon: Icons.calendar_month_rounded,
          title: 'Realisasi per bulan',
          subtitle: 'Lihat budget, aktual, dan sisa tiap bulan',
          onTap: onOpenMonthly,
        ),
        const SizedBox(height: 10),
        _BudgetActionCard(
          icon: Icons.search_rounded,
          title: 'Rincian anggaran',
          subtitle: items.isEmpty
              ? 'Data item akan tersedia setelah diperbarui'
              : 'Cari item, pemakaian terbesar, atau overbudget',
          onTap: items.isEmpty ? null : onBrowseItems,
        ),
        const SizedBox(height: 14),
        _BudgetSourceCard(syncedAt: summary.syncedAt),
      ],
    );
  }
}

class _BudgetNotice extends StatelessWidget {
  const _BudgetNotice({required this.message, required this.onRefresh});

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, color: AppColors.orange),
          const SizedBox(height: 12),
          const Text(
            'Anggaran belum dapat dimuat',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    ),
  );
}

class _BudgetSiteCard extends StatelessWidget {
  const _BudgetSiteCard({required this.site, required this.months});

  final String site;
  final List<OperationalBudgetMonth> months;

  @override
  Widget build(BuildContext context) {
    final double budget = months.fold(
      0,
      (total, item) => total + item.budgetUsd,
    );
    final double actual = months.fold(
      0,
      (total, item) => total + item.actualUsd,
    );
    final double remaining = budget - actual;
    final double usage = budget <= 0
        ? 0
        : (actual / budget).clamp(0, 1).toDouble();
    final bool overBudget = actual > budget;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: AppColors.mint,
                  child: Text(
                    site == 'CPP' ? 'C' : 'P',
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  site == 'CPP' ? 'CPP' : 'PORT',
                  style: _budgetCardTitleStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_usd(actual), style: _budgetAmountStyle),
            ),
            const SizedBox(height: 2),
            Text(
              'dari ${_usd(budget)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _budgetLabelStyle,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: usage,
                minHeight: 8,
                backgroundColor: AppColors.mint,
                color: overBudget ? AppColors.danger : AppColors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overBudget
                  ? 'Melebihi ${_usd(actual - budget)}'
                  : 'Sisa ${_usd(remaining)}',
              style: TextStyle(
                color: overBudget ? AppColors.danger : AppColors.green,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetActionCard extends StatelessWidget {
  const _BudgetActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Icon(icon, color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: _budgetCardTitleStyle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: _budgetLabelStyle),
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

class _BudgetSourceCard extends StatelessWidget {
  const _BudgetSourceCard({this.syncedAt});

  final DateTime? syncedAt;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: AppColors.mint,
        child: Icon(Icons.table_chart_outlined, color: AppColors.green),
      ),
      title: const Text('Sumber data', style: _budgetCardTitleStyle),
      subtitle: Text(
        syncedAt == null
            ? 'Budget 3271/3275 dan aktual CPP/PORT'
            : 'Diperbarui ${DateFormat('dd/MM/yyyy HH:mm').format(syncedAt!.toLocal())}',
        style: _budgetLabelStyle,
      ),
    ),
  );
}

String _usd(double value) =>
    'US\$${NumberFormat.decimalPattern('id_ID').format(value.round())}';

class _MaterialRequestOverviewBody extends StatelessWidget {
  const _MaterialRequestOverviewBody({
    required this.items,
    required this.loading,
    required this.error,
    required this.selectedStatus,
    required this.isPlanner,
    required this.onRefresh,
    required this.onSelectStatus,
    required this.onClearStatus,
    required this.onCreate,
    required this.onProcess,
  });

  final List<MaterialRequest> items;
  final bool loading;
  final String? error;
  final MaterialRequestStatus? selectedStatus;
  final bool isPlanner;
  final Future<void> Function() onRefresh;
  final ValueChanged<MaterialRequestStatus> onSelectStatus;
  final VoidCallback onClearStatus;
  final VoidCallback? onCreate;
  final ValueChanged<MaterialRequest>? onProcess;

  @override
  Widget build(BuildContext context) {
    final MaterialRequestStatus? selectedStatus = this.selectedStatus;
    final int submitted = items
        .where((item) => item.status == MaterialRequestStatus.submitted)
        .length;
    final int processed = items
        .where((item) => item.status == MaterialRequestStatus.processed)
        .length;
    final int rejected = items
        .where((item) => item.status == MaterialRequestStatus.rejected)
        .length;
    final List<MaterialRequest> visibleItems = selectedStatus == null
        ? items
        : items
              .where((item) => item.status == selectedStatus)
              .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Ajukan kebutuhan barang'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ringkasan status',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        const Text(
          'Tekan status untuk melihat pengajuan yang sesuai.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _RequestStatusCard(
                    label: 'Diajukan',
                    count: submitted,
                    icon: Icons.send_outlined,
                    color: AppColors.orange,
                    selected: selectedStatus == MaterialRequestStatus.submitted,
                    onTap: () =>
                        onSelectStatus(MaterialRequestStatus.submitted),
                  ),
                ),
                _StatusDivider(),
                Expanded(
                  child: _RequestStatusCard(
                    label: 'Diproses',
                    count: processed,
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.green,
                    selected: selectedStatus == MaterialRequestStatus.processed,
                    onTap: () =>
                        onSelectStatus(MaterialRequestStatus.processed),
                  ),
                ),
                _StatusDivider(),
                Expanded(
                  child: _RequestStatusCard(
                    label: 'Ditolak',
                    count: rejected,
                    icon: Icons.cancel_outlined,
                    color: AppColors.danger,
                    selected: selectedStatus == MaterialRequestStatus.rejected,
                    onTap: () => onSelectStatus(MaterialRequestStatus.rejected),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                selectedStatus == null
                    ? (isPlanner ? 'Semua pengajuan' : 'Pengajuan saya')
                    : 'Pengajuan: ${selectedStatus.label}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (selectedStatus != null)
              TextButton(onPressed: onClearStatus, child: const Text('Semua')),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          selectedStatus == null
              ? (isPlanner
                    ? 'Pilih pengajuan untuk memperbarui prosesnya.'
                    : 'Pantau perkembangan kebutuhan yang sudah Anda kirim.')
              : 'Hanya pengajuan berstatus ${selectedStatus.label.toLowerCase()} yang ditampilkan.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null)
          _MaterialRequestNotice(
            icon: Icons.cloud_off_outlined,
            title: 'Pengajuan belum dapat dimuat',
            message: error!,
            actionLabel: 'Coba lagi',
            onAction: onRefresh,
          )
        else if (visibleItems.isEmpty)
          _MaterialRequestNotice(
            icon: Icons.inventory_2_outlined,
            title: selectedStatus == null
                ? 'Belum ada pengajuan'
                : 'Belum ada pengajuan ${selectedStatus.label.toLowerCase()}',
            message: selectedStatus == null
                ? 'Ajukan barang atau alat untuk mencatat kebutuhan pekerjaan Anda.'
                : 'Pilih status lain atau tampilkan semua pengajuan.',
            actionLabel: selectedStatus == null
                ? 'Ajukan barang'
                : 'Tampilkan semua',
            onAction: selectedStatus == null ? onCreate : onClearStatus,
          )
        else
          ...visibleItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MaterialRequestTile(
                item: item,
                showRequester: isPlanner,
                onProcess: isPlanner ? () => onProcess?.call(item) : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _OutstandingMaintenanceBody extends StatelessWidget {
  const _OutstandingMaintenanceBody({
    required this.items,
    required this.correctiveItems,
    required this.loading,
    required this.error,
    required this.syncedAt,
    required this.onRefresh,
    required this.onOpenPmSection,
    required this.onOpenCmSection,
  });

  final List<PreventiveMaintenanceWorkOrder> items;
  final List<CorrectiveMaintenanceWorkOrder> correctiveItems;
  final bool loading;
  final String? error;
  final DateTime? syncedAt;
  final Future<void> Function() onRefresh;
  final void Function(String crew, String site) onOpenPmSection;
  final ValueChanged<String> onOpenCmSection;

  int _countPm(String crew, String site) =>
      items.where((item) => item.crew == crew && item.site == site).length;

  int _countCm(String site) =>
      correctiveItems.where((item) => item.site == site).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('PM per crew & lokasi', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 5),
        const Text(
          'Pilih crew untuk membuka daftar PM layar penuh.',
          style: TextStyle(color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null)
          _OutstandingPmNotice(message: error!, onRetry: onRefresh)
        else ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _MaintenanceLocationGroup(
                  site: 'CPP',
                  children: <Widget>[
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew A',
                      count: _countPm('A', 'CPP'),
                      onTap: () => onOpenPmSection('A', 'CPP'),
                    ),
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew B',
                      count: _countPm('B', 'CPP'),
                      onTap: () => onOpenPmSection('B', 'CPP'),
                    ),
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew C',
                      count: _countPm('C', 'CPP'),
                      onTap: () => onOpenPmSection('C', 'CPP'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MaintenanceLocationGroup(
                  site: 'PORT',
                  children: <Widget>[
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew A',
                      count: _countPm('A', 'PORT'),
                      onTap: () => onOpenPmSection('A', 'PORT'),
                    ),
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew B',
                      count: _countPm('B', 'PORT'),
                      onTap: () => onOpenPmSection('B', 'PORT'),
                    ),
                    _MaintenanceGroupCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Crew C',
                      count: _countPm('C', 'PORT'),
                      onTap: () => onOpenPmSection('C', 'PORT'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('CM per lokasi', style: AppTextStyles.cardTitle),
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(
                child: _MaintenanceGroupCard(
                  icon: Icons.build_circle_outlined,
                  title: 'CM CPP',
                  count: _countCm('CPP'),
                  onTap: () => onOpenCmSection('CPP'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MaintenanceGroupCard(
                  icon: Icons.build_circle_outlined,
                  title: 'CM PORT',
                  count: _countCm('PORT'),
                  onTap: () => onOpenCmSection('PORT'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RequestStatusCard extends StatelessWidget {
  const _RequestStatusCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Filter: $label',
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: color.withValues(alpha: 0.45))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 7),
            Text(
              '$count',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 54, color: AppColors.line);
}

class _MaterialRequestNotice extends StatelessWidget {
  const _MaterialRequestNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppColors.green, size: 30),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(message, style: const TextStyle(color: AppColors.muted)),
          if (onAction != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    ),
  );
}

class _MaterialRequestTile extends StatelessWidget {
  const _MaterialRequestTile({
    required this.item,
    required this.showRequester,
    this.onProcess,
  });

  final MaterialRequest item;
  final bool showRequester;
  final VoidCallback? onProcess;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _MaterialRequestDetailSheet(
          item: item,
          showRequester: showRequester,
          onProcess: onProcess,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.green,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MaterialRequestStatusChip(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_quantityText(item.quantity)} ${item.unit} • ${item.area.label} • ${item.needType.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
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

class _MaterialRequestDetailSheet extends StatelessWidget {
  const _MaterialRequestDetailSheet({
    required this.item,
    required this.showRequester,
    this.onProcess,
  });

  final MaterialRequest item;
  final bool showRequester;
  final VoidCallback? onProcess;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .64,
      maxChildSize: .9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  item.itemName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MaterialRequestStatusChip(status: item.status),
            ],
          ),
          const SizedBox(height: 18),
          _detailRow('Jumlah', '${_quantityText(item.quantity)} ${item.unit}'),
          _detailRow('Area', item.area.label),
          _detailRow('Jenis kebutuhan', item.needType.label),
          if (showRequester && item.requesterName != null)
            _detailRow('Diajukan oleh', item.requesterName!),
          const SizedBox(height: 14),
          const Text(
            'Alasan kebutuhan',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(item.reason, style: const TextStyle(height: 1.4)),
          if (item.plannerNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Catatan planner: ${item.plannerNote}'),
            ),
          ],
          if (onProcess != null) ...<Widget>[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onProcess!();
              },
              icon: const Icon(Icons.task_alt_outlined),
              label: Text(
                item.status == MaterialRequestStatus.submitted
                    ? 'Proses pengajuan'
                    : 'Ubah status',
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 116,
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

class _MaterialRequestStatusChip extends StatelessWidget {
  const _MaterialRequestStatusChip({required this.status});

  final MaterialRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      MaterialRequestStatus.submitted => AppColors.orange,
      MaterialRequestStatus.processed => AppColors.green,
      MaterialRequestStatus.rejected => AppColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MaterialRequestProcessSheet extends StatefulWidget {
  const _MaterialRequestProcessSheet({required this.item});

  final MaterialRequest item;

  @override
  State<_MaterialRequestProcessSheet> createState() =>
      _MaterialRequestProcessSheetState();
}

class _MaterialRequestProcessSheetState
    extends State<_MaterialRequestProcessSheet> {
  late MaterialRequestStatus _status;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _status = widget.item.status == MaterialRequestStatus.rejected
        ? MaterialRequestStatus.rejected
        : MaterialRequestStatus.processed;
    _note = TextEditingController(text: widget.item.plannerNote);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Proses ${widget.item.itemName}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          '${_quantityText(widget.item.quantity)} ${widget.item.unit} • ${widget.item.area.label}',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<MaterialRequestStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items:
              const <MaterialRequestStatus>[
                    MaterialRequestStatus.processed,
                    MaterialRequestStatus.rejected,
                  ]
                  .map(
                    (status) => DropdownMenuItem<MaterialRequestStatus>(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(growable: false),
          onChanged: (value) {
            if (value != null) setState(() => _status = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Catatan planner',
            hintText: 'Contoh: sedang dicarikan supplier atau alasan penolakan',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _MaterialRequestDecision(status: _status, note: _note.text),
            ),
            child: const Text('Simpan status'),
          ),
        ),
      ],
    ),
  );
}

class _MaterialRequestDecision {
  const _MaterialRequestDecision({required this.status, required this.note});

  final MaterialRequestStatus status;
  final String note;
}

String _quantityText(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _MaterialRequestFormScreenState
    extends ConsumerState<MaterialRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemName = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: 'unit');
  final _reason = TextEditingController();
  MaterialRequestArea _area = MaterialRequestArea.lv;
  MaterialNeedType _needType = MaterialNeedType.replacement;
  bool _saving = false;

  @override
  void dispose() {
    _itemName.dispose();
    _quantity.dispose();
    _unit.dispose();
    _reason.dispose();
    super.dispose();
  }

  MaterialRequestService? _createService() {
    try {
      return MaterialRequestService(Supabase.instance.client);
    } on AssertionError {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final AppUser? user = ref.read(currentUserProvider);
    if (user == null) return;
    final num? quantity = num.tryParse(
      _quantity.text.trim().replaceAll(',', '.'),
    );
    if (quantity == null || quantity <= 0) return;
    setState(() => _saving = true);
    try {
      final MaterialRequestService? service =
          widget.service ?? _createService();
      if (service == null) {
        throw const FormatException('Layanan pengajuan belum tersedia.');
      }
      await service.submit(
        actorId: user.id,
        area: _area,
        itemName: _itemName.text,
        quantity: quantity,
        unit: _unit.text,
        needType: _needType,
        reason: _reason.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengajuan barang berhasil dikirim.')),
      );
      context.go('/material-requests');
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pengajuan belum terkirim: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/material-requests',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/material-requests'),
        title: const Text('Ajukan Barang'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            120 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            const Text(
              'Ajukan kebutuhan barang',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Isi kebutuhan dengan jelas agar planner dapat menentukan tindak lanjutnya.',
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<MaterialRequestArea>(
              initialValue: _area,
              decoration: const InputDecoration(labelText: 'Area pekerjaan'),
              items: MaterialRequestArea.values
                  .map(
                    (area) => DropdownMenuItem<MaterialRequestArea>(
                      value: area,
                      child: Text(area.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _area = value);
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _itemName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama barang atau alat',
                hintText: 'Contoh: Ban unit kendaraan ringan',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nama barang atau alat wajib diisi.'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _quantity,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Jumlah'),
                    validator: (value) {
                      final num? amount = num.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      return amount == null || amount <= 0
                          ? 'Jumlah harus lebih dari 0.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _unit,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Satuan',
                      hintText: 'unit, pcs, set',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Satuan wajib diisi.'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MaterialNeedType>(
              initialValue: _needType,
              decoration: const InputDecoration(labelText: 'Kondisi kebutuhan'),
              items: MaterialNeedType.values
                  .map(
                    (needType) => DropdownMenuItem<MaterialNeedType>(
                      value: needType,
                      child: Text(needType.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _needType = value);
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              enabled: !_saving,
              minLines: 4,
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Alasan kebutuhan',
                hintText:
                    'Jelaskan kondisi barang dan dampaknya terhadap pekerjaan.',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Alasan kebutuhan wajib diisi.'
                  : null,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Kirim pengajuan'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MaintenanceLocationGroup extends StatelessWidget {
  const _MaintenanceLocationGroup({required this.site, required this.children});

  final String site;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          site,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      ...children.map(
        (Widget child) =>
            Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ),
    ],
  );
}

class _MaintenanceGroupCard extends StatelessWidget {
  const _MaintenanceGroupCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.mint,
                child: Icon(icon, color: AppColors.green, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 36),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OutstandingPmNotice extends StatelessWidget {
  const _OutstandingPmNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.orange.withValues(alpha: 0.22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Row(
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: AppColors.orange),
            SizedBox(width: 9),
            Text(
              'Daftar PM belum tersedia',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(height: 1.4)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Coba lagi'),
        ),
      ],
    ),
  );
}

enum _PmDateOrder { oldest, newest }

class _PreventiveMaintenanceListSheet extends StatefulWidget {
  const _PreventiveMaintenanceListSheet({
    required this.title,
    required this.items,
  });

  final String title;
  final List<PreventiveMaintenanceWorkOrder> items;

  @override
  State<_PreventiveMaintenanceListSheet> createState() =>
      _PreventiveMaintenanceListSheetState();
}

class _PreventiveMaintenanceListSheetState
    extends State<_PreventiveMaintenanceListSheet> {
  _PmDateOrder _dateOrder = _PmDateOrder.oldest;
  String _searchQuery = '';

  DateTime? _sortDate(PreventiveMaintenanceWorkOrder item) =>
      item.plannedStartOn ?? item.raisedOn;

  List<PreventiveMaintenanceWorkOrder> get _filteredItems {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where((PreventiveMaintenanceWorkOrder item) {
          final String searchableText = <String>[
            item.workOrder,
            item.description,
            item.equipmentReference,
            item.crew,
            item.site,
            item.assignedTo ?? '',
            item.assignedToDescription ?? '',
            item.priority ?? '',
            item.priorityDescription ?? '',
          ].join(' ').toLowerCase();
          return searchableText.contains(query);
        })
        .toList(growable: false);
  }

  List<PreventiveMaintenanceWorkOrder> get _sortedItems {
    final List<PreventiveMaintenanceWorkOrder> result = List.of(_filteredItems);
    result.sort((a, b) {
      final DateTime? first = _sortDate(a);
      final DateTime? second = _sortDate(b);
      if (first == null && second == null) {
        return a.workOrder.compareTo(b.workOrder);
      }
      if (first == null) return 1;
      if (second == null) return -1;
      final int comparison = first.compareTo(second);
      return _dateOrder == _PmDateOrder.oldest ? comparison : -comparison;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: 0.72,
      maxChildSize: 1,
      builder: (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenDark,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_filteredItems.length} dari ${widget.items.length} work order outstanding',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              onChanged: (String value) => setState(() => _searchQuery = value),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Cari work order, pekerjaan, aset, crew, atau lokasi',
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.green),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_PmDateOrder>(
                value: _dateOrder,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(Icons.unfold_more_rounded, size: 18),
                onChanged: (_PmDateOrder? value) {
                  if (value != null) setState(() => _dateOrder = value);
                },
                items: const <DropdownMenuItem<_PmDateOrder>>[
                  DropdownMenuItem(
                    value: _PmDateOrder.oldest,
                    child: Text('Tanggal: terlama'),
                  ),
                  DropdownMenuItem(
                    value: _PmDateOrder.newest,
                    child: Text('Tanggal: terbaru'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_sortedItems.isEmpty)
            const _EmptyPmList()
          else
            ..._sortedItems.map(
              (PreventiveMaintenanceWorkOrder item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _PreventiveMaintenanceTile(item: item),
              ),
            ),
        ],
      ),
    ),
  );
}

class _EmptyPmList extends StatelessWidget {
  const _EmptyPmList();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text('Tidak ada PM outstanding yang sesuai pencarian.'),
    ),
  );
}

class _CorrectiveMaintenanceListSheet extends StatefulWidget {
  const _CorrectiveMaintenanceListSheet({
    required this.site,
    required this.items,
  });

  final String site;
  final List<CorrectiveMaintenanceWorkOrder> items;

  @override
  State<_CorrectiveMaintenanceListSheet> createState() =>
      _CorrectiveMaintenanceListSheetState();
}

class _CorrectiveMaintenanceListSheetState
    extends State<_CorrectiveMaintenanceListSheet> {
  String _searchQuery = '';

  List<CorrectiveMaintenanceWorkOrder> get _filteredItems =>
      _searchQuery.trim().isEmpty
      ? widget.items
      : widget.items
            .where((CorrectiveMaintenanceWorkOrder item) {
              final String query = _searchQuery.trim().toLowerCase();
              final String searchableText = <String>[
                item.workOrder,
                item.description,
                item.equipmentReference,
                item.site,
                item.priority ?? '',
                item.progress ?? '',
              ].join(' ').toLowerCase();
              return searchableText.contains(query);
            })
            .toList(growable: false);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: 0.72,
      maxChildSize: 1,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenDark,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.build_circle_outlined,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'CM ${widget.site}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_filteredItems.length} dari ${widget.items.length} work order outstanding',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              onChanged: (String value) => setState(() => _searchQuery = value),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Cari nama, pekerjaan, aset, atau lokasi',
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.green),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_filteredItems.isEmpty)
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tidak ada work order yang sesuai pencarian.'),
              ),
            ),
          for (final item in _filteredItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CorrectiveMaintenanceTile(item: item),
            ),
        ],
      ),
    ),
  );
}

class _PreventiveMaintenanceTile extends StatelessWidget {
  const _PreventiveMaintenanceTile({required this.item});

  final PreventiveMaintenanceWorkOrder item;

  @override
  Widget build(BuildContext context) {
    final String assigned =
        item.assignedToDescription?.trim().isNotEmpty == true
        ? item.assignedToDescription!
        : item.assignedTo ?? 'Belum ditentukan';
    final String? priority = item.priorityDescription ?? item.priority;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.workOrder,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (priority != null && priority.trim().isNotEmpty)
                  _PmPriorityChip(label: priority),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              item.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 7),
            Row(
              children: <Widget>[
                Expanded(
                  child: _PmDetail(
                    icon: Icons.precision_manufacturing_outlined,
                    text: item.equipmentReference,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PmDetail(
                    icon: Icons.event_outlined,
                    text: item.plannedStartOn == null
                        ? 'Belum dijadwalkan'
                        : _pmShortDate(item.plannedStartOn!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _PmDetail(icon: Icons.person_outline_rounded, text: assigned),
            const SizedBox(height: 4),
            _PmDetail(
              icon: Icons.location_on_outlined,
              text: '${item.site} • Crew ${item.crew}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PmPriorityChip extends StatelessWidget {
  const _PmPriorityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.orange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.orange,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _PmDetail extends StatelessWidget {
  const _PmDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    ],
  );
}

class _CorrectiveMaintenanceTile extends StatelessWidget {
  const _CorrectiveMaintenanceTile({required this.item});

  final CorrectiveMaintenanceWorkOrder item;

  @override
  Widget build(BuildContext context) {
    final String progress = item.progress?.trim().isNotEmpty == true
        ? item.progress!
        : 'Belum ada keterangan progres.';
    return Card(
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
                    item.workOrder,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (item.priority?.trim().isNotEmpty == true)
                  _CmPriorityChip(label: item.priority!),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _PmDetail(
                    icon: Icons.precision_manufacturing_outlined,
                    text: item.equipmentReference,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PmDetail(
                    icon: Icons.event_outlined,
                    text: item.raisedOn == null
                        ? 'Tanggal belum ada'
                        : _pmShortDate(item.raisedOn!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.timeline_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'PROGRES TERAKHIR',
                          style: TextStyle(
                            color: AppColors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          progress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ],
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

class _CmPriorityChip extends StatelessWidget {
  const _CmPriorityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bool critical = label.toUpperCase().startsWith('P1');
    final Color color = critical ? AppColors.danger : AppColors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BudgetMetricLayout extends StatelessWidget {
  const _BudgetMetricLayout({this.budget = 0, this.actual = 0});

  final double budget;
  final double actual;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: _BudgetMetricCard(
          label: 'Anggaran',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.green,
          value: _usd(budget),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _BudgetMetricCard(
          label: 'Aktual',
          icon: Icons.receipt_long_outlined,
          color: AppColors.orange,
          value: _usd(actual),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _BudgetMetricCard(
          label: 'Sisa anggaran',
          icon: Icons.savings_outlined,
          color: actual > budget ? AppColors.danger : AppColors.greenDark,
          value: _usd(budget - actual),
        ),
      ),
    ],
  );
}

class _BudgetMetricCard extends StatelessWidget {
  const _BudgetMetricCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _budgetLabelStyle,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: _budgetAmountStyle),
          ),
        ],
      ),
    ),
  );
}

class _MeetingStatusChip extends StatelessWidget {
  const _MeetingStatusChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final String count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      '$label  $count',
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}

class _MeetingNotice extends StatelessWidget {
  const _MeetingNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.mint,
            child: Icon(icon, color: AppColors.green, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _MeetingMinuteTile extends StatelessWidget {
  const _MeetingMinuteTile({required this.item, required this.onTap});

  final MeetingMinute item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDraft = item.status == MeetingMinuteStatus.draft;
    final String date = item.meetingDate == null
        ? 'Date not set'
        : _momDate(item.meetingDate!);
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: isDraft
              ? AppColors.orange.withValues(alpha: 0.13)
              : AppColors.mint,
          child: Icon(
            isDraft ? Icons.edit_note_rounded : Icons.task_alt_rounded,
            color: isDraft ? AppColors.orange : AppColors.green,
          ),
        ),
        title: Text(
          item.title.trim().isEmpty ? 'Untitled minutes' : item.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            item.followUpSource == null
                ? '$date • ${item.actions.length} action plans'
                : '$date • Follow-up of ${item.followUpSource!.title.trim().isEmpty ? 'previous minutes' : item.followUpSource!.title}',
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            _MeetingBadge(status: item.status),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _MeetingBadge extends StatelessWidget {
  const _MeetingBadge({required this.status});

  final MeetingMinuteStatus status;

  @override
  Widget build(BuildContext context) {
    final bool draft = status == MeetingMinuteStatus.draft;
    final Color color = draft ? AppColors.orange : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class MeetingMinuteEditorScreen extends ConsumerStatefulWidget {
  const MeetingMinuteEditorScreen({this.meetingId, this.followUpOf, super.key});

  final String? meetingId;
  final String? followUpOf;

  @override
  ConsumerState<MeetingMinuteEditorScreen> createState() =>
      _MeetingMinuteEditorScreenState();
}

class _MeetingMinuteEditorScreenState
    extends ConsumerState<MeetingMinuteEditorScreen> {
  final MeetingMinuteService _service = MeetingMinuteService(
    Supabase.instance.client,
  );
  final TextEditingController _title = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _attendees = TextEditingController();
  final TextEditingController _apologies = TextEditingController();
  final TextEditingController _minuteTaker = TextEditingController();
  final TextEditingController _distribution = TextEditingController();
  final TextEditingController _agenda = TextEditingController();
  final TextEditingController _proposedBy = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_ActionDraft> _actions = <_ActionDraft>[];
  MeetingMinute? _minute;
  MeetingMinute? _followUpSource;
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.meetingId == null;
  bool get _isFollowUp => _isNew && widget.followUpOf != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _attendees.dispose();
    _apologies.dispose();
    _minuteTaker.dispose();
    _distribution.dispose();
    _agenda.dispose();
    _proposedBy.dispose();
    _note.dispose();
    for (final _ActionDraft action in _actions) {
      action.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_isNew) {
        if (_isFollowUp) {
          final MeetingMinute source = await _service.loadOne(
            widget.followUpOf!,
          );
          _followUpSource = source;
          _date = DateTime.now().add(const Duration(days: 7));
          _title.text = source.title.trim().isEmpty
              ? 'Follow-up minutes'
              : '${source.title.trim()} - Follow-up';
          _location.text = source.location;
          _attendees.text = source.attendees;
          _apologies.text = source.apologies;
          _minuteTaker.text = source.minuteTaker.isEmpty
              ? (ref.read(currentUserProvider)?.name ?? '')
              : source.minuteTaker;
          _distribution.text = source.distributionList;
          _agenda.text = source.newBusinessAgenda;
          _proposedBy.text = source.proposedBy;
          _note.text =
              'Follow-up of ${source.title.trim().isEmpty ? 'previous minutes' : source.title.trim()}.';
          _actions.addAll(
            source.actions.map(
              (MeetingMinuteAction action) => _ActionDraft(
                itemDate: action.itemDate,
                issueDescription: action.issueDescription,
                subject: action.subjectDiscussion,
                assignedTo: action.assignedTo,
                dueDate: action.dueDate,
                progressRemark: action.progressRemark,
              ),
            ),
          );
        } else {
          _date = DateTime.now();
          _minuteTaker.text = ref.read(currentUserProvider)?.name ?? '';
        }
        if (_actions.isEmpty) _actions.add(_ActionDraft(itemDate: _date));
      } else {
        final MeetingMinute minute = await _service.loadOne(widget.meetingId!);
        _minute = minute;
        _title.text = minute.title;
        _date = minute.meetingDate;
        _startTime = _parseTime(minute.startTime);
        _endTime = _parseTime(minute.endTime);
        _location.text = minute.location;
        _attendees.text = minute.attendees;
        _apologies.text = minute.apologies;
        _minuteTaker.text = minute.minuteTaker;
        _distribution.text = minute.distributionList;
        _agenda.text = minute.newBusinessAgenda;
        _proposedBy.text = minute.proposedBy;
        _note.text = minute.note;
        _actions.addAll(minute.actions.map(_ActionDraft.fromModel));
        if (_actions.isEmpty) _actions.add(_ActionDraft(itemDate: _date));
      }
    } on Object catch (error) {
      _error = 'Unable to open minutes. $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final List<String> parts = raw.split(':');
    if (parts.length < 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDate({required bool main, int? actionIndex}) async {
    final DateTime initial = main
        ? (_date ?? DateTime.now())
        : (_actions[actionIndex!].itemDate ?? _date ?? DateTime.now());
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: main ? 'Select meeting date' : 'Select date raised',
      locale: const Locale('en'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (main) {
        _date = picked;
      } else {
        _actions[actionIndex!].itemDate = picked;
      }
    });
  }

  Future<void> _pickDueDate(int index) async {
    final _ActionDraft action = _actions[index];
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: action.dueDate ?? action.itemDate ?? _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select due date',
      locale: const Locale('en'),
    );
    if (picked != null && mounted) setState(() => action.dueDate = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: (start ? _startTime : _endTime) ?? TimeOfDay.now(),
      helpText: start ? 'Select start time' : 'Select end time',
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String? _completeValidation() {
    if (_title.text.trim().isEmpty) {
      return 'Enter a meeting title before completing the minutes.';
    }
    if (_date == null) {
      return 'Select a meeting date before completing the minutes.';
    }
    if (_location.text.trim().isEmpty) {
      return 'Enter a meeting location before completing the minutes.';
    }
    if (_minuteTaker.text.trim().isEmpty) {
      return 'Enter the minute taker before completing the minutes.';
    }
    final bool hasActionPlan = _actions.any(
      (_ActionDraft action) => action.subject.text.trim().isNotEmpty,
    );
    if (!hasActionPlan) {
      return 'Add at least one action plan before completing the minutes.';
    }
    for (int index = 0; index < _actions.length; index++) {
      final _ActionDraft action = _actions[index];
      if (action.subject.text.trim().isEmpty) continue;
      final String label = 'Action plan ${index + 1}';
      if (action.issue.text.trim().isEmpty) {
        return '$label requires an issue description.';
      }
      if (action.itemDate == null) {
        return '$label requires a date raised.';
      }
      if (action.assignedTo.text.trim().isEmpty) {
        return '$label requires a responsible person.';
      }
    }
    return null;
  }

  Future<void> _save(MeetingMinuteStatus status) async {
    if (_saving) return;
    final String? validation = status == MeetingMinuteStatus.completed
        ? _completeValidation()
        : null;
    if (validation != null) {
      _message(validation);
      return;
    }
    final String? actorId = ref.read(currentUserProvider)?.id;
    if (actorId == null) {
      _message('Session expired. Please sign in again.');
      return;
    }
    setState(() => _saving = true);
    try {
      final MeetingMinute saved = await _service.save(
        id: _minute?.id,
        actorId: actorId,
        title: _title.text,
        meetingDate: _date,
        startTime: _timeText(_startTime),
        endTime: _timeText(_endTime),
        location: _location.text,
        attendees: _attendees.text,
        apologies: _apologies.text,
        minuteTaker: _minuteTaker.text,
        distributionList: _distribution.text,
        newBusinessAgenda: _agenda.text,
        proposedBy: _proposedBy.text,
        note: _note.text,
        followUpOf: _minute?.followUpOf ?? widget.followUpOf,
        followUpSourceTitle:
            _minute?.followUpSource?.title ?? _followUpSource?.title ?? '',
        followUpSourceDate:
            _minute?.followUpSource?.meetingDate ??
            _followUpSource?.meetingDate,
        status: status,
        actions: <MeetingMinuteAction>[
          for (int index = 0; index < _actions.length; index++)
            _actions[index].toModel(position: index),
        ],
      );
      if (!mounted) return;
      _message(
        status == MeetingMinuteStatus.draft
            ? 'Draft saved.'
            : 'Minutes completed.',
      );
      context.go('/meeting-minutes/${saved.id}');
    } on Object catch (error) {
      if (mounted) _message('Unable to save minutes. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    final MeetingMinute? minute = _minute;
    if (minute == null) return;
    try {
      final List<MeetingMinuteExportPhoto> photos = await _service
          .downloadPhotos(minute);
      final List<int> bytes = MeetingMinuteExcelService().create(
        minute,
        photos: photos,
      );
      final String safeTitle = minute.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '')
          .toLowerCase();
      final String fileName =
          'mom-${safeTitle.isEmpty ? 'notulen' : safeTitle}.xlsx';
      if (kIsWeb) {
        downloadFile(
          bytes: Uint8List.fromList(bytes),
          fileName: fileName,
          mimeType: MeetingMinuteExcelService.mimeType,
        );
      } else {
        await Share.shareXFiles(<XFile>[
          XFile.fromData(
            Uint8List.fromList(bytes),
            mimeType: MeetingMinuteExcelService.mimeType,
            name: fileName,
          ),
        ]);
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to export minutes to Excel. $error');
    }
  }

  Future<void> _addPhoto(int index) async {
    final MeetingMinute? minute = _minute;
    final _ActionDraft action = _actions[index];
    if (minute == null || action.id == null) {
      _message('Save a draft before adding photos.');
      return;
    }
    if (action.photos.length >= 2) {
      _message('Each action plan supports up to two photos.');
      return;
    }
    final FilePickerResult? selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (selected == null || selected.files.isEmpty) return;
    final PlatformFile file = selected.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      _message('Unable to read this photo. Choose another file.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.uploadActionPhoto(
        meetingId: minute.id,
        actionId: action.id!,
        bytes: bytes,
        fileName: file.name,
      );
      final MeetingMinute updated = await _service.loadOne(minute.id);
      if (!mounted) return;
      _applyMinute(updated);
      _message('Photo compressed and added.');
    } on Object catch (error) {
      if (mounted) _message('Unable to add photo. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePhoto(MeetingMinuteActionPhoto photo) async {
    final MeetingMinute? minute = _minute;
    if (minute == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.deleteActionPhoto(photo);
      final MeetingMinute updated = await _service.loadOne(minute.id);
      if (!mounted) return;
      _applyMinute(updated);
      _message('Photo deleted.');
    } on Object catch (error) {
      if (mounted) _message('Unable to delete photo. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _applyMinute(MeetingMinute minute) {
    for (final _ActionDraft action in _actions) {
      action.dispose();
    }
    _actions
      ..clear()
      ..addAll(minute.actions.map(_ActionDraft.fromModel));
    if (_actions.isEmpty) {
      _actions.add(_ActionDraft(itemDate: minute.meetingDate));
    }
    _minute = minute;
  }

  Future<void> _delete() async {
    final MeetingMinute? minute = _minute;
    if (minute == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete minutes?'),
        content: const Text(
          'These minutes will be deleted. Existing follow-up minutes will be retained without the link to these minutes.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(minute.id);
      if (mounted) context.go('/meeting-minutes');
    } on Object catch (error) {
      if (mounted) _message('Unable to delete minutes. $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    final String pageTitle = _isNew ? 'Create Minutes' : 'Edit Minutes';
    final MeetingMinuteReference? linkedSource =
        _minute?.followUpSource ??
        (_followUpSource == null
            ? null
            : MeetingMinuteReference(
                id: _followUpSource!.id,
                title: _followUpSource!.title,
                meetingDate: _followUpSource!.meetingDate,
              ));
    return AppBackScope(
      fallbackRoute: '/meeting-minutes',
      child: Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/meeting-minutes'),
                title: Text(pageTitle),
                actions: <Widget>[
                  if (_minute != null)
                    IconButton(
                      tooltip: 'Export Excel',
                      onPressed: _export,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                ],
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  desktop ? 18 : 20,
                  20,
                  120 + MediaQuery.paddingOf(context).bottom,
                ),
                children: <Widget>[
                  if (desktop) ...<Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.edit_note_rounded,
                          color: AppColors.green,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Text(pageTitle, style: AppTextStyles.pageTitle),
                        const Spacer(),
                        if (_minute != null)
                          OutlinedButton.icon(
                            onPressed: _export,
                            icon: const Icon(Icons.ios_share_rounded),
                            label: const Text('Export Excel'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_minute != null) ...<Widget>[
                    Row(
                      children: <Widget>[
                        _MeetingBadge(status: _minute!.status),
                        const SizedBox(width: 8),
                        Text(
                          'Last saved ${_momDateTime(_minute!.updatedAt.toLocal())}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (linkedSource != null) ...<Widget>[
                    Card(
                      color: AppColors.mint,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Follow-up of: ${linkedSource.title.trim().isEmpty ? 'previous minutes' : linkedSource.title}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _SectionCard(
                    title: 'Meeting details',
                    icon: Icons.calendar_month_rounded,
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _title,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Meeting or inspection title',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DateTimeFields(
                          date: _date,
                          startTime: _startTime,
                          endTime: _endTime,
                          onDate: () => _pickDate(main: true),
                          onStart: () => _pickTime(start: true),
                          onEnd: () => _pickTime(start: false),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _location,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Attendees and distribution',
                    icon: Icons.groups_rounded,
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _attendees,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Attendees',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apologies,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Apologies',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _minuteTaker,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Minute taker',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _distribution,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Distribution',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'New business',
                    icon: Icons.topic_outlined,
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _agenda,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'New business',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _proposedBy,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Proposed by',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Issues and action plans',
                    icon: Icons.checklist_rounded,
                    child: Column(
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < _actions.length;
                          index++
                        ) ...<Widget>[
                          _ActionEditor(
                            index: index,
                            action: _actions[index],
                            onItemDate: () =>
                                _pickDate(main: false, actionIndex: index),
                            onDueDate: () => _pickDueDate(index),
                            onAddPhoto: _saving ? null : () => _addPhoto(index),
                            onDeletePhoto: _saving ? null : _deletePhoto,
                            photoUrl: _service.photoUrl,
                            onRemove: _actions.length == 1
                                ? null
                                : () => setState(() {
                                    final _ActionDraft removed = _actions
                                        .removeAt(index);
                                    removed.dispose();
                                  }),
                          ),
                          if (index < _actions.length - 1)
                            const Divider(height: 28),
                        ],
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: () => setState(
                            () => _actions.add(
                              _ActionDraft(
                                itemDate: _date,
                                issueDescription: _actions.isEmpty
                                    ? ''
                                    : _actions.last.issue.text,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add action plan'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _actions.add(_ActionDraft(itemDate: _date)),
                          ),
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('Add new issue'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Notes',
                    icon: Icons.sticky_note_2_outlined,
                    child: TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Additional notes',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_minute?.status == MeetingMinuteStatus.completed)
                    Column(
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(MeetingMinuteStatus.completed),
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: const Text('Save changes'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => context.go(
                                  '/meeting-minutes/${_minute!.id}/follow-up',
                                ),
                          icon: const Icon(Icons.next_plan_outlined),
                          label: const Text('Create follow-up'),
                        ),
                      ],
                    )
                  else ...<Widget>[
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _save(MeetingMinuteStatus.draft),
                      icon: const Icon(Icons.save_as_outlined),
                      label: const Text('Save as draft'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _save(MeetingMinuteStatus.completed),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.task_alt_rounded),
                      label: const Text('Complete minutes'),
                    ),
                  ],
                  if (_minute != null) ...<Widget>[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete minutes'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  String? _timeText(TimeOfDay? time) => time == null
      ? null
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.green),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _DateTimeFields extends StatelessWidget {
  const _DateTimeFields({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.onDate,
    required this.onStart,
    required this.onEnd,
  });

  final DateTime? date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final VoidCallback onDate;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: <Widget>[
      _PickerField(
        label: 'Meeting date',
        value: date == null ? 'Select date' : _momDate(date!),
        icon: Icons.calendar_today_outlined,
        onTap: onDate,
      ),
      _PickerField(
        label: 'Start time',
        value: startTime?.format(context) ?? 'Select time',
        icon: Icons.schedule_rounded,
        onTap: onStart,
      ),
      _PickerField(
        label: 'End time',
        value: endTime?.format(context) ?? 'Select time',
        icon: Icons.schedule_rounded,
        onTap: onEnd,
      ),
    ],
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width >= 620 ? 220 : double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.green),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 3),
                Text(value, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionEditor extends StatelessWidget {
  const _ActionEditor({
    required this.index,
    required this.action,
    required this.onItemDate,
    required this.onDueDate,
    required this.onAddPhoto,
    required this.onDeletePhoto,
    required this.photoUrl,
    this.onRemove,
  });

  final int index;
  final _ActionDraft action;
  final VoidCallback onItemDate;
  final VoidCallback onDueDate;
  final VoidCallback? onAddPhoto;
  final ValueChanged<MeetingMinuteActionPhoto>? onDeletePhoto;
  final Future<String> Function(MeetingMinuteActionPhoto photo) photoUrl;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Text(
            'Action plan ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (onRemove != null)
            IconButton(
              tooltip: 'Delete action plan',
              onPressed: onRemove,
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.danger,
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      TextField(
        controller: action.issue,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Issues description'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: action.subject,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Action plan'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: action.assignedTo,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Resp. person'),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _PickerField(
            label: 'Date raised',
            value: action.itemDate == null
                ? 'Select date'
                : _momShortDate(action.itemDate!),
            icon: Icons.event_note_outlined,
            onTap: onItemDate,
          ),
          _PickerField(
            label: 'Due date (optional)',
            value: action.dueDate == null
                ? 'Not set'
                : _momShortDate(action.dueDate!),
            icon: Icons.event_available_outlined,
            onTap: onDueDate,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          const Icon(Icons.photo_camera_back_outlined, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Action plan photos (${action.photos.length}/2)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (action.photos.length < 2)
            TextButton.icon(
              onPressed: onAddPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photo'),
            ),
        ],
      ),
      if (action.photos.isEmpty)
        const Text(
          'Save a draft first. JPG/JPEG/PNG photos are automatically compressed before upload.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final MeetingMinuteActionPhoto photo in action.photos.take(
                2,
              ))
                _ActionPhotoTile(
                  photo: photo,
                  photoUrl: photoUrl,
                  onDelete: onDeletePhoto == null
                      ? null
                      : () => onDeletePhoto!(photo),
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: action.progress,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Progress / remark'),
      ),
    ],
  );
}

class _ActionPhotoTile extends StatelessWidget {
  const _ActionPhotoTile({
    required this.photo,
    required this.photoUrl,
    this.onDelete,
  });

  final MeetingMinuteActionPhoto photo;
  final Future<String> Function(MeetingMinuteActionPhoto photo) photoUrl;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: FutureBuilder<String>(
      future: photoUrl(photo),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: snapshot.hasData
                  ? Image.network(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoPlaceholder(),
                    )
                  : _photoPlaceholder(loading: true),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  photo.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete photo',
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _photoPlaceholder({bool loading = false}) => ColoredBox(
    color: AppColors.mint,
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.broken_image_outlined, color: AppColors.muted),
    ),
  );
}

class _ActionDraft {
  _ActionDraft({
    this.id,
    this.itemDate,
    this.dueDate,
    String issueDescription = '',
    String subject = '',
    String assignedTo = '',
    String progressRemark = '',
    this.photos = const <MeetingMinuteActionPhoto>[],
  }) : issue = TextEditingController(text: issueDescription),
       subject = TextEditingController(text: subject),
       assignedTo = TextEditingController(text: assignedTo),
       progress = TextEditingController(text: progressRemark);

  factory _ActionDraft.fromModel(MeetingMinuteAction action) => _ActionDraft(
    id: action.id,
    itemDate: action.itemDate,
    dueDate: action.dueDate,
    issueDescription: action.issueDescription,
    subject: action.subjectDiscussion,
    assignedTo: action.assignedTo,
    progressRemark: action.progressRemark,
    photos: action.photos,
  );

  final String? id;
  DateTime? itemDate;
  DateTime? dueDate;
  final List<MeetingMinuteActionPhoto> photos;
  final TextEditingController issue;
  final TextEditingController subject;
  final TextEditingController assignedTo;
  final TextEditingController progress;

  MeetingMinuteAction toModel({required int position}) => MeetingMinuteAction(
    id: id,
    itemDate: itemDate,
    dueDate: dueDate,
    issueDescription: issue.text,
    subjectDiscussion: subject.text,
    assignedTo: assignedTo.text,
    position: position,
    progressRemark: progress.text,
    photos: photos,
  );

  void dispose() {
    issue.dispose();
    subject.dispose();
    assignedTo.dispose();
    progress.dispose();
  }
}

String _momDate(DateTime value) {
  const List<String> months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _momShortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${(value.year % 100).toString().padLeft(2, '0')}';

String _momDateTime(DateTime value) =>
    '${_momDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _pmShortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
