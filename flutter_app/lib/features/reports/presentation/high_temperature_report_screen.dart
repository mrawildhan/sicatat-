import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _TeamOption {
  const _TeamOption({required this.id, required this.name});
  final String id;
  final String name;
  factory _TeamOption.fromJson(JsonMap json) => _TeamOption(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class _HighTemperatureRow {
  const _HighTemperatureRow({
    required this.date,
    required this.team,
    required this.shift,
    required this.section,
    required this.round,
    required this.side,
    required this.point,
    required this.value,
    required this.unit,
    required this.recordedBy,
  });
  final String date;
  final String team;
  final String shift;
  final String section;
  final int round;
  final String side;
  final String point;
  final double value;
  final String unit;
  final String recordedBy;
}

class HighTemperatureReportScreen extends StatefulWidget {
  const HighTemperatureReportScreen({super.key});
  @override
  State<HighTemperatureReportScreen> createState() =>
      _HighTemperatureReportScreenState();
}

class _HighTemperatureReportScreenState
    extends State<HighTemperatureReportScreen> {
  late DateTime _from;
  late DateTime _to;
  List<_TeamOption> _teams = const <_TeamOption>[];
  String? _teamId;
  List<_HighTemperatureRow> _rows = const <_HighTemperatureRow>[];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final Object response = await Supabase.instance.client
          .from('team')
          .select('id,name')
          .order('code');
      if (response is! List) {
        throw const FormatException('Invalid team response.');
      }
      final List<_TeamOption> teams = response
          .map(
            (Object? row) =>
                _TeamOption.fromJson(requireJsonMap(row, source: 'team')),
          )
          .toList(growable: false);
      if (mounted) setState(() => _teams = teams);
    } on Object catch (_) {
      /* The report can still run for all teams. */
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  Future<void> _pick(bool isFrom) async {
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2040),
      initialDate: isFrom ? _from : _to,
    );
    if (date != null) {
      setState(() {
        if (isFrom) {
          _from = date;
        } else {
          _to = date;
        }
      });
    }
  }

  Future<List<JsonMap>> _fetchIn(
    String table,
    String fields,
    String key,
    List<String> values, {
    bool temperaturesOnly = false,
  }) async {
    if (values.isEmpty) return const <JsonMap>[];
    final List<JsonMap> collected = <JsonMap>[];
    const int pageSize = 1000;
    for (int offset = 0; ; offset += pageSize) {
      final Object response = temperaturesOnly
          ? await Supabase.instance.client
                .from(table)
                .select(fields)
                .inFilter(key, values)
                .gte('value_numeric', 60)
                .range(offset, offset + pageSize - 1)
          : await Supabase.instance.client
                .from(table)
                .select(fields)
                .inFilter(key, values)
                .range(offset, offset + pageSize - 1);
      if (response is! List) throw FormatException('Invalid $table response.');
      final List<JsonMap> page = response
          .map((Object? row) => requireJsonMap(row, source: table))
          .toList(growable: false);
      collected.addAll(page);
      if (page.length < pageSize) return collected;
    }
  }

  Future<void> _load() async {
    if (_from.isAfter(_to)) {
      setState(() => _error = 'Start date cannot be after end date.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _rows = const <_HighTemperatureRow>[];
    });
    try {
      Object sheetResponse;
      if (_teamId == null) {
        sheetResponse = await Supabase.instance.client
            .from('sheet')
            .select('id,tanggal,team:team_id(name),shift:shift_id(code)')
            .gte('tanggal', _date(_from))
            .lte('tanggal', _date(_to));
      } else {
        sheetResponse = await Supabase.instance.client
            .from('sheet')
            .select('id,tanggal,team:team_id(name),shift:shift_id(code)')
            .eq('team_id', _teamId!)
            .gte('tanggal', _date(_from))
            .lte('tanggal', _date(_to));
      }
      if (sheetResponse is! List) {
        throw const FormatException('Invalid sheet response.');
      }
      final List<JsonMap> sheets = sheetResponse
          .map((Object? row) => requireJsonMap(row, source: 'sheet'))
          .toList(growable: false);
      final Map<String, JsonMap> sheetById = <String, JsonMap>{
        for (final JsonMap sheet in sheets) sheet.requiredString('id'): sheet,
      };
      final List<JsonMap> rounds = await _fetchIn(
        'round',
        'id,sheet_id,section,round_number',
        'sheet_id',
        sheetById.keys.toList(growable: false),
      );
      final Map<String, JsonMap> roundById = <String, JsonMap>{
        for (final JsonMap round in rounds) round.requiredString('id'): round,
      };
      final List<JsonMap> units = await _fetchIn(
        'unit_status',
        'id,unit_code',
        'round_id',
        roundById.keys.toList(growable: false),
      );
      final Map<String, JsonMap> unitById = <String, JsonMap>{
        for (final JsonMap unit in units) unit.requiredString('id'): unit,
      };
      final List<JsonMap> readings = await _fetchIn(
        'reading',
        'round_id,unit_status_id,measurement_point_id,value_numeric,recorded_by',
        'round_id',
        roundById.keys.toList(growable: false),
        temperaturesOnly: true,
      );
      final List<String> pointIds = readings
          .map((JsonMap row) => row.requiredString('measurement_point_id'))
          .toSet()
          .toList(growable: false);
      final List<JsonMap> points = await _fetchIn(
        'measurement_point',
        'id,label,unit,equipment_id',
        'id',
        pointIds,
      );
      final Map<String, JsonMap> pointById = <String, JsonMap>{
        for (final JsonMap point in points) point.requiredString('id'): point,
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
      final Map<String, String> nameByUserId = <String, String>{
        for (final JsonMap user in users)
          user.requiredString('id'): user.requiredString('name'),
      };
      final List<_HighTemperatureRow> result = <_HighTemperatureRow>[];
      for (final JsonMap reading in readings) {
        final JsonMap? round = roundById[reading.requiredString('round_id')];
        if (round == null) continue;
        final JsonMap? sheet = sheetById[round.requiredString('sheet_id')];
        if (sheet == null) continue;
        final Object? rawTeam = sheet['team'];
        final Object? rawShift = sheet['shift'];
        final JsonMap? team = rawTeam == null
            ? null
            : requireJsonMap(rawTeam, source: 'team');
        final JsonMap? shift = rawShift == null
            ? null
            : requireJsonMap(rawShift, source: 'shift');
        final JsonMap? point =
            pointById[reading.requiredString('measurement_point_id')];
        final String? unitId = reading.optionalString('unit_status_id');
        final JsonMap? unit = unitId == null ? null : unitById[unitId];
        final Object? rawValue = reading['value_numeric'];
        if (rawValue is! num) continue;
        result.add(
          _HighTemperatureRow(
            date: sheet.requiredString('tanggal'),
            team: team?.optionalString('name') ?? 'Unassigned',
            shift: shift?.optionalString('code') ?? '—',
            section: _section(round.requiredString('section')),
            round: round.requiredInt('round_number'),
            side: _side(unit?.optionalString('unit_code')),
            point: point?.optionalString('label') ?? 'Unknown point',
            value: rawValue.toDouble(),
            unit: point?.optionalString('unit') ?? '°C',
            recordedBy:
                nameByUserId[reading.optionalString('recorded_by')] ?? '—',
          ),
        );
      }
      result.sort((left, right) {
        final int dateCompare = right.date.compareTo(left.date);
        return dateCompare == 0
            ? right.value.compareTo(left.value)
            : dateCompare;
      });
      if (mounted) setState(() => _rows = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _section(String value) => value == 'gearbox_breaker'
      ? 'Gearbox Breaker'
      : value == 'gearbox_sizer'
      ? 'Gearbox Sizer'
      : value;
  String _side(String? value) => value == 'BARAT'
      ? 'West'
      : value == 'TIMUR'
      ? 'East'
      : value ?? '—';

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/dashboard',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/dashboard'),
        title: const Text('High temperature report'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'All temperature readings at or above 60°C, across synced sheets.',
          ),
          const SizedBox(height: 16),
          _dateTile('From', _from, () => _pick(true)),
          const SizedBox(height: 10),
          _dateTile('To', _to, () => _pick(false)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('high-temperature-team'),
            initialValue: _teamId,
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All teams'),
              ),
              ..._teams.map(
                (team) => DropdownMenuItem<String>(
                  value: team.id,
                  child: Text(team.name),
                ),
              ),
            ],
            onChanged: (String? value) => setState(() => _teamId = value),
            decoration: const InputDecoration(labelText: 'Team'),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.thermostat_rounded),
            label: Text(_loading ? 'Loading...' : 'Load report'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('Unable to load report: $_error'),
            ),
          if (!_loading && _error == null && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                '${_rows.length} reading(s) found.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ..._rows.map(_rowTile),
        ],
      ),
    ),
  );

  Widget _dateTile(String title, DateTime date, VoidCallback onTap) => Card(
    child: ListTile(
      onTap: onTap,
      leading: const Icon(Icons.calendar_month_rounded, color: AppColors.green),
      title: Text(title),
      subtitle: Text(_date(date)),
    ),
  );
  Widget _rowTile(_HighTemperatureRow row) {
    final bool critical = row.value >= 70;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: Icon(
            Icons.thermostat_rounded,
            color: critical ? AppColors.danger : AppColors.warning,
          ),
          title: Text(
            '${row.value.toStringAsFixed(1)}${row.unit}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: critical ? AppColors.danger : AppColors.warning,
            ),
          ),
          subtitle: Text(
            '${row.date} · ${row.team} · ${row.shift}\n${row.section}, Round ${row.round} · ${row.side} · ${row.point}\nRecorded by ${row.recordedBy}',
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}
