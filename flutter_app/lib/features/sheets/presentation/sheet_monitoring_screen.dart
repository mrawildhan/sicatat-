import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      final teamId = user.role == UserRole.foreman ? user.teamId : null;
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
    final title = user?.role == UserRole.foreman
        ? 'Team sheets'
        : 'Sheet monitoring';
    final errorMessage = _errorMessage;
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
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _isLoading
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
                child: Text('No sheets have been synced to the server yet.'),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _sheets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => _sheet(_sheets[index]),
                ),
              ),
      ),
    );
  }

  Widget _sheet(SheetModel sheet) {
    final state = sheet.status == SheetStatus.draft
        ? SyncState.draft
        : SyncState.synced;
    return Card(
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
              '${sheet.teamName ?? 'Team'} • ${sheet.shiftName ?? 'Shift'}',
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
    );
  }

  String _statusLabel(SheetStatus status) => switch (status) {
    SheetStatus.draft => 'Crew draft',
    SheetStatus.submitted => 'Submitted - waiting for verification',
    SheetStatus.submittedIncomplete => 'Submitted as incomplete',
    SheetStatus.verified => 'Verified',
    SheetStatus.returned => 'Returned',
  };
}
