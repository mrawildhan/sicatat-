import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SyncState { draft, synced, pending, conflict }

class SyncChip extends StatelessWidget {
  const SyncChip(this.state, {super.key});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      SyncState.draft => ('Draf', AppColors.warning, Icons.edit_note_rounded),
      SyncState.synced => (
        'Tersinkron',
        AppColors.green,
        Icons.cloud_done_rounded,
      ),
      SyncState.pending => (
        'Belum tersinkron',
        AppColors.orange,
        Icons.cloud_upload_rounded,
      ),
      SyncState.conflict => (
        'Konflik',
        AppColors.danger,
        Icons.warning_amber_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
