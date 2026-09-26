import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/sicatat_types.dart';
import '../../data/reports/meeting_minute_photo_compressor.dart';

/// What happened after a critical temperature (owner request 2026-09-26):
/// every value at or above the critical limit is recorded in
/// `temperature_alert` by the dispatch cron; reviewers then follow it up.
enum AlertFollowUpStatus {
  open('open', 'Terbuka'),
  inProgress('in_progress', 'Ditangani'),
  closed('closed', 'Ditutup');

  const AlertFollowUpStatus(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static AlertFollowUpStatus fromStorage(String? value) =>
      AlertFollowUpStatus.values.firstWhere(
        (AlertFollowUpStatus status) => status.storageValue == value,
        orElse: () => AlertFollowUpStatus.open,
      );

  Color get color => switch (this) {
    AlertFollowUpStatus.open => AppColors.danger,
    AlertFollowUpStatus.inProgress => AppColors.orange,
    AlertFollowUpStatus.closed => AppColors.green,
  };
}

class TemperatureAlertRecord {
  const TemperatureAlertRecord({
    required this.id,
    required this.formLabel,
    required this.pointLabel,
    required this.value,
    required this.limitValue,
    required this.occurredAt,
    required this.status,
    this.sheetDate,
    this.shiftLabel,
    this.teamName,
    this.siteName,
    this.action,
    this.workOrder,
    this.photoPath,
    this.handlerName,
    this.followUpAt,
    this.closedAt,
  });

  static const String columns =
      'id,form_label,point_label,value,limit_value,sheet_date,shift_label,'
      'occurred_at,followup_status,followup_action,followup_work_order,'
      'followup_photo_path,followup_at,closed_at,team:team_id(name),'
      'site:site_id(name),handler:followup_by(name)';

  final String id;
  final String formLabel;
  final String pointLabel;
  final double value;
  final double limitValue;
  final DateTime occurredAt;
  final AlertFollowUpStatus status;
  final DateTime? sheetDate;
  final String? shiftLabel;
  final String? teamName;
  final String? siteName;
  final String? action;
  final String? workOrder;
  final String? photoPath;
  final String? handlerName;
  final DateTime? followUpAt;
  final DateTime? closedAt;

  bool get isClosed => status == AlertFollowUpStatus.closed;

  /// Days the alert has been open, or took until it was closed.
  int ageDays(DateTime now) =>
      (closedAt ?? now).difference(occurredAt).inHours ~/ 24;

  String get searchText => <String?>[
    formLabel,
    pointLabel,
    teamName,
    shiftLabel,
    action,
    workOrder,
    handlerName,
  ].whereType<String>().join(' ').toLowerCase();

  factory TemperatureAlertRecord.fromJson(JsonMap json) {
    String? nameOf(String key) {
      final Object? value = json[key];
      return value is Map ? value['name']?.toString() : null;
    }

    return TemperatureAlertRecord(
      id: json.requiredString('id'),
      formLabel: json.requiredString('form_label'),
      pointLabel: json.requiredString('point_label'),
      value: (json['value']! as num).toDouble(),
      limitValue: (json['limit_value']! as num).toDouble(),
      occurredAt: DateTime.parse(json.requiredString('occurred_at')).toLocal(),
      status: AlertFollowUpStatus.fromStorage(
        json.optionalString('followup_status'),
      ),
      sheetDate: DateTime.tryParse(json.optionalString('sheet_date') ?? ''),
      shiftLabel: json.optionalString('shift_label'),
      teamName: nameOf('team'),
      siteName: nameOf('site'),
      action: json.optionalString('followup_action'),
      workOrder: json.optionalString('followup_work_order'),
      photoPath: json.optionalString('followup_photo_path'),
      handlerName: nameOf('handler'),
      followUpAt: DateTime.tryParse(json.optionalString('followup_at') ?? '')
          ?.toLocal(),
      closedAt: DateTime.tryParse(json.optionalString('closed_at') ?? '')
          ?.toLocal(),
    );
  }
}

/// One change of an alert's follow-up, from `audit_log`.
class AlertFollowUpEntry {
  const AlertFollowUpEntry({
    required this.at,
    required this.status,
    this.action,
    this.workOrder,
    this.byName,
  });

  final DateTime at;
  final AlertFollowUpStatus status;
  final String? action;
  final String? workOrder;
  final String? byName;
}

class AlertFollowUpService {
  AlertFollowUpService(this._client);

  final SupabaseClient _client;

  static const String photoBucket = 'temperature-alert-photos';

  /// Alerts from [from] (inclusive) to [to] (exclusive), newest first. Row
  /// level security limits them to what the user reviews.
  Future<List<TemperatureAlertRecord>> load({
    required DateTime from,
    required DateTime to,
  }) async {
    final Object rows = await _client
        .from('temperature_alert')
        .select(TemperatureAlertRecord.columns)
        .gte('occurred_at', from.toUtc().toIso8601String())
        .lt('occurred_at', to.toUtc().toIso8601String())
        .order('occurred_at', ascending: false)
        .limit(1000);
    return _parse(rows);
  }

  /// Every alert that is not closed yet, whatever its age.
  Future<List<TemperatureAlertRecord>> loadUnclosed() async {
    final Object rows = await _client
        .from('temperature_alert')
        .select(TemperatureAlertRecord.columns)
        .neq('followup_status', AlertFollowUpStatus.closed.storageValue)
        .order('occurred_at', ascending: false)
        .limit(1000);
    return _parse(rows);
  }

  List<TemperatureAlertRecord> _parse(Object rows) {
    if (rows is! List) {
      throw const FormatException('Data peringatan suhu tidak valid.');
    }
    return rows
        .map(
          (Object? row) => TemperatureAlertRecord.fromJson(
            requireJsonMap(row, source: 'temperature alert'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<AlertFollowUpEntry>> history(String alertId) async {
    final Object rows = await _client
        .from('audit_log')
        .select('new_value,changed_at,changer:changed_by(name)')
        .eq('entity_type', 'temperature_alert')
        .eq('entity_id', alertId)
        .order('changed_at', ascending: false)
        .limit(50);
    if (rows is! List) return const <AlertFollowUpEntry>[];
    return <AlertFollowUpEntry>[
      for (final Object? raw in rows)
        () {
          final JsonMap row = requireJsonMap(raw, source: 'audit log');
          final Object? value = row['new_value'];
          final Map<Object?, Object?> change = value is Map
              ? value
              : const <Object?, Object?>{};
          final Object? changer = row['changer'];
          return AlertFollowUpEntry(
            at: DateTime.parse(row.requiredString('changed_at')).toLocal(),
            status: AlertFollowUpStatus.fromStorage(
              change['status']?.toString(),
            ),
            action: change['action']?.toString(),
            workOrder: change['work_order']?.toString(),
            byName: changer is Map ? changer['name']?.toString() : null,
          );
        }(),
    ];
  }

  Future<void> save({
    required String alertId,
    required AlertFollowUpStatus status,
    required String action,
    required String workOrder,
    required String? photoPath,
  }) => _client.rpc<void>(
    'temperature_alert_follow_up',
    params: <String, Object?>{
      'p_id': alertId,
      'p_status': status.storageValue,
      'p_action': action,
      'p_work_order': workOrder,
      'p_photo_path': photoPath,
    },
  );

  /// Compresses the photo to about 300 KB (Supabase free plan) and stores it
  /// under the alert's folder. Returns the storage path.
  Future<String> uploadPhoto({
    required String alertId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final CompressedMeetingMinutePhoto photo =
        MeetingMinutePhotoCompressor.compress(
          bytes: bytes,
          fileName: fileName,
          maxDimension: 1280,
          targetBytes: 300 * 1024,
        );
    final String extension =
        photo.mimeType == MeetingMinutePhotoCompressor.pngMimeType
        ? 'png'
        : 'jpg';
    final String path =
        '$alertId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(
          path,
          photo.bytes,
          fileOptions: FileOptions(contentType: photo.mimeType),
        );
    return path;
  }

  Future<void> removePhoto(String path) =>
      _client.storage.from(photoBucket).remove(<String>[path]);

  Future<Uint8List> downloadPhoto(String path) =>
      _client.storage.from(photoBucket).download(path);
}
