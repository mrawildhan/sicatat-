import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../check_reminders.dart';
import '../check_schedule.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';

/// Beranda card for crew and foremen: today's Hydraulic Feeder checks of the
/// team on duty, which are done and which are late, plus Coal Valve progress.
/// Also (re)schedules the Android check reminders.
class CheckScheduleCard extends StatefulWidget {
  const CheckScheduleCard({required this.user, super.key});

  final AppUser user;

  @override
  State<CheckScheduleCard> createState() => _CheckScheduleCardState();
}

class _CheckScheduleCardState extends State<CheckScheduleCard> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  bool _loading = true;
  bool _onDuty = false;
  DateTime? _sheetDate;
  String? _shiftCode;
  ScheduledCheck? _nextDuty;
  DailyCheckSheet? _hydraulic;
  DailyCheckSheet? _coalValve;

  /// A check counts as late this long after its planned time.
  static const Duration _grace = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _load();
    CheckReminders.refresh(widget.user);
  }

  Future<void> _load() async {
    try {
      final roster = await loadRosterForTeam(widget.user.teamId);
      if (roster == null) return;
      final (anchor, teamCode) = roster;
      final now = DateTime.now();
      final (date, shift) = currentShift(now);
      final onDuty = anchor.teamCodeFor(date, shift) == teamCode;
      DailyCheckSheet? hydraulic;
      DailyCheckSheet? coalValve;
      ScheduledCheck? next;
      if (onDuty) {
        await _repository.loadThresholds();
        DailyCheckSheet? find(List<DailyCheckSheet> sheets) => sheets
            .where(
              (sheet) =>
                  sheet.teamId == widget.user.teamId &&
                  sheet.shiftCode == shift,
            )
            .firstOrNull;
        hydraulic = find(
          await _repository.listRange(
            DailyCheckFormType.hydraulicFeeder,
            date,
            date,
          ),
        );
        coalValve = find(
          await _repository.listRange(DailyCheckFormType.coalValve, date, date),
        );
      } else {
        next = upcomingChecks(anchor, teamCode, from: now).firstOrNull;
      }
      if (!mounted) return;
      setState(() {
        _onDuty = onDuty;
        _sheetDate = date;
        _shiftCode = shift;
        _hydraulic = hydraulic;
        _coalValve = coalValve;
        _nextDuty = next;
      });
    } on Object {
      // The card is a convenience; the dashboard works without it.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(DailyCheckFormType type, DailyCheckSheet? sheet) {
    context.go(
      sheet == null
          ? '/daily-checks/${type.storageValue}/new'
          : '/daily-checks/${type.storageValue}/sheet/${sheet.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _sheetDate == null) return const SizedBox.shrink();
    final shiftName = _shiftCode == 'PAGI' ? 'Shift Pagi' : 'Shift Malam';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _onDuty ? _duty(shiftName) : _offDuty(),
    );
  }

  Widget _offDuty() {
    final next = _nextDuty;
    return Row(
      children: <Widget>[
        const Icon(Icons.event_available_outlined, color: AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            next == null
                ? 'Regu Anda sedang tidak bertugas.'
                : 'Regu Anda tidak bertugas sekarang. Pengecekan Hydraulic '
                      'berikutnya ${DateFormat('EEEE d MMM, HH:mm').format(next.dueAt)} '
                      '(${next.shiftCode == 'PAGI' ? 'Shift Pagi' : 'Shift Malam'}).',
            style: AppTextStyles.supporting,
          ),
        ),
      ],
    );
  }

  Widget _duty(String shiftName) {
    final now = DateTime.now();
    final hydraulic = _hydraulic;
    final coal = _coalValve;
    final checks = checksForShift(_sheetDate!, _shiftCode!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.alarm_rounded, color: AppColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Jadwal pengecekan · $shiftName',
                style: AppTextStyles.cardTitle.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Daily Check Sheet Hydraulic Feeder',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            for (final check in checks)
              Expanded(child: _checkChip(check, hydraulic, now)),
          ],
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(DailyCheckFormType.coalValve, coal),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Temperature Coal Valve',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  coal == null
                      ? 'Belum dibuat'
                      : '${coal.completeSlots}/${coal.slots.length} pembacaan',
                  style: AppTextStyles.supporting,
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
        if (CheckReminders.supported)
          const Text(
            'Notifikasi muncul 10 menit sebelum tiap jadwal Hydraulic.',
            style: AppTextStyles.badge,
          ),
      ],
    );
  }

  Widget _checkChip(
    ScheduledCheck check,
    DailyCheckSheet? sheet,
    DateTime now,
  ) {
    final state = sheet == null
        ? DailyCheckSlotState.empty
        : sheet.form.slotState(sheet.readings[check.slot.key]);
    final late =
        state != DailyCheckSlotState.complete &&
        now.isAfter(check.dueAt.add(_grace));
    final (color, label) = switch (state) {
      DailyCheckSlotState.complete => (AppColors.green, 'Selesai'),
      _ when late => (AppColors.danger, 'Terlambat'),
      DailyCheckSlotState.partial => (AppColors.orange, 'Belum lengkap'),
      DailyCheckSlotState.empty => (
        now.isAfter(check.dueAt.subtract(const Duration(minutes: 30)))
            ? AppColors.orange
            : AppColors.muted,
        'Belum',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => sheet == null
              ? _open(DailyCheckFormType.hydraulicFeeder, null)
              : context.go(
                  '/daily-checks/hydraulic_feeder/sheet/${sheet.id}/${check.slot.key}',
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Column(
              children: <Widget>[
                Text(
                  check.slot.plannedTime!,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.badge.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
