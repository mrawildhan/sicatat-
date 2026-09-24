import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Short date and time for source-update notes, e.g. "24/9/26 14.27".
String sourceUpdateStamp(DateTime value) =>
    DateFormat('d/M/yy HH.mm').format(value.toLocal());

/// Status card for data imported from a spreadsheet (Data PR, PM & CM):
/// when the spreadsheet last changed, and whether the latest check is
/// running, done, or failed. Green normally, orange after a failed check.
class SourceUpdateCard extends StatelessWidget {
  const SourceUpdateCard({
    required this.title,
    required this.changes,
    required this.checking,
    this.checkedAt,
    this.error,
    this.onRefresh,
    super.key,
  });

  final String title;

  /// One line per source, e.g. "Spreadsheet terakhir berubah … · 2.984 PR".
  final List<String> changes;
  final bool checking;
  final DateTime? checkedAt;

  /// Message of a failed latest check; the stored data is still shown.
  final String? error;

  /// Shows a "check again" button in the card when set.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final bool failed = !checking && error != null;
    final Color color = failed ? AppColors.orange : AppColors.green;
    final String status = checking
        ? 'Memeriksa perubahan spreadsheet…'
        : failed
        ? 'Pemeriksaan terakhir gagal: $error'
        : checkedAt == null
        ? 'Belum pernah diperiksa'
        : 'Terakhir diperiksa ${sourceUpdateStamp(checkedAt!)}';
    final TextStyle? small = Theme.of(context).textTheme.bodySmall;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 12, onRefresh == null ? 12 : 4, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          checking
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  failed ? Icons.sync_problem_rounded : Icons.schedule_rounded,
                  color: color,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                for (final String line in changes) Text(line, style: small),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: small?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Periksa ulang spreadsheet',
              onPressed: checking ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}
