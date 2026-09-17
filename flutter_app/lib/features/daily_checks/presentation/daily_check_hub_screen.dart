import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/summary_filter_card.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

enum _HubFilter { all, draft, submitted, high }

class DailyCheckHubScreen extends ConsumerStatefulWidget {
  const DailyCheckHubScreen({required this.type, super.key});

  final DailyCheckFormType type;

  @override
  ConsumerState<DailyCheckHubScreen> createState() =>
      _DailyCheckHubScreenState();
}

class _DailyCheckHubScreenState extends ConsumerState<DailyCheckHubScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  List<DailyCheckSheet> _sheets = const <DailyCheckSheet>[];
  bool _loading = true;
  String? _error;
  _HubFilter _filter = _HubFilter.all;

  DailyCheckForm get _form => widget.type.form;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DailyCheckHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _filter = _HubFilter.all;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheets = await _repository.list(widget.type);
      if (mounted) setState(() => _sheets = sheets);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Sheets could not be loaded: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isHigh(DailyCheckSheet sheet) {
    final highest = sheet.highestTemperature;
    return highest != null &&
        temperatureLevel(highest) != DailyCheckTemperatureLevel.normal;
  }

  List<DailyCheckSheet> get _visible => _sheets
      .where(
        (sheet) => switch (_filter) {
          _HubFilter.all => true,
          _HubFilter.draft => sheet.isDraft,
          _HubFilter.submitted => !sheet.isDraft,
          _HubFilter.high => _isHigh(sheet),
        },
      )
      .toList(growable: false);

  void _toggle(_HubFilter filter) =>
      setState(() => _filter = _filter == filter ? _HubFilter.all : filter);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canCreate = user?.role.canCreateTemperatureSheet == true;
    return AppBackScope(
      fallbackRoute: '/temperature-forms',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/temperature-forms'),
          title: Text(
            _form.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                onPressed: () =>
                    context.go('/daily-checks/${widget.type.storageValue}/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New sheet'),
              )
            : null,
        body: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
      children: <Widget>[
        Text(_form.description, style: AppTextStyles.supporting),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            SummaryFilterCard(
              label: 'Draft',
              count: _sheets.where((sheet) => sheet.isDraft).length,
              color: AppColors.orange,
              icon: Icons.edit_note_rounded,
              selected: _filter == _HubFilter.draft,
              onTap: () => _toggle(_HubFilter.draft),
            ),
            const SummaryFilterGap(),
            SummaryFilterCard(
              label: 'Submitted',
              count: _sheets.where((sheet) => !sheet.isDraft).length,
              color: AppColors.green,
              icon: Icons.cloud_done_rounded,
              selected: _filter == _HubFilter.submitted,
              onTap: () => _toggle(_HubFilter.submitted),
            ),
            const SummaryFilterGap(),
            SummaryFilterCard(
              label: 'High temp',
              count: _sheets.where(_isHigh).length,
              color: AppColors.danger,
              icon: Icons.thermostat_rounded,
              selected: _filter == _HubFilter.high,
              onTap: () => _toggle(_HubFilter.high),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(switch (_filter) {
                _HubFilter.all => 'All sheets',
                _HubFilter.draft => 'Draft sheets',
                _HubFilter.submitted => 'Submitted sheets',
                _HubFilter.high => 'Sheets with high temperature (≥ 60 °C)',
              }, style: AppTextStyles.sectionTitle),
            ),
            if (_filter != _HubFilter.all)
              TextButton(
                onPressed: () => setState(() => _filter = _HubFilter.all),
                child: const Text('Show all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error case final error?)
          Text(error, style: const TextStyle(color: AppColors.danger))
        else if (visible.isEmpty)
          _empty()
        else
          ...visible.map(_sheetCard),
      ],
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: <Widget>[
        Icon(_form.icon, size: 52, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          _filter == _HubFilter.all ? 'No sheets yet' : 'No matching sheets',
          style: AppTextStyles.cardTitle.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          _filter == _HubFilter.all
              ? 'Tap New sheet to start recording.'
              : 'Tap the card again to show all sheets.',
          textAlign: TextAlign.center,
          style: AppTextStyles.supporting,
        ),
      ],
    ),
  );

  Widget _sheetCard(DailyCheckSheet sheet) {
    final slots = sheet.slots;
    final highest = sheet.highestTemperature;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(
            '/daily-checks/${widget.type.storageValue}/sheet/${sheet.id}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    Expanded(
                      child: Text(
                        '${DateFormat('dd/MM/yyyy').format(sheet.date)} · ${sheet.shiftLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DailyCheckStatusChip(sheet.status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${sheet.teamName ?? 'Team'} · ${sheet.completeSlots}/${slots.length} ${widget.type == DailyCheckFormType.hydraulicFeeder ? 'checks' : 'readings'} complete',
                  style: AppTextStyles.supporting,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SlotProgressBar(
                        form: sheet.form,
                        slots: slots,
                        readings: sheet.readings,
                      ),
                    ),
                    if (highest != null) ...<Widget>[
                      const SizedBox(width: 12),
                      TemperatureBadge(highest, prefix: 'Max '),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
