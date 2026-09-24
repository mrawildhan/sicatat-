import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/sicatat_types.dart';
import '../theme/app_theme.dart';

/// Short date and 24-hour time, e.g. "24/9/26 14.13".
String sourceUpdateStamp(DateTime value) =>
    DateFormat('d/M/yy HH.mm').format(value.toLocal());

/// Newest Drive "Date modified" of [sources] in `data_source_status`
/// (written by the sync functions), or null when none is known yet.
Future<DateTime?> loadSourceModified(
  SupabaseClient client,
  List<String> sources,
) async {
  final Object response = await client
      .from('data_source_status')
      .select('modified_at')
      .inFilter('source', sources);
  if (response is! List) return null;
  DateTime? newest;
  for (final Object? row in response) {
    final DateTime? time = DateTime.tryParse(
      requireJsonMap(row).optionalString('modified_at') ?? '',
    );
    if (time != null && (newest == null || time.isAfter(newest))) {
      newest = time;
    }
  }
  return newest?.toLocal();
}

/// Two-line status for data imported from Drive spreadsheets (Data PR,
/// PM & CM, Anggaran, Gudang): the title, then when the file was last
/// modified in Drive, the running check, or a failed check.
class SourceUpdateCard extends StatelessWidget {
  const SourceUpdateCard({
    required this.title,
    required this.checking,
    this.updatedAt,
    this.error,
    this.onRefresh,
    super.key,
  });

  final String title;
  final bool checking;

  /// The Drive "Date modified" of the file(s) behind the screen.
  final DateTime? updatedAt;

  /// Message of a failed latest check; the stored data is still shown.
  final String? error;

  /// Shows a "check again" button in the card when set.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final bool failed = !checking && error != null;
    final Color color = failed ? AppColors.orange : AppColors.green;
    final String status = checking
        ? 'Memeriksa pembaruan…'
        : failed
        ? 'Gagal memeriksa: $error'
        : updatedAt == null
        ? 'Tanggal pembaruan belum tersedia'
        : 'Terakhir diperbarui ${sourceUpdateStamp(updatedAt!)}';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 8, onRefresh == null ? 12 : 2, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  failed ? Icons.sync_problem_rounded : Icons.schedule_rounded,
                  color: color,
                  size: 20,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Periksa ulang',
              visualDensity: VisualDensity.compact,
              onPressed: checking ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
