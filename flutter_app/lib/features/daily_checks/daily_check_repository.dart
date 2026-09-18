import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/sicatat_types.dart';
import 'daily_check_forms.dart';

enum DailyCheckStatus { draft, submitted }

class DailyCheckSheet {
  const DailyCheckSheet({
    required this.id,
    required this.type,
    required this.date,
    required this.shiftId,
    required this.teamId,
    required this.status,
    required this.readings,
    required this.createdBy,
    required this.createdAt,
    this.shiftName,
    this.shiftCode,
    this.teamName,
    this.creatorName,
    this.submitterName,
    this.submittedAt,
    this.notes,
    this.approverName,
    this.approvedAt,
  });

  final String id;
  final DailyCheckFormType type;
  final DateTime date;
  final String shiftId;
  final String teamId;
  final DailyCheckStatus status;
  final Map<String, Map<String, Object?>> readings;
  final String createdBy;
  final DateTime createdAt;
  final String? shiftName;
  final String? shiftCode;
  final String? teamName;
  final String? creatorName;
  final String? submitterName;
  final DateTime? submittedAt;
  final String? notes;

  /// Foreman/supervisor who approved ("Mengetahui") the submitted sheet.
  final String? approverName;
  final DateTime? approvedAt;
  bool get isApproved => approvedAt != null;

  DailyCheckForm get form => type.form;

  DailyCheckSheet copyWithNotes(String? value) => DailyCheckSheet(
    id: id,
    type: type,
    date: date,
    shiftId: shiftId,
    teamId: teamId,
    status: status,
    readings: readings,
    createdBy: createdBy,
    createdAt: createdAt,
    shiftName: shiftName,
    shiftCode: shiftCode,
    teamName: teamName,
    creatorName: creatorName,
    submitterName: submitterName,
    submittedAt: submittedAt,
    notes: value == null || value.isEmpty ? null : value,
    approverName: approverName,
    approvedAt: approvedAt,
  );
  List<DailyCheckSlot> get slots => form.slotsForShift(shiftCode);
  bool get isDraft => status == DailyCheckStatus.draft;

  int get completeSlots => slots
      .where(
        (slot) =>
            form.slotState(readings[slot.key]) == DailyCheckSlotState.complete,
      )
      .length;

  double? get highestTemperature => form.highestTemperature(readings);

  DailyCheckTemperatureLevel get worstLevel => form.worstLevel(readings);

  String get shiftLabel => switch (shiftCode) {
    'PAGI' => 'Shift Pagi',
    'MALAM' => 'Shift Malam',
    _ => shiftName ?? 'Shift',
  };

  factory DailyCheckSheet.fromJson(JsonMap json) {
    final type = DailyCheckFormType.fromStorage(
      json.optionalString('form_type'),
    );
    if (type == null) {
      throw FormatException('Unknown form type: ${json['form_type']}');
    }
    final rawReadings = json['readings'];
    final readings = <String, Map<String, Object?>>{};
    if (rawReadings is Map) {
      rawReadings.forEach((key, value) {
        if (key is String && value is Map) {
          readings[key] = value.map(
            (field, fieldValue) => MapEntry(field.toString(), fieldValue),
          );
        }
      });
    }
    JsonMap? related(String key) {
      final value = json[key];
      return value == null ? null : requireJsonMap(value, source: key);
    }

    final submittedAt = json.optionalString('submitted_at');
    final approvedAt = json.optionalString('approved_at');
    return DailyCheckSheet(
      id: json.requiredString('id'),
      type: type,
      date: DateTime.parse(json.requiredString('tanggal')),
      shiftId: json.requiredString('shift_id'),
      teamId: json.requiredString('team_id'),
      status: json['status'] == 'submitted'
          ? DailyCheckStatus.submitted
          : DailyCheckStatus.draft,
      readings: readings,
      createdBy: json.requiredString('created_by'),
      createdAt: DateTime.parse(json.requiredString('created_at')).toLocal(),
      shiftName: related('shift')?.optionalString('name'),
      shiftCode: related('shift')?.optionalString('code'),
      teamName: related('team')?.optionalString('name'),
      creatorName: related('creator')?.optionalString('name'),
      submitterName: related('submitter')?.optionalString('name'),
      submittedAt: submittedAt == null
          ? null
          : DateTime.parse(submittedAt).toLocal(),
      notes: json.optionalString('notes'),
      approverName: related('approver')?.optionalString('name'),
      approvedAt: approvedAt == null
          ? null
          : DateTime.parse(approvedAt).toLocal(),
    );
  }
}

class DailyCheckTeam {
  const DailyCheckTeam({required this.id, required this.name});

  final String id;
  final String name;
}

/// Online-only access to `daily_check_sheet`. Row-level security decides what
/// each role may read and write; this class only shapes the calls.
class DailyCheckRepository {
  DailyCheckRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _columns =
      'id,form_type,tanggal,shift_id,team_id,status,readings,notes,'
      'created_by,created_at,submitted_at,approved_at,'
      'shift:shift_id(name,code),team:team_id(name),'
      'creator:app_user!daily_check_sheet_created_by_fkey(name),'
      'submitter:app_user!daily_check_sheet_submitted_by_fkey(name),'
      'approver:app_user!daily_check_sheet_approved_by_fkey(name)';

  Future<List<DailyCheckSheet>> list(DailyCheckFormType type) async {
    final Object rows = await _client
        .from('daily_check_sheet')
        .select(_columns)
        .eq('form_type', type.storageValue)
        .order('tanggal', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);
    return _sheets(rows);
  }

  /// Sheets in a date range, oldest first, for printing several at once.
  Future<List<DailyCheckSheet>> listRange(
    DailyCheckFormType type,
    DateTime from,
    DateTime to,
  ) async {
    final Object rows = await _client
        .from('daily_check_sheet')
        .select(_columns)
        .eq('form_type', type.storageValue)
        .gte('tanggal', _date(from))
        .lte('tanggal', _date(to))
        .order('tanggal', ascending: true)
        .order('created_at', ascending: true)
        .limit(400);
    return _sheets(rows);
  }

  /// Every form's sheets from [from] onwards, for reports.
  Future<List<DailyCheckSheet>> listSince(DateTime from) async {
    final Object rows = await _client
        .from('daily_check_sheet')
        .select(_columns)
        .gte('tanggal', _date(from))
        .order('tanggal', ascending: false)
        .limit(600);
    return _sheets(rows);
  }

  Future<void> approve(String id, {bool approve = true}) async {
    try {
      await _client.rpc<Object?>(
        'daily_check_approve',
        params: <String, Object?>{'p_id': id, 'p_approve': approve},
      );
    } on PostgrestException catch (error) {
      throw DailyCheckException(error.message);
    }
  }

  /// Loads per-point limits into [DailyCheckThresholds]. A failure keeps the
  /// limits already loaded (or the 60/70 °C default).
  Future<void> loadThresholds() async {
    try {
      final Object rows = await _client
          .from('daily_check_threshold')
          .select('form_type,field_key,warning_from,critical_from');
      if (rows is! List) return;
      final limits = <String, DailyCheckLimits>{};
      for (final raw in rows) {
        final row = requireJsonMap(raw, source: 'threshold');
        final type = DailyCheckFormType.fromStorage(
          row.optionalString('form_type'),
        );
        if (type == null) continue;
        limits[DailyCheckThresholds.key(
          type,
          row.requiredString('field_key'),
        )] = DailyCheckLimits(
          (row['warning_from']! as num).toDouble(),
          (row['critical_from']! as num).toDouble(),
        );
      }
      DailyCheckThresholds.replaceAll(limits);
    } on Object {
      // Colours fall back to the loaded or standard limits.
    }
  }

  Future<void> saveThreshold(
    DailyCheckFormType type,
    String fieldKey,
    DailyCheckLimits limits,
  ) async {
    try {
      await _client.from('daily_check_threshold').upsert(<String, Object?>{
        'form_type': type.storageValue,
        'field_key': fieldKey,
        'warning_from': limits.warning,
        'critical_from': limits.critical,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'form_type,field_key');
    } on PostgrestException catch (error) {
      throw DailyCheckException('Batas tidak dapat disimpan: ${error.message}');
    }
  }

  Future<void> resetThreshold(DailyCheckFormType type, String fieldKey) =>
      _client
          .from('daily_check_threshold')
          .delete()
          .eq('form_type', type.storageValue)
          .eq('field_key', fieldKey);

  Future<List<AlertRecipient>> alertRecipients() async {
    final Object rows = await _client
        .from('temperature_alert_recipient')
        .select('id,email,name,is_active')
        .order('email', ascending: true);
    if (rows is! List) return const <AlertRecipient>[];
    return rows
        .map((row) => AlertRecipient.fromJson(requireJsonMap(row)))
        .toList(growable: false);
  }

  Future<void> addAlertRecipient(String email, String? name) async {
    try {
      await _client.from('temperature_alert_recipient').insert(
        <String, Object?>{
          'email': email.trim().toLowerCase(),
          'name': name == null || name.trim().isEmpty ? null : name.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw DailyCheckException(
        error.code == '23505'
            ? 'Email ini sudah terdaftar.'
            : 'Email tidak dapat disimpan: ${error.message}',
      );
    }
  }

  Future<void> setAlertRecipientActive(String id, bool active) => _client
      .from('temperature_alert_recipient')
      .update(<String, Object?>{'is_active': active})
      .eq('id', id);

  Future<void> removeAlertRecipient(String id) =>
      _client.from('temperature_alert_recipient').delete().eq('id', id);

  /// Recent critical-temperature alerts the signed-in reviewer may see.
  Future<List<TemperatureAlert>> recentAlerts({int days = 14}) async {
    final Object rows = await _client
        .from('temperature_alert')
        .select(
          'id,form_label,point_label,value,limit_value,sheet_date,'
          'shift_label,occurred_at,status,team:team_id(name)',
        )
        .gte(
          'occurred_at',
          DateTime.now()
              .toUtc()
              .subtract(Duration(days: days))
              .toIso8601String(),
        )
        .order('occurred_at', ascending: false)
        .limit(100);
    if (rows is! List) return const <TemperatureAlert>[];
    return rows
        .map((row) => TemperatureAlert.fromJson(requireJsonMap(row)))
        .toList(growable: false);
  }

  Future<DailyCheckSheet?> get(String id) async {
    final Object? row = await _client
        .from('daily_check_sheet')
        .select(_columns)
        .eq('id', id)
        .maybeSingle();
    return row == null
        ? null
        : DailyCheckSheet.fromJson(requireJsonMap(row, source: 'sheet'));
  }

  Future<DailyCheckSheet> create({
    required DailyCheckFormType type,
    required DateTime date,
    required String shiftId,
    required String teamId,
    required String createdBy,
  }) async {
    try {
      final Object row = await _client
          .from('daily_check_sheet')
          .insert(<String, Object?>{
            'form_type': type.storageValue,
            'tanggal': _date(date),
            'shift_id': shiftId,
            'team_id': teamId,
            'created_by': createdBy,
          })
          .select(_columns)
          .single();
      return DailyCheckSheet.fromJson(requireJsonMap(row, source: 'sheet'));
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const DailyCheckException(
          'Lembar untuk tanggal dan shift ini sudah ada.',
        );
      }
      rethrow;
    }
  }

  Future<void> saveSlot(
    String id,
    String slotKey,
    Map<String, Object?> values,
  ) async {
    try {
      await _client.rpc<Object?>(
        'daily_check_save_slot',
        params: <String, Object?>{
          'p_id': id,
          'p_slot': slotKey,
          'p_values': values,
        },
      );
    } on PostgrestException catch (error) {
      throw DailyCheckException(error.message);
    }
  }

  Future<void> saveNotes(String id, String? notes) =>
      _update(id, <String, Object?>{'notes': notes});

  Future<void> submit(String id) =>
      _update(id, const <String, Object?>{'status': 'submitted'});

  Future<void> reopen(String id) =>
      _update(id, const <String, Object?>{'status': 'draft'});

  Future<void> delete(String id) async {
    final Object rows = await _client
        .from('daily_check_sheet')
        .delete()
        .eq('id', id)
        .select('id');
    if (rows is! List || rows.isEmpty) {
      throw const DailyCheckException(
        'Hanya lembar draf yang dapat dihapus oleh regunya.',
      );
    }
  }

  Future<Set<String>> occupiedShiftIds({
    required DailyCheckFormType type,
    required DateTime date,
    required String teamId,
  }) async {
    final Object rows = await _client.rpc<Object>(
      'daily_check_occupied_shifts',
      params: <String, Object?>{
        'p_form_type': type.storageValue,
        'p_tanggal': _date(date),
        'p_team_id': teamId,
      },
    );
    if (rows is! List) return <String>{};
    return rows
        .map((row) => row is Map ? row.values.first : row)
        .whereType<String>()
        .toSet();
  }

  Future<List<DailyCheckTeam>> activeTeams() async {
    final Object rows = await _client
        .from('team')
        .select('id,name')
        .eq('is_active', true)
        .order('code', ascending: true);
    if (rows is! List) return const <DailyCheckTeam>[];
    return rows
        .map((row) => requireJsonMap(row, source: 'team'))
        .map(
          (row) => DailyCheckTeam(
            id: row.requiredString('id'),
            name: row.requiredString('name'),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _update(String id, Map<String, Object?> values) async {
    try {
      final Object rows = await _client
          .from('daily_check_sheet')
          .update(values)
          .eq('id', id)
          .select('id');
      if (rows is! List || rows.isEmpty) {
        throw const DailyCheckException(
          'Anda tidak memiliki izin untuk mengubah lembar ini.',
        );
      }
    } on PostgrestException catch (error) {
      throw DailyCheckException(error.message);
    }
  }

  List<DailyCheckSheet> _sheets(Object rows) {
    if (rows is! List) throw const FormatException('Invalid sheet list.');
    return rows
        .map(
          (row) =>
              DailyCheckSheet.fromJson(requireJsonMap(row, source: 'sheet')),
        )
        .toList(growable: false);
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class DailyCheckException implements Exception {
  const DailyCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlertRecipient {
  const AlertRecipient({
    required this.id,
    required this.email,
    required this.isActive,
    this.name,
  });

  final String id;
  final String email;
  final String? name;
  final bool isActive;

  factory AlertRecipient.fromJson(JsonMap json) => AlertRecipient(
    id: json.requiredString('id'),
    email: json.requiredString('email'),
    name: json.optionalString('name'),
    isActive: json.requiredBool('is_active'),
  );
}

class TemperatureAlert {
  const TemperatureAlert({
    required this.id,
    required this.formLabel,
    required this.pointLabel,
    required this.value,
    required this.limit,
    required this.occurredAt,
    required this.status,
    this.teamName,
    this.shiftLabel,
    this.sheetDate,
  });

  final String id;
  final String formLabel;
  final String pointLabel;
  final double value;
  final double limit;
  final DateTime occurredAt;
  final String status;
  final String? teamName;
  final String? shiftLabel;
  final DateTime? sheetDate;

  factory TemperatureAlert.fromJson(JsonMap json) {
    final team = json['team'];
    final date = json.optionalString('sheet_date');
    return TemperatureAlert(
      id: json.requiredString('id'),
      formLabel: json.requiredString('form_label'),
      pointLabel: json.requiredString('point_label'),
      value: (json['value']! as num).toDouble(),
      limit: (json['limit_value']! as num).toDouble(),
      occurredAt: DateTime.parse(json.requiredString('occurred_at')).toLocal(),
      status: json.requiredString('status'),
      teamName: team is Map ? team['name']?.toString() : null,
      shiftLabel: json.optionalString('shift_label'),
      sheetDate: date == null ? null : DateTime.parse(date),
    );
  }
}
