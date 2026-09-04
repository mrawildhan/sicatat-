import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class SheetMonitoringScreen extends ConsumerStatefulWidget {
  const SheetMonitoringScreen({super.key});

  @override
  ConsumerState<SheetMonitoringScreen> createState() =>
      _SheetMonitoringScreenState();
}

class _SheetMonitoringScreenState extends ConsumerState<SheetMonitoringScreen> {
  List<SheetModel> _sheets = const <SheetModel>[];
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
      if (mounted) {
        setState(() => _sheets = sheets);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Server sheets could not be loaded. Check the connection and refresh.',
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
        ? 'Lembar tim'
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
        : _sheets.isEmpty
        ? const Center(
            child: Text('Belum ada lembar yang tersinkron ke server.'),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _sheets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _sheet(_sheets[index]),
            ),
          );
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
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
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
                '${sheet.teamName ?? 'Tim'} • ${sheet.shiftName ?? 'Shift'}',
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
    SheetStatus.draft => 'Draf crew',
    SheetStatus.submitted => 'Dikirim',
    SheetStatus.submittedIncomplete => 'Dikirim tidak lengkap',
    SheetStatus.verified => 'Terverifikasi',
    SheetStatus.returned => 'Dikembalikan',
  };
}
