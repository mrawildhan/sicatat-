import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One counter in a summary row, tappable to filter the list below it.
///
/// Suhu, Pengingat, Permintaan Barang, and Notulen each used to draw their own
/// version of this card at different heights and text sizes, which made the
/// same row look bigger on one screen than another. They all use this now.
class SummaryFilterCard extends StatelessWidget {
  const SummaryFilterCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  /// A null callback leaves the card visible but inert, for counters the
  /// current role may not open.
  final VoidCallback? onTap;
  final bool selected;

  /// Tall enough for an 18px icon, the metric, and its label without
  /// clipping: the content measures about 69 logical pixels.
  static const double _height = 76;
  static const double _radius = 18;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: onTap != null,
      selected: selected,
      label: '$label: $count',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(
                color: selected ? color.withValues(alpha: 0.5) : AppColors.line,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 3),
                Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.metric,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.badge.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Spacing between two [SummaryFilterCard]s.
class SummaryFilterGap extends StatelessWidget {
  const SummaryFilterGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 8);
}
