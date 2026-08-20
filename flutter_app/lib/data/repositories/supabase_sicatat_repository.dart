import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/field_entry_models.dart';
import '../models/master_data_models.dart';
import '../models/sheet_model.dart';
import '../models/sicatat_types.dart';
import '../sync/sync_service.dart';
import 'sicatat_repository.dart';

/// Typed remote gateway for the existing SICATAT Supabase schema.
/// Widgets do not access Supabase directly. The offline repository will use
/// this gateway only when processing its SQLite sync queue.
class SupabaseSicatatRepository implements SicatatRepository {
  SupabaseSicatatRepository(this.client);

  final SupabaseClient client;
  final Uuid _uuid = const Uuid();

  @override
  Future<AppUser> signIn({required String nik, required String pin}) async {
    final normalizedNik = nik.trim();
    if (normalizedNik.isEmpty || pin.isEmpty) {
      throw const FormatException('Crew ID and PIN are required.');
    }

    try {
      await client.auth.signInWithPassword(
        email: '$normalizedNik@sicatat.local',
        password: pin,
      );
      final Object row = await client
          .from('app_user')
          .select('id, nik, name, role, team_id, phone, is_active')
          .eq('nik', normalizedNik)
          .eq('is_active', true)
          .single();
      return AppUser.fromJson(requireJsonMap(row, source: 'profil pengguna'));
    } on AuthException {
      throw const FormatException('Crew ID or PIN is invalid.');
    } on PostgrestException {
      await client.auth.signOut();
      throw const FormatException('Crew ID or PIN is invalid.');
    }
  }

  @override
  Future<AppUser?> restoreSession() async {
    final email = client.auth.currentSession?.user.email;
    if (email == null || !email.endsWith('@sicatat.local')) return null;
    final nik = email.substring(0, email.length - '@sicatat.local'.length);
    try {
      final Object row = await client
          .from('app_user')
          .select('id, nik, name, role, team_id, phone, is_active')
          .eq('nik', nik)
          .eq('is_active', true)
          .single();
      return AppUser.fromJson(requireJsonMap(row, source: 'profil pengguna'));
    } on PostgrestException {
      await client.auth.signOut();
      return null;
    }
  }

  @override
  Future<List<ShiftOption>> getActiveShifts() async {
    final Object response = await client
        .from('shift')
        .select('id, code, name')
        .eq('is_active', true)
        .order('code');
    if (response is! List) {
      throw const FormatException('The server returned an invalid shift list.');
    }
    final shifts = response
        .map(
          (Object? row) =>
              ShiftOption.fromJson(requireJsonMap(row, source: 'shift')),
        )
        .toList(growable: false);
    shifts.sort(
      (left, right) =>
          _shiftSortKey(left.code).compareTo(_shiftSortKey(right.code)),
    );
    return shifts;
  }

  @override
  Future<TemperatureTemplate> getActiveTemperatureTemplate() async {
    final Object moduleRow = await client
        .from('module')
        .select('id')
        .eq('code', 'temperature_check')
        .eq('is_active', true)
        .single();
    final moduleId = requireJsonMap(
      moduleRow,
      source: 'modul suhu',
    ).requiredString('id');
    try {
      final Object templateRow = await client
          .from('form_template')
          .select('version, schema_json')
          .eq('module_id', moduleId)
          .eq('is_active', true)
          .order('effective_from', ascending: false)
          .limit(1)
          .single();
      final json = requireJsonMap(templateRow, source: 'template suhu');
      return TemperatureTemplate(
        moduleId: moduleId,
        version: json.requiredString('version'),
        schema: json['schema_json'] is Map
            ? requireJsonMap(json['schema_json'], source: 'schema template')
            : null,
      );
    } on PostgrestException {
      // Early SICATAT deployments had the active module, equipment, and
      // measurement points but no form_template row. The sheet schema keeps
      // its version as a snapshot string (not a foreign key), so a stable
      // compatibility value lets crews create a safe draft while the admin
      // completes template master data later.
      return TemperatureTemplate(
        moduleId: moduleId,
        version: 'legacy-temperature-v1',
      );
    }
  }

  @override
  Future<List<MeasurementPoint>> getGearboxMeasurementPoints() async {
    final Object response = await client
        .from('measurement_point')
        .select(
          'id, code, label, equipment_id, data_type, unit, is_required, sort_order',
        )
        .isFilter('equipment_id', null)
        .eq('is_active', true)
        .order('sort_order');
    if (response is! List) {
      throw const FormatException(
        'The server returned invalid gearbox measurement points.',
      );
    }
    const expectedCodes = <String>[
      'gb_low_speed',
      'gb_intermediate',
      'gb_high_speed',
      'gb_input_shaft',
    ];
    final byCode = <String, MeasurementPoint>{};
    for (final Object? row in response) {
      final point = MeasurementPoint.fromJson(
        requireJsonMap(row, source: 'titik ukur'),
      );
      byCode[point.code] = point;
    }
    final points = <MeasurementPoint>[];
    for (final code in expectedCodes) {
      final point = byCode[code];
      if (point == null) {
        throw FormatException(
          'Measurement point $code is not available on the server.',
        );
      }
      points.add(point);
    }
    return points;
  }

  @override
  Future<InspectionFormConfig> getInspectionFormConfig() async {
    final template = await getActiveTemperatureTemplate();
    final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
      client
          .from('equipment')
          .select('id, code, name, section, sort_order')
          .eq('is_active', true)
          .order('section')
          .order('sort_order'),
      client
          .from('measurement_point')
          .select(
            'id, code, label, equipment_id, data_type, unit, is_required, sort_order',
          )
          .eq('is_active', true)
          .order('sort_order'),
      _loadActiveThresholdRows(),
    ]);
    if (responses[0] is! List || responses[1] is! List || responses[2] is! List) {
      throw const FormatException(
        'The server returned invalid form master data.',
      );
    }
    final equipment = (responses[0] as List)
        .map(
          (Object? row) => InspectionEquipment.fromJson(
            requireJsonMap(row, source: 'equipment'),
          ),
        )
        .toList(growable: false);
    final points = (responses[1] as List)
        .map(
          (Object? row) => MeasurementPoint.fromJson(
            requireJsonMap(row, source: 'measurement point'),
          ),
        )
        .toList(growable: false);
    final thresholdByPoint = <String, ThresholdRule>{};
    for (final Object? row in responses[2] as List) {
      final threshold = ThresholdRule.fromJson(
        requireJsonMap(row, source: 'threshold'),
      );
      // The newest active threshold is authoritative when historical rows are
      // retained on the server.
      thresholdByPoint.putIfAbsent(threshold.measurementPointId, () => threshold);
    }
    return InspectionFormConfig(
      equipment: equipment,
      measurementPoints: points,
      thresholds: thresholdByPoint.values.toList(growable: false),
      steps: _stepsFromSchema(template.schema),
    );
  }

  @override
  Future<List<SheetModel>> listSheets() async {
    return listSharedSheets();
  }

  @override
  Future<List<SheetModel>> listSharedSheets({
    String? teamId,
    String? createdBy,
  }) async {
    final Object response;
    if (createdBy != null) {
      response = await client
          .from('sheet')
          .select('*, team:team_id(name), shift:shift_id(name)')
          .eq('created_by', createdBy)
          .order('tanggal', ascending: false);
    } else if (teamId == null) {
      response = await client
          .from('sheet')
          .select('*, team:team_id(name), shift:shift_id(name)')
          .order('tanggal', ascending: false);
    } else {
      response = await client
          .from('sheet')
          .select('*, team:team_id(name), shift:shift_id(name)')
          .eq('team_id', teamId)
          .order('tanggal', ascending: false);
    }
    if (response is! List) {
      throw const FormatException('The server returned an invalid sheet list.');
    }
    return response
        .map(
          (Object? row) => SheetModel.fromRemoteRow(
            requireJsonMap(row, source: 'lembar server'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SheetModel> createSheet(CreateSheetCommand command) async {
    final id = _uuid.v4();
    final clientUuid = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final Object row = await client
        .from('sheet')
        .insert(<String, Object?>{
          'id': id,
          'client_uuid': clientUuid,
          'module_id': command.moduleId,
          'template_version': command.templateVersion,
          'tanggal': _dateOnly(command.date),
          'shift_id': command.shiftId,
          'team_id': command.teamId,
          'status': SheetStatus.draft.storageValue,
          'created_by': command.createdBy,
          'created_at': createdAt.toIso8601String(),
        })
        .select()
        .single();
    return SheetModel.fromRemoteRow(requireJsonMap(row, source: 'lembar baru'));
  }

  @override
  Future<void> syncPending() async {
    await SyncService(client).syncPending();
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  int _shiftSortKey(String code) => switch (code) {
    'PAGI' => 0,
    'MALAM' => 1,
    _ => 2,
  };

  List<InspectionStep> _stepsFromSchema(JsonMap? schema) {
    final rawSteps = schema?['steps'];
    if (rawSteps is! List) return InspectionFormConfig.defaultSteps;
    final steps = <InspectionStep>[];
    for (final Object? rawStep in rawSteps) {
      if (rawStep is! Map) continue;
      final step = requireJsonMap(rawStep, source: 'langkah template');
      final sectionValue = step.optionalString('section');
      final roundNumber = step['round_number'];
      if (sectionValue == null || roundNumber is! num || roundNumber < 1) {
        continue;
      }
      try {
        steps.add(
          InspectionStep(
            section: InspectionSectionX.fromStorage(sectionValue),
            roundNumber: roundNumber.toInt(),
          ),
        );
      } on FormatException {
        // A template may contain a future section not supported by this mobile
        // build. Keep the current supported steps usable until that section is
        // shipped, rather than rendering a malformed operational form.
      }
    }
    return steps.isEmpty ? InspectionFormConfig.defaultSteps : steps;
  }

  Future<Object> _loadActiveThresholdRows() async {
    try {
      return await client
          .from('threshold')
          .select(
            'measurement_point_id, warning_min, warning_max, alarm_min, alarm_max, delta_max_per_round',
          )
          .eq('is_active', true)
          .order('effective_from', ascending: false);
    } on PostgrestException {
      // Thresholds strengthen validation but must not make a critical field
      // form unusable in an older deployment where this master table has not
      // yet been granted to crew accounts.
      return const <Object>[];
    }
  }
}
