import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

/// Temperature of one measurement point over time, so a slow rise is seen
/// before it becomes a breakdown. Covers all three Suhu sheets.
class TemperatureTrendScreen extends StatefulWidget {
  const TemperatureTrendScreen({super.key});

  @override
  State<TemperatureTrendScreen> createState() => _TemperatureTrendScreenState();
}

/// null = Daily Temperature Feeder Sizer.
typedef _Source = DailyCheckFormType?;

class _FeederPoint {
  const _FeederPoint(this.id, this.label);

  final String id;
  final String label;
}

class _Series {
  const _Series(this.label, this.color, this.points);

  final String label;
  final Color color;
  final List<(DateTime, double)> points;
}

class _TemperatureTrendScreenState extends State<TemperatureTrendScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  _Source _source = DailyCheckFormType.hydraulicFeeder;
  List<_FeederPoint> _feederPoints = const <_FeederPoint>[];
  String? _feederPointId;
  String _fieldKey = 'main_pump';
  String? _unitKey;
  int _days = 30;
  List<_Series> _series = const <_Series>[];
  bool _loading = false;
  String? _error;

  static const List<Color> _palette = <Color>[
    AppColors.green,
    Color(0xFF2F6FB0),
    Color(0xFF8A4FB3),
    Color(0xFFB36B00),
  ];

  @override
  void initState() {
    super.initState();
    _unitKey = DailyCheckFormType.hydraulicFeeder.form.units.first.key;
    _init();
  }

  Future<void> _init() async {
    await _repository.loadThresholds();
    try {
      final Object rows = await Supabase.instance.client
          .from('measurement_point')
          .select(
            'id,label,unit,data_type,sort_order,equipment:equipment_id(name)',
          )
          .eq('is_active', true)
          .eq('data_type', 'numeric')
          .order('sort_order', ascending: true);
      if (rows is List) {
        _feederPoints = rows
            .map((raw) {
              final row = requireJsonMap(raw, source: 'measurement point');
              final equipment = row['equipment'];
              final equipmentName = equipment is Map
                  ? equipment['name']?.toString()
                  : null;
              return _FeederPoint(
                row.requiredString('id'),
                equipmentName == null
                    ? row.requiredString('label')
                    : '$equipmentName · ${row.requiredString('label')}',
              );
            })
            .toList(growable: false);
        _feederPointId = _feederPoints.firstOrNull?.id;
      }
    } on Object {
      // The Feeder Sizer option simply stays empty.
    }
    await _load();
  }

  List<DailyCheckField> _temperatureFields(DailyCheckFormType type) => type
      .form
      .fields
      .where((field) => field.kind == DailyCheckValueKind.temperature)
      .toList(growable: false);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final since = DateTime.now().subtract(Duration(days: _days));
    try {
      final type = _source;
      final series = type == null
          ? await _feederSeries(since)
          : await _dailySeries(type, since);
      if (mounted) setState(() => _series = series);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Data tidak dapat dimuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_Series>> _dailySeries(
    DailyCheckFormType type,
    DateTime since,
  ) async {
    final sheets = (await _repository.listSince(since))
        .where((sheet) => sheet.type == type)
        .toList(growable: false);
    final form = type.form;
    final units = _unitKey == null
        ? form.units
        : form.units.where((unit) => unit.key == _unitKey).toList();
    final field = form.fields.firstWhere((f) => f.key == _fieldKey);
    return <_Series>[
      for (var i = 0; i < units.length; i++)
        _Series(
          units[i].label,
          _palette[i % _palette.length],
          <(DateTime, double)>[
            for (final sheet in sheets)
              for (final slot in sheet.slots)
                if (sheet.readings[slot.key]?[DailyCheckForm.valueKey(
                      units[i],
                      field,
                    )]
                    case final num value)
                  (_slotTime(sheet, slot), value.toDouble()),
          ]..sort((a, b) => a.$1.compareTo(b.$1)),
        ),
    ];
  }

  DateTime _slotTime(DailyCheckSheet sheet, DailyCheckSlot slot) {
    final recorded = sheet.readings[slot.key]?[DailyCheckForm.recordedAtKey];
    final at = recorded is String
        ? DateTime.tryParse(recorded)?.toLocal()
        : null;
    return at ?? sheet.date;
  }

  Future<List<_Series>> _feederSeries(DateTime since) async {
    final pointId = _feederPointId;
    if (pointId == null) return const <_Series>[];
    final Object rows = await Supabase.instance.client
        .from('reading')
        .select(
          'value_numeric,measured_at,unit_status:unit_status_id(unit_code)',
        )
        .eq('measurement_point_id', pointId)
        .gte('measured_at', since.toUtc().toIso8601String())
        .order('measured_at', ascending: true)
        .limit(3000);
    if (rows is! List) return const <_Series>[];
    final bySide = <String, List<(DateTime, double)>>{};
    for (final raw in rows) {
      final row = requireJsonMap(raw, source: 'reading');
      final value = row['value_numeric'];
      if (value is! num) continue;
      final status = row['unit_status'];
      final side = switch (status is Map ? status['unit_code'] : null) {
        'BARAT' => 'Barat',
        'TIMUR' => 'Timur',
        _ => 'Unit',
      };
      (bySide[side] ??= <(DateTime, double)>[]).add((
        DateTime.parse(row.requiredString('measured_at')).toLocal(),
        value.toDouble(),
      ));
    }
    var i = 0;
    return <_Series>[
      for (final entry in bySide.entries)
        _Series(entry.key, _palette[i++ % _palette.length], entry.value),
    ];
  }

  DailyCheckLimits get _limits {
    final type = _source;
    return type == null
        ? DailyCheckLimits.standard
        : DailyCheckThresholds.of(type, _fieldKey);
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/temperature-forms',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/temperature-forms'),
        title: const Text('Tren suhu'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          _controls(),
          const SizedBox(height: 16),
          if (_error case final error?)
            DailyCheckNotice(error, error: true)
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_series.every((series) => series.points.isEmpty))
            const DailyCheckNotice(
              'Belum ada pembacaan untuk titik ini pada periode yang dipilih.',
            )
          else ...<Widget>[
            _chart(),
            const SizedBox(height: 16),
            ..._series.where((s) => s.points.isNotEmpty).map(_stats),
          ],
        ],
      ),
    ),
  );

  Widget _controls() {
    final type = _source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: type?.storageValue ?? 'feeder_sizer',
          decoration: const InputDecoration(labelText: 'Lembar'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: 'feeder_sizer',
              child: Text('Daily Temperature Feeder Sizer'),
            ),
            for (final option in DailyCheckFormType.values)
              DropdownMenuItem<String>(
                value: option.storageValue,
                child: Text(option.form.title),
              ),
          ],
          onChanged: (value) {
            final next = DailyCheckFormType.fromStorage(value);
            setState(() {
              _source = next;
              if (next != null) {
                _fieldKey = _temperatureFields(next).first.key;
                _unitKey = next.form.units.first.key;
              }
            });
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (type == null)
          DropdownButtonFormField<String>(
            key: ValueKey<String?>('feeder-$_feederPointId'),
            initialValue: _feederPointId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Titik ukur'),
            items: <DropdownMenuItem<String>>[
              for (final point in _feederPoints)
                DropdownMenuItem<String>(
                  value: point.id,
                  child: Text(point.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              setState(() => _feederPointId = value);
              _load();
            },
          )
        else ...<Widget>[
          DropdownButtonFormField<String>(
            key: ValueKey<String>('field-${type.storageValue}-$_fieldKey'),
            initialValue: _fieldKey,
            decoration: const InputDecoration(labelText: 'Titik ukur'),
            items: <DropdownMenuItem<String>>[
              for (final field in _temperatureFields(type))
                DropdownMenuItem<String>(
                  value: field.key,
                  child: Text(field.label),
                ),
            ],
            onChanged: (value) {
              setState(() => _fieldKey = value ?? _fieldKey);
              _load();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey<String>('unit-${type.storageValue}-$_unitKey'),
            initialValue: _unitKey,
            decoration: InputDecoration(
              labelText: type == DailyCheckFormType.hydraulicFeeder
                  ? 'Feeder'
                  : 'Sisi',
            ),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Semua (dibandingkan)'),
              ),
              for (final unit in type.form.units)
                DropdownMenuItem<String?>(
                  value: unit.key,
                  child: Text(unit.label),
                ),
            ],
            onChanged: (value) {
              setState(() => _unitKey = value);
              _load();
            },
          ),
        ],
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 7, label: Text('7 hari')),
            ButtonSegment<int>(value: 30, label: Text('30 hari')),
            ButtonSegment<int>(value: 90, label: Text('90 hari')),
          ],
          selected: <int>{_days},
          onSelectionChanged: (value) {
            setState(() => _days = value.first);
            _load();
          },
        ),
      ],
    );
  }

  Widget _chart() {
    final all = _series.expand((s) => s.points).toList();
    final limits = _limits;
    final minX = all.map((p) => p.$1.millisecondsSinceEpoch).reduce(math.min);
    final maxX = all.map((p) => p.$1.millisecondsSinceEpoch).reduce(math.max);
    final values = all.map((p) => p.$2);
    final minY = math.min(values.reduce(math.min), limits.warning) - 5;
    final maxY = math.max(values.reduce(math.max), limits.critical) + 5;
    final spanX = math.max(maxX - minX, 3600000).toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minX: minX.toDouble(),
                  maxX: minX + spanX,
                  minY: minY.floorToDouble(),
                  maxY: maxY.ceilToDouble(),
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: <HorizontalLine>[
                      HorizontalLine(
                        y: limits.warning,
                        color: AppColors.warning,
                        strokeWidth: 1.5,
                        dashArray: <int>[6, 4],
                      ),
                      HorizontalLine(
                        y: limits.critical,
                        color: AppColors.danger,
                        strokeWidth: 1.5,
                        dashArray: <int>[6, 4],
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: spanX / 4,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            // Within two days the date repeats; show the hour.
                            DateFormat(spanX < 2 * 86400000 ? 'HH:mm' : 'dd/MM')
                                .format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    value.toInt(),
                                  ),
                                ),
                            style: AppTextStyles.badge,
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => <LineTooltipItem?>[
                        for (final spot in spots)
                          LineTooltipItem(
                            '${formatReading(spot.y)} °C\n'
                            '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()))}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: <LineChartBarData>[
                    for (final series in _series)
                      if (series.points.isNotEmpty)
                        LineChartBarData(
                          spots: <FlSpot>[
                            for (final point in series.points)
                              FlSpot(
                                point.$1.millisecondsSinceEpoch.toDouble(),
                                point.$2,
                              ),
                          ],
                          color: series.color,
                          barWidth: 2.5,
                          dotData: FlDotData(show: series.points.length <= 40),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: <Widget>[
                for (final series in _series)
                  if (series.points.isNotEmpty)
                    _legend(series.color, series.label),
                _legend(
                  AppColors.warning,
                  'Waspada ${formatReading(limits.warning)} °C',
                ),
                _legend(
                  AppColors.danger,
                  'Kritis ${formatReading(limits.critical)} °C',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 12, height: 4, color: color),
      const SizedBox(width: 6),
      Text(label, style: AppTextStyles.badge),
    ],
  );

  Widget _stats(_Series series) {
    final values = series.points.map((p) => p.$2).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final last = series.points.last;
    String fmt(double v) => formatReading(double.parse(v.toStringAsFixed(1)));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(radius: 6, backgroundColor: series.color),
        title: Text(
          series.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${values.length} pembacaan · rata-rata ${fmt(average)} °C · '
          'min ${fmt(values.reduce(math.min))} · maks ${fmt(values.reduce(math.max))}\n'
          'Terakhir ${fmt(last.$2)} °C pada ${DateFormat('dd MMM yyyy, HH:mm').format(last.$1)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
