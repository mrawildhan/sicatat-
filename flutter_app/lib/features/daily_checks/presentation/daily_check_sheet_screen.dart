import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../daily_check_forms.dart';
import '../daily_check_pdf.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

/// Sheet summary: one card per check/reading, red while values are missing,
/// with Submit pinned to the bottom (same flow as the Feeder/Sizer sheet).
class DailyCheckSheetScreen extends ConsumerStatefulWidget {
  const DailyCheckSheetScreen({
    required this.type,
    required this.sheetId,
    super.key,
  });

  final DailyCheckFormType type;
  final String sheetId;

  @override
  ConsumerState<DailyCheckSheetScreen> createState() =>
      _DailyCheckSheetScreenState();
}

class _DailyCheckSheetScreenState extends ConsumerState<DailyCheckSheetScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  final TextEditingController _notes = TextEditingController();
  DailyCheckSheet? _sheet;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _hubRoute => '/daily-checks/${widget.type.storageValue}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sheet = await _repository.get(widget.sheetId);
      if (!mounted) return;
      setState(() {
        _sheet = sheet;
        _notes.text = sheet?.notes ?? '';
        _error = sheet == null
            ? 'Sheet not found or not available to you.'
            : null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Sheet could not be loaded: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canWrite {
    final user = ref.read(currentUserProvider);
    final sheet = _sheet;
    if (user == null || sheet == null) return false;
    return user.role.isGlobalTemperatureManager ||
        (user.role == UserRole.crew && user.teamId == sheet.teamId);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
      await _load();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNotesIfChanged() async {
    final sheet = _sheet;
    if (sheet == null || !sheet.isDraft || !_canWrite) return;
    final text = _notes.text.trim();
    if (text == (sheet.notes ?? '')) return;
    await _repository.saveNotes(sheet.id, text.isEmpty ? null : text);
  }

  Future<void> _submit() async {
    final sheet = _sheet!;
    final incomplete = sheet.slots.length - sheet.completeSlots;
    final unit = widget.type == DailyCheckFormType.hydraulicFeeder
        ? 'check'
        : 'reading';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit this sheet?'),
        content: Text(
          incomplete == 0
              ? 'All ${sheet.slots.length} ${unit}s are complete. The sheet becomes final; you can reopen it later if a correction is needed.'
              : '$incomplete $unit${incomplete == 1 ? ' is' : 's are'} not complete yet. Submit anyway? The sheet becomes final; you can reopen it later.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _saveNotesIfChanged();
      await _repository.submit(sheet.id);
    }, 'Sheet submitted.');
  }

  Future<void> _reopen() => _run(
    () => _repository.reopen(_sheet!.id),
    'Sheet reopened for revision.',
  );

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'All values in this sheet will be removed. This cannot be undone.',
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
    setState(() => _busy = true);
    try {
      await _repository.delete(_sheet!.id);
      if (mounted) context.go(_hubRoute);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _export() async {
    final sheet = _sheet;
    if (sheet == null) return;
    setState(() => _busy = true);
    try {
      await _saveNotesIfChanged();
      await printDailyCheckSheet(sheet.copyWithNotes(_notes.text.trim()));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF could not be made: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSlot(DailyCheckSlot slot) async {
    await _saveNotesIfChanged();
    if (mounted) context.go('$_hubRoute/sheet/${widget.sheetId}/${slot.key}');
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return AppBackScope(
      fallbackRoute: _hubRoute,
      child: Scaffold(
        appBar: AppBar(
          leading: AppBackButton(fallbackRoute: _hubRoute),
          title: Text(
            widget.type.form.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            if (sheet != null)
              IconButton(
                tooltip: 'Print / export PDF',
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
            if (sheet != null && sheet.isDraft && _canWrite)
              PopupMenuButton<String>(
                tooltip: 'More options',
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                      title: Text('Delete draft'),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : sheet == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? 'Sheet not found.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              )
            : RefreshIndicator(onRefresh: _load, child: _content(sheet)),
        bottomNavigationBar: sheet == null || !_canWrite
            ? null
            : DailyCheckBottomBar(
                child: sheet.isDraft
                    ? ElevatedButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: busyIcon(_busy, Icons.send_rounded),
                        label: const Text('Submit sheet'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _busy ? null : _reopen,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Reopen for revision'),
                      ),
              ),
      ),
    );
  }

  Widget _content(DailyCheckSheet sheet) {
    final slots = sheet.slots;
    final highest = sheet.highestTemperature;
    final unitName = widget.type == DailyCheckFormType.hydraulicFeeder
        ? 'Checks'
        : 'Readings';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${DateFormat('EEE, dd MMM yyyy').format(sheet.date)} · ${sheet.shiftLabel}',
                        style: AppTextStyles.cardTitle.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    DailyCheckStatusChip(sheet.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Crew: ${sheet.teamName ?? '—'} · Created by ${sheet.creatorName ?? '—'}',
                  style: AppTextStyles.supporting,
                ),
                if (sheet.submittedAt case final submittedAt?)
                  Text(
                    'Submitted ${DateFormat('dd MMM yyyy, HH:mm').format(submittedAt)} by ${sheet.submitterName ?? '—'}',
                    style: AppTextStyles.supporting,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text(
                      '${sheet.completeSlots}/${slots.length} complete',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (highest != null)
                      TemperatureBadge(highest, prefix: 'Max '),
                  ],
                ),
                const SizedBox(height: 8),
                SlotProgressBar(
                  form: sheet.form,
                  slots: slots,
                  readings: sheet.readings,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(unitName, style: AppTextStyles.sectionTitle),
        const SizedBox(height: 4),
        Text(
          sheet.isDraft
              ? 'Red cards still have missing values. Tap a card to fill it.'
              : 'Tap a card to see its values.',
          style: AppTextStyles.supporting,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700
                ? 5
                : slots.length <= 3
                ? 3
                : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: columns == 3 ? 1.0 : 1.9,
              children: slots.map((slot) => _slotCard(sheet, slot)).toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Notes', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          enabled: sheet.isDraft && _canWrite && !_busy,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'General notes for this sheet (optional)',
          ),
          onEditingComplete: _saveNotesIfChanged,
        ),
      ],
    );
  }

  Widget _slotCard(DailyCheckSheet sheet, DailyCheckSlot slot) {
    final values = sheet.readings[slot.key];
    final state = sheet.form.slotState(values);
    final color = slotStateColor(state);
    final recorded = values?[DailyCheckForm.recordedAtKey];
    final recordedAt = recorded is String
        ? DateTime.tryParse(recorded)?.toLocal()
        : null;
    final missing = sheet.form.missingCount(values);
    final (icon, status) = switch (state) {
      DailyCheckSlotState.complete => (Icons.check_circle_rounded, 'Complete'),
      DailyCheckSlotState.partial => (Icons.error_rounded, '$missing missing'),
      DailyCheckSlotState.empty => (
        Icons.radio_button_unchecked,
        'Not started',
      ),
    };
    final timeText = recordedAt != null
        ? DateFormat('HH:mm').format(recordedAt)
        : slot.plannedTime;
    return Material(
      color: state == DailyCheckSlotState.partial
          ? const Color(0xFFFFECEB)
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _busy ? null : () => _openSlot(slot),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: state == DailyCheckSlotState.empty
                  ? AppColors.line
                  : color,
              width: state == DailyCheckSlotState.empty ? 1 : 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 22,
                color: state == DailyCheckSlotState.empty
                    ? AppColors.muted
                    : color,
              ),
              const SizedBox(height: 4),
              Text(
                slot.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (timeText != null)
                Text(
                  recordedAt != null ? 'at $timeText' : timeText,
                  style: AppTextStyles.badge.copyWith(color: AppColors.muted),
                ),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.badge.copyWith(
                  color: state == DailyCheckSlotState.empty
                      ? AppColors.muted
                      : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
