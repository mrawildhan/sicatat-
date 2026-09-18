import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';
import '../../daily_checks/daily_check_repository.dart';
import '../../daily_checks/presentation/daily_check_widgets.dart';

class SheetMonitoringScreen extends ConsumerStatefulWidget {
  const SheetMonitoringScreen({super.key});

  @override
  ConsumerState<SheetMonitoringScreen> createState() =>
      _SheetMonitoringScreenState();
}

class _SheetMonitoringScreenState extends ConsumerState<SheetMonitoringScreen> {
  List<SheetModel> _sheets = const <SheetModel>[];
  List<DailyCheckSheet> _dailySheets = const <DailyCheckSheet>[];
  List<TemperatureAlert> _alerts = const <TemperatureAlert>[];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final teamId = user.role.isTeamScopedTemperature ? user.teamId : null;
      final sheets = await ref
          .read(sicatatRepositoryProvider)
          .listSharedSheets(teamId: teamId);
      final dailyRepository = DailyCheckRepository();
      await dailyRepository.loadThresholds();
      final daily = await dailyRepository.listSince(
        DateTime.now().subtract(const Duration(days: 14)),
      );
      List<TemperatureAlert> alerts = const <TemperatureAlert>[];
      try {
        alerts = await dailyRepository.recentAlerts(days: 7);
      } on Object {
        // Alerts are a bonus; the sheet lists still show.
      }
      if (mounted) {
        setState(() {
          _sheets = sheets;
          _dailySheets = daily;
          _alerts = alerts;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Lembar dari server tidak dapat dimuat. Periksa koneksi lalu muat ulang.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final title = user?.role.isTeamScopedTemperature == true
        ? 'Lembar regu'
        : 'Pemantauan lembar';
    final errorMessage = _errorMessage;
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    final Widget content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMessage != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                if (_alerts.isNotEmpty) ...<Widget>[
                  _heading(
                    'Suhu kritis 7 hari terakhir',
                    'Juga dikirim lewat email ke penerima yang diatur admin.',
                  ),
                  ..._alerts.map(_alert),
                  const SizedBox(height: 18),
                ],
                _heading(
                  'Hydraulic Feeder & Coal Valve',
                  '14 hari terakhir. Lembar terkirim menunggu persetujuan '
                      'foreman/supervisor.',
                ),
                if (_dailySheets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Belum ada lembar.'),
                  )
                else
                  ..._dailySheets.map(_dailySheet),
                const SizedBox(height: 18),
                _heading('Daily Temperature Feeder Sizer', null),
                if (_sheets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Belum ada lembar yang tersinkron ke server.'),
                  )
                else
                  for (final sheet in _sheets) ...<Widget>[
                    _sheet(sheet),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
    return AppBackScope(
      fallbackRoute: '/sheets',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/sheets'),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: <Widget>[
                  IconButton(
                    onPressed: _isLoading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
        body: useDesktopHeader
            ? Column(
                children: <Widget>[
                  _desktopHeader(context, title),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  Widget _desktopHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
    child: Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Kembali ke Suhu',
          onPressed: () => context.go('/sheets'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _isLoading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );

  Widget _sheet(SheetModel sheet) {
    final state = sheet.status == SheetStatus.draft
        ? SyncState.draft
        : SyncState.synced;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(_destinationFor(sheet)),
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
              const SizedBox(height: 12),
              Text(
                '${sheet.teamName ?? 'Regu'} • ${displayShiftName(sheet.shiftName ?? 'Shift')}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Text(
                _statusLabel(sheet.status),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String? subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: AppTextStyles.sectionTitle),
        if (subtitle != null) Text(subtitle, style: AppTextStyles.supporting),
      ],
    ),
  );

  Widget _alert(TemperatureAlert alert) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: const Color(0xFFFFECEB),
    child: ListTile(
      leading: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
      title: Text(
        '${formatReading(alert.value)} °C · ${alert.pointLabel}',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      subtitle: Text(
        '${alert.formLabel}\n${alert.teamName ?? 'Regu'} · '
        '${alert.shiftLabel ?? '-'} · '
        '${DateFormat('dd MMM yyyy, HH:mm').format(alert.occurredAt)}',
      ),
      isThreeLine: true,
    ),
  );

  Widget _dailySheet(DailyCheckSheet sheet) {
    final waiting = !sheet.isDraft && !sheet.isApproved;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.go(
          '/daily-checks/${sheet.type.storageValue}/sheet/${sheet.id}',
        ),
        leading: Icon(
          sheet.form.icon,
          color: sheet.worstLevel.index > 0
              ? temperatureColor(sheet.worstLevel)
              : AppColors.green,
        ),
        title: Text(
          '${DateFormat('dd/MM/yyyy').format(sheet.date)} · ${sheet.form.title}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${sheet.teamName ?? 'Regu'} · ${sheet.shiftLabel} · '
          '${sheet.completeSlots}/${sheet.slots.length} lengkap',
        ),
        trailing: sheet.isDraft
            ? const DailyCheckStatusChip(DailyCheckStatus.draft)
            : waiting
            ? const Chip(label: Text('Perlu disetujui'))
            : const Icon(Icons.verified_rounded, color: AppColors.green),
      ),
    );
  }

  String _destinationFor(SheetModel sheet) {
    final AppUser? user = ref.read(currentUserProvider);
    final bool canContinue =
        (sheet.status == SheetStatus.draft ||
            sheet.status == SheetStatus.returned) &&
        user?.role.canCreateTemperatureSheet == true;
    return canContinue
        ? '/temperature?sheetId=${sheet.id}'
        : '/summary?sheetId=${sheet.id}';
  }

  String _statusLabel(SheetStatus status) => switch (status) {
    SheetStatus.draft => 'Draf kru',
    SheetStatus.submitted => 'Dikirim',
    SheetStatus.submittedIncomplete => 'Dikirim tidak lengkap',
    SheetStatus.verified => 'Terverifikasi',
    SheetStatus.returned => 'Dikembalikan',
  };
}
