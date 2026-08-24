import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sicatat_types.dart';
import '../models/master_data_models.dart';

class ReportRow {
  const ReportRow({
    required this.date,
    required this.team,
    required this.shift,
    required this.section,
    required this.round,
    required this.time,
    required this.side,
    required this.unitStatus,
    required this.equipment,
    required this.point,
    required this.value,
    required this.unit,
    required this.recordedBy,
    required this.sheetStatus,
    required this.isAnomaly,
    this.anomalyNote,
  });
  final String date;
  final String team;
  final String shift;
  final String section;
  final int round;
  final String time;
  final String side;
  final String unitStatus;
  final String equipment;
  final String point;
  final String value;
  final String unit;
  final String recordedBy;
  final String sheetStatus;
  final bool isAnomaly;
  final String? anomalyNote;

  /// CSV cannot retain cell colours, so this explicit label makes temperatures
  /// requiring attention obvious after the file is opened in Excel as well.
  double? get temperatureCelsius {
    final String normalizedUnit = unit.replaceAll('°', '').trim().toLowerCase();
    if (normalizedUnit != 'c') return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  bool get isCriticalTemperature =>
      (temperatureCelsius ?? -double.infinity) >= 70;

  bool get isHighTemperature => (temperatureCelsius ?? -double.infinity) >= 60;

  String get alertLabel {
    if (isCriticalTemperature) return 'CRITICAL >=70°C';
    if (isHighTemperature) return 'HIGH 60-69°C';
    if (isAnomaly) return 'REVIEW REQUIRED';
    return '';
  }
}

class ReportExportResult {
  const ReportExportResult({required this.sheetCount, required this.rows});
  final int sheetCount;
  final List<ReportRow> rows;
}

class ReportExportService {
  ReportExportService(this._client);
  final SupabaseClient _client;

  Future<List<JsonMap>> _fetchIn(
    String table,
    String fields,
    String column,
    List<String> values,
  ) async {
    if (values.isEmpty) return const <JsonMap>[];
    final List<JsonMap> collected = <JsonMap>[];
    const int pageSize = 1000;
    for (int offset = 0; ; offset += pageSize) {
      final Object response = await _client
          .from(table)
          .select(fields)
          .inFilter(column, values)
          .range(offset, offset + pageSize - 1);
      if (response is! List) throw FormatException('Invalid $table response.');
      final List<JsonMap> page = response
          .map((Object? row) => requireJsonMap(row, source: table))
          .toList(growable: false);
      collected.addAll(page);
      if (page.length < pageSize) return collected;
    }
  }

  Future<ReportExportResult> load({
    DateTime? from,
    DateTime? to,
    String? teamId,
    String? sheetId,
  }) async {
    Object response;
    if (sheetId != null) {
      response = await _client
          .from('sheet')
          .select('id,tanggal,status,team:team_id(name),shift:shift_id(name)')
          .eq('id', sheetId);
    } else if (from == null || to == null) {
      throw ArgumentError('A date range or sheet ID is required.');
    } else if (teamId == null) {
      response = await _client
          .from('sheet')
          .select('id,tanggal,status,team:team_id(name),shift:shift_id(name)')
          .gte('tanggal', _date(from))
          .lte('tanggal', _date(to));
    } else {
      response = await _client
          .from('sheet')
          .select('id,tanggal,status,team:team_id(name),shift:shift_id(name)')
          .eq('team_id', teamId)
          .gte('tanggal', _date(from))
          .lte('tanggal', _date(to));
    }
    if (response is! List) {
      throw const FormatException('Invalid sheet response.');
    }
    final List<JsonMap> sheets = response
        .map((Object? row) => requireJsonMap(row, source: 'sheet'))
        .toList(growable: false);
    if (sheets.isEmpty) {
      return const ReportExportResult(sheetCount: 0, rows: <ReportRow>[]);
    }
    final Map<String, JsonMap> sheetById = <String, JsonMap>{
      for (final JsonMap sheet in sheets) sheet.requiredString('id'): sheet,
    };
    final List<JsonMap> rounds = await _fetchIn(
      'round',
      'id,sheet_id,section,round_number,jam',
      'sheet_id',
      sheetById.keys.toList(growable: false),
    );
    final Map<String, JsonMap> roundById = <String, JsonMap>{
      for (final JsonMap row in rounds) row.requiredString('id'): row,
    };
    final List<JsonMap> statuses = await _fetchIn(
      'unit_status',
      'id,round_id,unit_code,status',
      'round_id',
      roundById.keys.toList(growable: false),
    );
    final Map<String, JsonMap> statusById = <String, JsonMap>{
      for (final JsonMap row in statuses) row.requiredString('id'): row,
    };
    final List<JsonMap> readings = await _fetchIn(
      'reading',
      'round_id,unit_status_id,measurement_point_id,value_numeric,value_boolean,value_text,recorded_by,is_anomaly,anomaly_note',
      'round_id',
      roundById.keys.toList(growable: false),
    );
    final List<JsonMap> points = await _fetchIn(
      'measurement_point',
      'id,label,unit,equipment_id',
      'id',
      readings
          .map((JsonMap row) => row.requiredString('measurement_point_id'))
          .toSet()
          .toList(growable: false),
    );
    final Map<String, JsonMap> pointById = <String, JsonMap>{
      for (final JsonMap row in points) row.requiredString('id'): row,
    };
    final List<String> equipmentIds = points
        .map((JsonMap row) => row.optionalString('equipment_id'))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final List<JsonMap> equipment = await _fetchIn(
      'equipment',
      'id,name',
      'id',
      equipmentIds,
    );
    final Map<String, String> equipmentById = <String, String>{
      for (final JsonMap row in equipment)
        row.requiredString('id'): row.requiredString('name'),
    };
    final List<String> userIds = readings
        .map((JsonMap row) => row.optionalString('recorded_by'))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final List<JsonMap> users = await _fetchIn(
      'app_user',
      'id,name',
      'id',
      userIds,
    );
    final Map<String, String> userById = <String, String>{
      for (final JsonMap row in users)
        row.requiredString('id'): row.requiredString('name'),
    };
    final List<ReportRow> rows = <ReportRow>[];
    for (final JsonMap reading in readings) {
      final JsonMap? round = roundById[reading.requiredString('round_id')];
      if (round == null) continue;
      final JsonMap? sheet = sheetById[round.requiredString('sheet_id')];
      if (sheet == null) continue;
      final JsonMap? point =
          pointById[reading.requiredString('measurement_point_id')];
      if (point == null) continue;
      final String? statusId = reading.optionalString('unit_status_id');
      final JsonMap? status = statusId == null ? null : statusById[statusId];
      final Object? rawTeam = sheet['team'];
      final Object? rawShift = sheet['shift'];
      final JsonMap? team = rawTeam == null
          ? null
          : requireJsonMap(rawTeam, source: 'sheet team');
      final JsonMap? shift = rawShift == null
          ? null
          : requireJsonMap(rawShift, source: 'sheet shift');
      rows.add(
        ReportRow(
          date: sheet.requiredString('tanggal'),
          team: team?.optionalString('name') ?? 'Unassigned',
          shift: displayShiftName(shift?.optionalString('name') ?? '—'),
          section: _section(round.requiredString('section')),
          round: round.requiredInt('round_number'),
          time: _time(round.optionalString('jam')),
          side: _side(status?.optionalString('unit_code')),
          unitStatus: status?.optionalString('status') ?? '',
          equipment: equipmentById[point.optionalString('equipment_id')] ?? '',
          point: point.requiredString('label'),
          value: _value(reading),
          unit: point.optionalString('unit') ?? '',
          recordedBy: userById[reading.optionalString('recorded_by')] ?? '—',
          sheetStatus: sheet.requiredString('status'),
          isAnomaly:
              reading['is_anomaly'] == true || reading['is_anomaly'] == 1,
          anomalyNote: reading.optionalString('anomaly_note'),
        ),
      );
    }
    // Status sisi tidak selalu mempunyai baris reading (mis. Not operating).
    // Masukkan sebagai baris export tersendiri agar PDF tetap menunjukkan
    // kondisi unit untuk Round 1 dan Round 2, bukan diam-diam menghilang.
    for (final JsonMap status in statuses) {
      final JsonMap? round = roundById[status.requiredString('round_id')];
      if (round == null) continue;
      final JsonMap? sheet = sheetById[round.requiredString('sheet_id')];
      if (sheet == null) continue;
      final Object? rawTeam = sheet['team'];
      final Object? rawShift = sheet['shift'];
      final JsonMap? team = rawTeam == null
          ? null
          : requireJsonMap(rawTeam, source: 'sheet team');
      final JsonMap? shift = rawShift == null
          ? null
          : requireJsonMap(rawShift, source: 'sheet shift');
      rows.add(
        ReportRow(
          date: sheet.requiredString('tanggal'),
          team: team?.optionalString('name') ?? 'Unassigned',
          shift: displayShiftName(shift?.optionalString('name') ?? '—'),
          section: _section(round.requiredString('section')),
          round: round.requiredInt('round_number'),
          time: _time(round.optionalString('jam')),
          side: _side(status.optionalString('unit_code')),
          unitStatus: status.optionalString('status') ?? '',
          equipment: '',
          point: 'Status',
          value: _status(status.optionalString('status')),
          unit: '',
          recordedBy: '',
          sheetStatus: sheet.requiredString('status'),
          isAnomaly: false,
        ),
      );
    }
    rows.sort((ReportRow left, ReportRow right) {
      final int dateCompare = left.date.compareTo(right.date);
      if (dateCompare != 0) return dateCompare;
      final int sectionCompare = left.section.compareTo(right.section);
      return sectionCompare != 0
          ? sectionCompare
          : left.round.compareTo(right.round);
    });
    return ReportExportResult(sheetCount: sheets.length, rows: rows);
  }

  String toCsv(ReportExportResult result) {
    final List<List<String>> data = <List<String>>[
      <String>[
        'Date',
        'Team',
        'Shift',
        'Section',
        'Round',
        'Time',
        'Side',
        'Unit Status',
        'Equipment',
        'Measurement Point',
        'Value',
        'Unit',
        'Recorded By',
        'Sheet Status',
        'Temperature Alert',
        'Anomaly',
        'Anomaly Note',
      ],
      ...result.rows.map(
        (ReportRow row) => <String>[
          row.date,
          row.team,
          row.shift,
          row.section,
          row.round.toString(),
          row.time,
          row.side,
          row.unitStatus,
          row.equipment,
          row.point,
          row.value,
          row.unit,
          row.recordedBy,
          row.sheetStatus,
          row.alertLabel,
          row.isAnomaly ? 'Yes' : '',
          row.anomalyNote ?? '',
        ],
      ),
    ];
    return data
        .map((List<String> row) => row.map(_escapeCsv).join(','))
        .join('\n');
  }

  String _escapeCsv(String value) {
    if (!RegExp(r'[,"\n\r]').hasMatch(value)) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String _time(String? value) => value == null
      ? ''
      : value.length >= 16 && value.contains('T')
      ? value.substring(11, 16)
      : value.length >= 5
      ? value.substring(0, 5)
      : value;
  String _section(String value) => value == 'gearbox_breaker'
      ? 'Gearbox Breaker'
      : value == 'gearbox_sizer'
      ? 'Gearbox Sizer'
      : value;
  String _side(String? value) => value == 'BARAT'
      ? 'West'
      : value == 'TIMUR'
      ? 'East'
      : value ?? '';
  String _status(String? value) => value == 'beroperasi'
      ? 'Operating'
      : value == 'tidak_beroperasi'
      ? 'Not operating'
      : value == 'tidak_dapat_diakses'
      ? 'Not accessible'
      : value ?? '';
  String _value(JsonMap row) {
    final Object? numeric = row['value_numeric'];
    if (numeric is num) return numeric.toString();
    final Object? boolean = row['value_boolean'];
    if (boolean is bool) return boolean ? 'OK' : 'Low';
    return row.optionalString('value_text') ?? '';
  }
}
