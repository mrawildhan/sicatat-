import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/local/local_database.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/field_entry_models.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class SheetSummaryScreen extends ConsumerStatefulWidget {
  const SheetSummaryScreen({required this.sheetId, super.key});
  final String? sheetId;

  @override
  ConsumerState<SheetSummaryScreen> createState() => _SheetSummaryScreenState();
}

class _SheetSummaryScreenState extends ConsumerState<SheetSummaryScreen> {
  final TextEditingController _forceReasonController = TextEditingController();
  SheetModel? _sheet;
  List<_SummaryEntry> _entries = const <_SummaryEntry>[];
  List<SheetAuditEvent> _audit = const <SheetAuditEvent>[];
  int _contributors = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<_SummaryEntry> get _incomplete =>
      _entries.where((entry) => !entry.isComplete).toList(growable: false);

  List<_SummaryGroup> get _groups {
    final Map<String, _SummaryGroup> groups = <String, _SummaryGroup>{};
    for (final entry in _entries) {
      final key = '${entry.section.storageValue}-${entry.roundNumber}';
      groups
          .putIfAbsent(
            key,
            () => _SummaryGroup(
              section: entry.section,
              roundNumber: entry.roundNumber,
            ),
          )
          .entries
          .add(entry);
    }
    return groups.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _forceReasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sheetId = widget.sheetId;
    if (sheetId == null || sheetId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Inspection sheet not found.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        LocalDatabase.instance.getSheet(sheetId),
        LocalDatabase.instance.getContributorCount(sheetId),
        ref.read(sicatatRepositoryProvider).getInspectionFormConfig(),
        LocalDatabase.instance.getSheetAuditTrail(sheetId),
      ]);
      final sheet = results[0] as SheetModel?;
      if (sheet == null) {
        throw const LocalRecordNotFoundException('Inspection sheet not found.');
      }
      final entries = await _buildEntries(
        sheetId,
        results[2] as InspectionFormConfig,
      );
      var audit = results[3] as List<SheetAuditEvent>;
      try {
        final Object remote = await Supabase.instance.client
            .from('audit_log')
            .select('id,action,changed_at,changed_by,new_value')
            .eq('entity_type', 'sheet')
            .eq('entity_id', sheetId)
            .order('changed_at', ascending: false);
        if (remote is List) {
          audit = remote
              .map(
                (Object? row) =>
                    SheetAuditEvent.fromRemoteRow(row as Map<String, dynamic>),
              )
              .toList(growable: false);
        }
      } on Object {
        // The locally queued audit remains useful while an older deployment
        // is still receiving its audit_log read policy.
      }
      if (!mounted) return;
      setState(() {
        _sheet = sheet;
        _contributors = results[1] as int;
        _entries = entries;
        _audit = audit;
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Sheet summary could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_SummaryEntry>> _buildEntries(
    String sheetId,
    InspectionFormConfig config,
  ) async {
    final entries = <_SummaryEntry>[];
    for (final step in config.steps) {
      final section = step.section;
      final roundNumber = step.roundNumber;
      final round = await LocalDatabase.instance.getRound(
        sheetId: sheetId,
        section: section,
        roundNumber: roundNumber,
      );
      final equipmentPoints = <MeasurementPoint>[
        for (final equipment in config.equipmentFor(section.storageValue))
          ...config.pointsForEquipment(equipment.id),
      ].where(config.isRequired).toList(growable: false);
      if (equipmentPoints.isNotEmpty) {
        final values = round == null
            ? const <String, FieldReadingValue>{}
            : await LocalDatabase.instance.getReadingValues(
                roundId: round.id,
                unitStatusId: null,
              );
        final missing = equipmentPoints
            .where((point) => !(values[point.id]?.hasValue ?? false))
            .map((point) => point.label)
            .toList(growable: false);
        entries.add(
          _SummaryEntry(
            section: section,
            roundNumber: roundNumber,
            entry: 'equipment',
            label: '${_sectionLabel(section)} - Round $roundNumber - Equipment',
            missing: missing,
          ),
        );
      }
      for (final expected in expectedSides.where(
        (item) => item.section == section && item.roundNumber == roundNumber,
      )) {
        final unit = round == null
            ? null
            : await LocalDatabase.instance.getUnitStatus(
                roundId: round.id,
                unitCode: expected.unitCode,
              );
        final missing = <String>[];
        if (unit == null) {
          missing.add('unit status');
        } else if (unit.status == UnitOperationalStatus.operating) {
          final values = await LocalDatabase.instance.getReadingValues(
            roundId: round!.id,
            unitStatusId: unit.id,
          );
          missing.addAll(
            config.gearboxPoints
                .where(
                  (point) =>
                      config.isRequired(point) &&
                      !(values[point.id]?.hasValue ?? false),
                )
                .map((point) => point.label),
          );
        } else if (unit.reason?.trim().isEmpty ?? true) {
          missing.add('reason');
        }
        entries.add(
          _SummaryEntry(
            section: section,
            roundNumber: roundNumber,
            side: expected.unitCode,
            entry: 'gearbox',
            label: expected.label,
            missing: missing,
          ),
        );
      }
    }
    return entries;
  }

  Future<void> _submit() async {
    final sheetId = widget.sheetId;
    final user = ref.read(currentUserProvider);
    if (sheetId == null ||
        user == null ||
        _incomplete.isNotEmpty ||
        _contributors == 0) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await LocalDatabase.instance.submitSheet(
        sheetId: sheetId,
        submittedBy: user.id,
      );
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (mounted) context.go('/sheets');
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'Sheet could not be submitted. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _forceSubmit() async {
    final sheetId = widget.sheetId;
    final user = ref.read(currentUserProvider);
    final permitted =
        user?.role == UserRole.foreman ||
        user?.role == UserRole.supervisor ||
        user?.role == UserRole.admin;
    if (sheetId == null ||
        !permitted ||
        _incomplete.isEmpty ||
        _contributors == 0 ||
        _forceReasonController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await LocalDatabase.instance.forceSubmitSheet(
        sheetId: sheetId,
        reason: _forceReasonController.text.trim(),
        submittedBy: user!.id,
      );
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (mounted) context.go('/sheets');
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'The incomplete sheet could not be submitted.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reopenForCorrection() async {
    final sheet = _sheet;
    final user = ref.read(currentUserProvider);
    if (sheet == null || user?.id != sheet.createdBy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revise submitted sheet?'),
        content: const Text(
          'This sheet will return to draft status so you can correct it and submit it again. It cannot be reopened after verification.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reopen draft'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await LocalDatabase.instance.reopenSheetForCorrection(
        sheetId: sheet.id,
        reopenedBy: user!.id,
      );
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (mounted) context.go('/temperature?sheetId=${sheet.id}');
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'The sheet could not be reopened: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _verify() async {
    final sheet = _sheet;
    final user = ref.read(currentUserProvider);
    if (sheet == null || user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify sheet?'),
        content: const Text(
          'Verification locks this sheet for crew editing. Return it instead if correction is required.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verify & lock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _applyReviewAction(
      () => LocalDatabase.instance.verifySheet(
        sheetId: sheet.id,
        verifiedBy: user.id,
      ),
      successRoute: '/sheets',
    );
  }

  Future<void> _returnForCorrection() async {
    final sheet = _sheet;
    final user = ref.read(currentUserProvider);
    if (sheet == null || user == null) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Return for correction'),
          content: TextField(
            controller: reason,
            autofocus: true,
            maxLines: 3,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(labelText: 'Return reason *'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Return sheet'),
            ),
          ],
        ),
      ),
    );
    final cleanReason = reason.text.trim();
    reason.dispose();
    if (confirmed != true) return;
    await _applyReviewAction(
      () => LocalDatabase.instance.returnSheetForCorrection(
        sheetId: sheet.id,
        returnedBy: user.id,
        reason: cleanReason,
      ),
      successRoute: '/sheets',
    );
  }

  Future<void> _applyReviewAction(
    Future<void> Function() action, {
    required String successRoute,
  }) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await action();
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (mounted) context.go(successRoute);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Review action failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteSheet() async {
    final sheet = _sheet;
    final sheetId = widget.sheetId;
    if (sheet == null || sheetId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete sheet?'),
        content: const Text(
          'This removes the sheet and all of its field entries.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      if (sheet.syncStatus == SheetSyncStatus.synced) {
        await Supabase.instance.client.from('sheet').delete().eq('id', sheetId);
      }
      await LocalDatabase.instance.deleteSheetLocal(sheetId);
      if (mounted) context.go('/sheets');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Unable to delete sheet: $error');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openEntry(_SummaryEntry entry) {
    final sheetId = widget.sheetId;
    if (sheetId == null) {
      return;
    }
    final side = entry.side == null ? '' : '&side=${entry.side}';
    context.go(
      '/temperature?sheetId=$sheetId&section=${entry.section.storageValue}&round=${entry.roundNumber}&entry=${entry.entry}$side',
    );
  }

  Future<void> _showGroupDetails(_SummaryGroup group) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .55,
            minChildSize: .35,
            maxChildSize: .9,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: <Widget>[
                Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...group.entries.map(_entryTile),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_sheet == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(_errorMessage ?? 'Inspection sheet not found.'),
        ),
      );
    }
    final isSubmitted =
        _sheet!.status == SheetStatus.submitted ||
        _sheet!.status == SheetStatus.submittedIncomplete ||
        _sheet!.status == SheetStatus.verified;
    final incomplete = _incomplete;
    final canSubmit = !isSubmitted && incomplete.isEmpty && _contributors > 0;
    final user = ref.watch(currentUserProvider);
    final canOverride =
        !isSubmitted &&
        incomplete.isNotEmpty &&
        _contributors > 0 &&
        (user?.role == UserRole.foreman ||
            user?.role == UserRole.supervisor ||
            user?.role == UserRole.admin);
    final canRevise =
        (_sheet!.status == SheetStatus.submitted ||
            _sheet!.status == SheetStatus.submittedIncomplete) &&
        user?.id == _sheet!.createdBy;
    final canReview =
        (_sheet!.status == SheetStatus.submitted ||
            _sheet!.status == SheetStatus.submittedIncomplete) &&
        (user?.role == UserRole.foreman ||
            user?.role == UserRole.supervisor ||
            user?.role == UserRole.admin);
    final canDelete =
        _sheet!.status != SheetStatus.verified &&
        (user?.role == UserRole.admin ||
            user?.role == UserRole.supervisor ||
            user?.role == UserRole.foreman ||
            (user?.role == UserRole.crew && _sheet?.createdBy == user?.id));
    return AppBackScope(
      fallbackRoute: '/sheets',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/sheets'),
          title: const Text(
            'Sheet summary',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
            children: <Widget>[
              _summaryBanner(isSubmitted, canSubmit, incomplete),
              const SizedBox(height: 12),
              _summaryGrid(),
              const SizedBox(height: 10),
              _quickActions(),
              if (canRevise ||
                  canReview ||
                  canOverride ||
                  _audit.isNotEmpty ||
                  canDelete)
                _moreOptions(
                  user: user,
                  canRevise: canRevise,
                  canReview: canReview,
                  canOverride: canOverride,
                  canDelete: canDelete,
                ),
              if (_errorMessage case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: isSubmitted
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x16000000),
                        blurRadius: 14,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: canSubmit && !_isSubmitting ? _submit : null,
                    child: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit sheet',
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _summaryBanner(
    bool submitted,
    bool canSubmit,
    List<_SummaryEntry> incomplete,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: submitted || canSubmit ? AppColors.mint : const Color(0xFFFFF4E6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: <Widget>[
        Icon(
          submitted || canSubmit
              ? Icons.task_alt_rounded
              : Icons.error_outline_rounded,
          color: submitted || canSubmit ? AppColors.green : AppColors.danger,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            submitted
                ? 'Submitted for verification'
                : canSubmit
                ? 'All required readings are complete'
                : '${incomplete.length} item(s) need attention. Tap a red card to continue.',
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
          ),
        ),
      ],
    ),
  );

  Widget _summaryGrid() => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.75,
    children: _groups.map(_groupTile).toList(growable: false),
  );

  Widget _groupTile(_SummaryGroup group) {
    final incomplete = group.incomplete;
    final complete = incomplete.isEmpty;
    return Card(
      color: complete ? Colors.white : const Color(0xFFFFF0EF),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isSubmitting
            ? null
            : () => complete
                  ? _showGroupDetails(group)
                  : _openEntry(incomplete.first),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                group.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Icon(
                    complete ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 17,
                    color: complete ? AppColors.green : AppColors.danger,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      complete
                          ? '${group.entries.length}/${group.entries.length} ready'
                          : '${incomplete.length} missing · Continue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: complete ? AppColors.green : AppColors.danger,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions() => Card(
    child: Row(
      children: <Widget>[
        Expanded(
          child: ListTile(
            dense: true,
            leading: const Icon(
              Icons.people_alt_outlined,
              color: AppColors.green,
            ),
            title: const Text(
              'Filled by',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('$_contributors person(s)'),
          ),
        ),
        IconButton(
          tooltip: 'Export PDF / CSV',
          onPressed: _isSubmitting
              ? null
              : () => context.go('/sheet-export?sheetId=${widget.sheetId}'),
          icon: const Icon(Icons.ios_share_rounded, color: AppColors.green),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );

  Widget _moreOptions({
    required AppUser? user,
    required bool canRevise,
    required bool canReview,
    required bool canOverride,
    required bool canDelete,
  }) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
    title: const Text(
      'More options & history',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    children: <Widget>[
      if (canRevise)
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _reopenForCorrection,
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Revise submitted sheet'),
        ),
      if (canReview)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _returnForCorrection,
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Return'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _verify,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Verify'),
                ),
              ),
            ],
          ),
        ),
      if (canOverride && user != null) _overrideCard(user),
      if (_audit.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Audit trail',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        ..._audit.map(
          (event) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.history_rounded),
            title: Text(event.action.replaceAll('_', ' ')),
            subtitle: Text(
              '${event.changedAt.toLocal()}${event.note == null ? '' : '\n${event.note}'}',
            ),
          ),
        ),
      ],
      if (canDelete)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _isSubmitting ? null : _deleteSheet,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete sheet'),
          ),
        ),
    ],
  );

  Widget _entryTile(_SummaryEntry entry) => Card(
    child: ListTile(
      leading: Icon(
        entry.isComplete
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded,
        color: entry.isComplete ? AppColors.green : AppColors.danger,
      ),
      title: Text(
        entry.label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        entry.isComplete ? 'Completed' : 'Missing: ${entry.missing.join(', ')}',
      ),
      trailing: entry.isComplete
          ? const Text(
              'Ready',
              style: TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
              ),
            )
          : FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: _isSubmitting ? null : () => _openEntry(entry),
              child: const Text('Continue'),
            ),
    ),
  );

  Widget _overrideCard(AppUser user) => Card(
    margin: const EdgeInsets.only(top: 12),
    color: const Color(0xFFFFF4E6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Override incomplete sheet (${user.role.name})',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('A reason is required and recorded for audit.'),
          const SizedBox(height: 12),
          TextField(
            controller: _forceReasonController,
            enabled: !_isSubmitting,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Override reason'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
            onPressed:
                _isSubmitting || _forceReasonController.text.trim().isEmpty
                ? null
                : _forceSubmit,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Submit as incomplete'),
          ),
        ],
      ),
    ),
  );

  String _sectionLabel(InspectionSection section) =>
      section == InspectionSection.gearboxBreaker
      ? 'Gearbox Breaker'
      : 'Gearbox Sizer';
}

class _SummaryEntry {
  const _SummaryEntry({
    required this.section,
    required this.roundNumber,
    required this.entry,
    required this.label,
    required this.missing,
    this.side,
  });

  final InspectionSection section;
  final int roundNumber;
  final String? side;
  final String entry;
  final String label;
  final List<String> missing;
  bool get isComplete => missing.isEmpty;
}

class _SummaryGroup {
  _SummaryGroup({required this.section, required this.roundNumber});

  final InspectionSection section;
  final int roundNumber;
  final List<_SummaryEntry> entries = <_SummaryEntry>[];

  List<_SummaryEntry> get incomplete =>
      entries.where((entry) => !entry.isComplete).toList(growable: false);

  String get label =>
      '${section == InspectionSection.gearboxBreaker ? 'Gearbox Breaker' : 'Gearbox Sizer'} · Round $roundNumber';

  String get shortLabel =>
      '${section == InspectionSection.gearboxBreaker ? 'Breaker' : 'Sizer'} · R$roundNumber';
}
