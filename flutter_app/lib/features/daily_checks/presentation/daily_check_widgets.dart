import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';

/// In-app temperature colours, matching the Feeder/Sizer form.
Color temperatureColor(double value) => switch (temperatureLevel(value)) {
  DailyCheckTemperatureLevel.critical => AppColors.danger,
  DailyCheckTemperatureLevel.warning => AppColors.warning,
  DailyCheckTemperatureLevel.normal => AppColors.green,
};

String formatReading(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class DailyCheckStatusChip extends StatelessWidget {
  const DailyCheckStatusChip(this.status, {super.key});

  final DailyCheckStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      DailyCheckStatus.draft => (
        'Draft',
        AppColors.orange,
        Icons.edit_note_rounded,
      ),
      DailyCheckStatus.submitted => (
        'Submitted',
        AppColors.green,
        Icons.cloud_done_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.badge.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class TemperatureBadge extends StatelessWidget {
  const TemperatureBadge(this.value, {this.prefix = '', super.key});

  final double value;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final color = temperatureColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$prefix${formatReading(value)} °C',
        style: AppTextStyles.badge.copyWith(
          color: color == AppColors.warning ? const Color(0xFF9A6A00) : color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Color slotStateColor(DailyCheckSlotState state) => switch (state) {
  DailyCheckSlotState.complete => AppColors.green,
  DailyCheckSlotState.partial => AppColors.danger,
  DailyCheckSlotState.empty => AppColors.line,
};

/// One segment per check/reading: green complete, red started but missing
/// values, grey not started.
class SlotProgressBar extends StatelessWidget {
  const SlotProgressBar({
    required this.form,
    required this.slots,
    required this.readings,
    super.key,
  });

  final DailyCheckForm form;
  final List<DailyCheckSlot> slots;
  final Map<String, Map<String, Object?>> readings;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (var i = 0; i < slots.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: slotStateColor(form.slotState(readings[slots[i].key])),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ],
  );
}

class DailyCheckNotice extends StatelessWidget {
  const DailyCheckNotice(this.text, {this.error = false, super.key});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFECEB) : AppColors.mint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          color: error ? AppColors.danger : AppColors.green,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              height: 1.4,
              color: error ? AppColors.danger : AppColors.greenDark,
              fontWeight: error ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}

/// White bar pinned to the bottom, like the Feeder/Sizer form.
class DailyCheckBottomBar extends StatelessWidget {
  const DailyCheckBottomBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
      child: child,
    ),
  );
}

Widget busyIcon(bool busy, IconData icon) => busy
    ? const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      )
    : Icon(icon);
