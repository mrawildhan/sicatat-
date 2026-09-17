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
      'created_by,created_at,submitted_at,'
      'shift:shift_id(name,code),team:team_id(name),'
      'creator:app_user!daily_check_sheet_created_by_fkey(name),'
      'submitter:app_user!daily_check_sheet_submitted_by_fkey(name)';

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
