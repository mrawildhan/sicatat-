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
              createdBy: user.role == UserRole.admin ? null : user.id,
            );
        await LocalDatabase.instance.cacheRemoteSheets(shared);
      }
      final localSheets = await LocalDatabase.instance.listSheets();
      final sheets = user?.role == UserRole.admin
          ? localSheets
          : localSheets
                .where((sheet) => sheet.createdBy == user?.id)
                .toList(growable: false);
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
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'My sheets',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            IconButton(
              onPressed: _isLoading ? null : _loadSheets,
              icon: const Icon(Icons.refresh_rounded),
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
    if (_sheets.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const <Widget>[
          SizedBox(height: 80),
          Icon(Icons.description_outlined, size: 58, color: AppColors.muted),
          SizedBox(height: 16),
          Center(
            child: Text(
              'No inspection sheets yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Create a new sheet to start recording temperatures.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
      itemCount: _sheets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _sheet(context, _sheets[index]),
    );
  }

  Widget _sheet(BuildContext context, SheetModel sheet) {
    final state = switch (sheet.syncStatus) {
      SheetSyncStatus.pending => SyncState.pending,
      SheetSyncStatus.synced => SyncState.synced,
      SheetSyncStatus.conflict => SyncState.conflict,
    };
    final detail = switch (sheet.status) {
      SheetStatus.draft => 'Draft - continue entry',
      SheetStatus.submitted => 'Submitted - may be revised before verification',
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
                _shiftNames[sheet.shiftId] ?? 'Saved shift',
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
