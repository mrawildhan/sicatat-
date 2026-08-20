import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/local_database.dart';
import '../models/sync_queue_item.dart';

class SyncResult {
  const SyncResult({
    required this.synced,
    required this.failed,
    required this.conflicted,
  });

  final int synced;
  final int failed;
  final int conflicted;
}

/// Queue processor with local parent checks for safe offline retry.
class SyncService {
  SyncService(this._client, {LocalDatabase? database})
    : _database = database ?? LocalDatabase.instance;

  final SupabaseClient _client;
  final LocalDatabase _database;
  static bool _isSyncing = false;

  Future<SyncResult> syncPending() async {
    if (_isSyncing) {
      return const SyncResult(synced: 0, failed: 0, conflicted: 0);
    }
    _isSyncing = true;
    var synced = 0;
    var failed = 0;
    var conflicted = 0;
    try {
      final items = await _database.getPendingSyncItems();
      for (final item in items) {
        final parentStatus = await _database.getParentSyncStatus(item);
        if (parentStatus == SyncParentStatus.pending) {
          // Its parent will be retried first. Continue to unrelated sheets so
          // one interrupted tree cannot block the whole outbox.
          continue;
        }
        if (parentStatus == SyncParentStatus.conflict ||
            parentStatus == SyncParentStatus.missing) {
          await _database.markSyncConflict(item);
          conflicted += 1;
          continue;
        }
        try {
          await _send(item);
          await _database.markSyncSuccess(item);
          synced += 1;
        } on PostgrestException catch (error) {
          if (item.entityType == SyncEntityType.sheet &&
              item.operation == SyncOperation.insert &&
              (error.code == '23505' ||
                  error.message.contains('duplicate key value') ||
                  error.message.contains('A sheet already exists'))) {
            await _database.markSyncConflict(item);
            conflicted += 1;
            continue;
          }
          await _database.markSyncFailure(item, error.message);
          failed += 1;
          continue;
        } catch (error) {
          await _database.markSyncFailure(item, error.toString());
          failed += 1;
          continue;
        }
      }
      return SyncResult(synced: synced, failed: failed, conflicted: conflicted);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _send(SyncQueueItem item) async {
    final table = item.entityType.storageValue;
    final payload = <String, dynamic>{
      for (final entry in item.payload.entries) entry.key: entry.value,
    };
    // sync_status is an Android SQLite-only column. Older Capacitor queues
    // included it in JSON, which made Supabase reject otherwise valid rows.
    payload.remove('sync_status');
    final rawTime = payload['jam'];
    if (item.entityType == SyncEntityType.round && rawTime is String) {
      final normalizedTime = await _database.normalizeLegacyRoundTime(
        item.clientUuid,
        rawTime,
      );
      if (normalizedTime != null) {
        payload['jam'] = normalizedTime;
      }
    }
    if (item.operation == SyncOperation.insert) {
      final conflictKey = switch (item.entityType) {
        SyncEntityType.sheetContributor => 'sheet_id,user_id',
        // audit_log intentionally has no client_uuid on Supabase. Its UUID
        // primary key makes retries idempotent without weakening the audit
        // table's public schema.
        SyncEntityType.auditLog => 'id',
        _ => 'client_uuid',
      };
      await _client.from(table).upsert(payload, onConflict: conflictKey);
      return;
    }
    final Object response = await _client
        .from(table)
        .update(payload)
        .eq('client_uuid', item.clientUuid)
        .select('client_uuid');
    if (response is! List || response.isEmpty) {
      throw StateError('The $table row to sync was not found on the server.');
    }
  }
}
