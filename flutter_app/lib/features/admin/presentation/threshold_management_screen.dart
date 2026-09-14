import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _PointOption {
  const _PointOption({
    required this.id,
    required this.label,
    required this.unit,
    this.equipmentName,
    this.section = '',
    this.equipmentOrder = 0,
    this.pointOrder = 0,
  });
  final String id;
  final String label;
  final String unit;
  final String? equipmentName;
  final String section;
  final int equipmentOrder;
  final int pointOrder;
  factory _PointOption.fromJson(JsonMap json) {
    final Object? rawEquipment = json['equipment'];
    final JsonMap? equipment = rawEquipment == null
        ? null
        : requireJsonMap(rawEquipment, source: 'point equipment');
    int order(Object? value) => value is num ? value.toInt() : 0;
    return _PointOption(
      id: json.requiredString('id'),
      label: json.requiredString('label'),
      unit: json.optionalString('unit') ?? '',
      equipmentName: equipment?.optionalString('name'),
      section: equipment?.optionalString('section') ?? '',
      equipmentOrder: order(equipment?['sort_order']),
      pointOrder: order(json['sort_order']),
    );
  }
  String get display =>
      '${equipmentName ?? 'Gearbox bersama'} · $label${unit.isEmpty ? '' : ' ($unit)'}';

  /// Same order as the crew form: equipment by section and sort order, each
  /// equipment's points by sort order, shared gearbox points last.
  static int compare(_PointOption a, _PointOption b) {
    final int shared = (a.equipmentName == null ? 1 : 0).compareTo(
      b.equipmentName == null ? 1 : 0,
    );
    if (shared != 0) return shared;
    final int section = a.section.compareTo(b.section);
    if (section != 0) return section;
    final int equipment = a.equipmentOrder.compareTo(b.equipmentOrder);
    if (equipment != 0) return equipment;
    final int name = (a.equipmentName ?? '').compareTo(b.equipmentName ?? '');
    if (name != 0) return name;
    final int point = a.pointOrder.compareTo(b.pointOrder);
    return point != 0 ? point : a.label.compareTo(b.label);
  }
}

class _Threshold {
  const _Threshold({
    required this.id,
    required this.pointId,
    required this.pointName,
    this.equipmentName,
    required this.isActive,
    required this.sourceNote,
    this.warningMin,
    this.warningMax,
    this.alarmMin,
    this.alarmMax,
    this.delta,
  });
  final String id;
  final String pointId;
  final String pointName;
  final String? equipmentName;
  final bool isActive;
  final String sourceNote;
  final double? warningMin;
  final double? warningMax;
  final double? alarmMin;
  final double? alarmMax;
  final double? delta;
  String get pointDisplay =>
      equipmentName == null ? pointName : '$equipmentName · $pointName';
  factory _Threshold.fromJson(JsonMap json) {
    final JsonMap point = requireJsonMap(
      json['measurement_point'],
      source: 'threshold point',
    );
    double? number(String key) {
      final Object? value = json[key];
      return value is num ? value.toDouble() : null;
    }

    return _Threshold(
      id: json.requiredString('id'),
      pointId: json.requiredString('measurement_point_id'),
      pointName: point.requiredString('label'),
      equipmentName: point['equipment'] == null
          ? null
          : requireJsonMap(
              point['equipment'],
              source: 'threshold equipment',
            ).optionalString('name'),
      isActive: json.requiredBool('is_active'),
      sourceNote: json.optionalString('source_note') ?? '',
      warningMin: number('warning_min'),
      warningMax: number('warning_max'),
      alarmMin: number('alarm_min'),
      alarmMax: number('alarm_max'),
      delta: number('delta_max_per_round'),
    );
  }
}

class ThresholdManagementScreen extends StatefulWidget {
  const ThresholdManagementScreen({super.key});
  @override
  State<ThresholdManagementScreen> createState() =>
      _ThresholdManagementScreenState();
}

class _ThresholdManagementScreenState extends State<ThresholdManagementScreen> {
  List<_PointOption> _points = const <_PointOption>[];
  List<_Threshold> _items = const <_Threshold>[];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _notice(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        Supabase.instance.client
            .from('measurement_point')
            .select(
              'id,label,unit,sort_order,equipment:equipment_id(name,section,sort_order)',
            )
            .eq('is_active', true)
            .eq('data_type', 'numeric'),
        Supabase.instance.client
            .from('threshold')
            .select(
              'id,measurement_point_id,warning_min,warning_max,alarm_min,alarm_max,delta_max_per_round,is_active,source_note,measurement_point:measurement_point_id(label,equipment:equipment_id(name))',
            )
            .order('effective_from', ascending: false),
      ]);
      if (results[0] is! List || results[1] is! List) {
        throw const FormatException('Respons batas suhu tidak valid.');
      }
      final List<_PointOption> points =
          (results[0] as List<Object?>)
              .map(
                (Object? row) => _PointOption.fromJson(
                  requireJsonMap(row, source: 'measurement point'),
                ),
              )
              .toList()
            ..sort(_PointOption.compare);
      final List<_Threshold> items = (results[1] as List<Object?>)
          .map(
            (Object? row) =>
                _Threshold.fromJson(requireJsonMap(row, source: 'threshold')),
          )
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _points = points;
          _items = items;
        });
      }
    } on Object catch (error) {
      if (mounted) _notice('Batas suhu tidak dapat dimuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(double? value) =>
      value == null ? '' : formatThresholdNumber(value);
  Future<void> _edit(_Threshold? item) async {
    final List<_PointOption> options = <_PointOption>[
      ..._points,
      if (item != null && !_points.any((point) => point.id == item.pointId))
        _PointOption(
          id: item.pointId,
          label: item.pointName,
          unit: '',
          equipmentName: item.equipmentName,
        ),
    ];
    if (options.isEmpty) {
      _notice('Tambahkan titik ukur suhu yang aktif terlebih dahulu.');
      return;
    }
    String pointId = item?.pointId ?? options.first.id;
    bool active = item?.isActive ?? true;
    String? problem;
    final TextEditingController warningMin = TextEditingController(
      text: _value(item?.warningMin),
    );
    final TextEditingController warningMax = TextEditingController(
      text: _value(item?.warningMax),
    );
    final TextEditingController alarmMin = TextEditingController(
      text: _value(item?.alarmMin),
    );
    final TextEditingController alarmMax = TextEditingController(
      text: _value(item?.alarmMax),
    );
    final TextEditingController delta = TextEditingController(
      text: _value(item?.delta),
    );
    final TextEditingController source = TextEditingController(
      text: item?.sourceNote ?? '',
    );
    final Map<String, Object?>? payload =
        await showDialog<Map<String, Object?>>(
          context: context,
          builder: (BuildContext dialogContext) => StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setModalState,
                ) => AlertDialog(
                  title: Text(
                    item == null ? 'Tambah batas suhu' : 'Ubah batas suhu',
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        DropdownButtonFormField<String>(
                          initialValue: pointId,
                          isExpanded: true,
                          items: options
                              .map(
                                (point) => DropdownMenuItem<String>(
                                  value: point.id,
                                  child: Text(
                                    point.display,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (String? value) =>
                              setModalState(() => pointId = value ?? pointId),
                          decoration: const InputDecoration(
                            labelText: 'Titik ukur',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _numberField(warningMin, 'Warning minimum (°C)'),
                        const SizedBox(height: 10),
                        _numberField(warningMax, 'Warning maximum (°C)'),
                        const SizedBox(height: 10),
                        _numberField(alarmMin, 'Alarm minimum (°C)'),
                        const SizedBox(height: 10),
                        _numberField(alarmMax, 'Alarm maximum (°C)'),
                        const SizedBox(height: 10),
                        _numberField(delta, 'Perubahan maksimum antar ronde'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: source,
                          decoration: const InputDecoration(
                            labelText: 'Sumber / referensi engineering *',
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: active,
                          onChanged: (bool value) =>
                              setModalState(() => active = value),
                          title: const Text('Aktif'),
                        ),
                        Text(
                          'Batas yang dikosongkan memakai bawaan: warning 60°C, alarm 70°C.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        if (problem case final String message) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            message,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final result = validateThresholdInput(
                          pointId: pointId,
                          warningMin: warningMin.text,
                          warningMax: warningMax.text,
                          alarmMin: alarmMin.text,
                          alarmMax: alarmMax.text,
                          delta: delta.text,
                          sourceNote: source.text,
                          isActive: active,
                        );
                        if (result.payload
                            case final Map<String, Object?> valid) {
                          Navigator.pop(dialogContext, valid);
                        } else {
                          setModalState(() => problem = result.error);
                        }
                      },
                      child: const Text('Simpan'),
                    ),
                  ],
                ),
          ),
        );
    _dispose(<TextEditingController>[
      warningMin,
      warningMax,
      alarmMin,
      alarmMax,
      delta,
      source,
    ]);
    if (payload == null) return;
    try {
      if (item == null) {
        await Supabase.instance.client.from('threshold').insert(payload);
      } else {
        await Supabase.instance.client
            .from('threshold')
            .update(payload)
            .eq('id', item.id);
      }
      if (mounted) {
        _notice('Batas suhu tersimpan.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Batas suhu tidak dapat disimpan: $error');
    }
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*')),
        ],
        decoration: InputDecoration(labelText: label),
      );
  void _dispose(List<TextEditingController> controllers) {
    for (final TextEditingController controller in controllers) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Batas suhu'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Tambah batas suhu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 120),
                      children: <Widget>[
                        Icon(
                          Icons.thermostat_auto_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Belum ada batas suhu khusus',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tekan Tambah batas suhu untuk menambahkan batas peringatan dan alarm per titik ukur.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, int index) {
                        final _Threshold item = _items[index];
                        return Card(
                          child: ListTile(
                            onTap: () => _edit(item),
                            title: Text(
                              item.pointDisplay,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              'Warning ${_value(item.warningMin)}-${_value(item.warningMax)} · Alarm ${_value(item.alarmMin)}-${_value(item.alarmMax)}${item.delta == null ? '' : ' · Δ ${_value(item.delta)}'}',
                            ),
                            trailing: Chip(
                              label: Text(
                                item.isActive ? 'Aktif' : 'Tidak aktif',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    ),
  );
}

/// Formats a threshold for display without a trailing ".0".
String formatThresholdNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// Parses and checks the threshold dialog before anything is sent, so a wrong
/// value keeps the dialog open instead of silently saving an empty limit.
@visibleForTesting
({Map<String, Object?>? payload, String? error}) validateThresholdInput({
  required String pointId,
  required String warningMin,
  required String warningMax,
  required String alarmMin,
  required String alarmMax,
  required String delta,
  required String sourceNote,
  required bool isActive,
}) {
  ({Map<String, Object?>? payload, String? error}) fail(String message) =>
      (payload: null, error: message);
  const Map<String, String> labels = <String, String>{
    'warning_min': 'Warning minimum',
    'warning_max': 'Warning maximum',
    'alarm_min': 'Alarm minimum',
    'alarm_max': 'Alarm maximum',
    'delta_max_per_round': 'Perubahan maksimum antar ronde',
  };
  final Map<String, String> raw = <String, String>{
    'warning_min': warningMin,
    'warning_max': warningMax,
    'alarm_min': alarmMin,
    'alarm_max': alarmMax,
    'delta_max_per_round': delta,
  };
  final Map<String, double?> values = <String, double?>{};
  for (final MapEntry<String, String> entry in raw.entries) {
    final String text = entry.value.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      values[entry.key] = null;
      continue;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) {
      return fail('${labels[entry.key]} harus berupa angka.');
    }
    values[entry.key] = parsed;
  }
  final double? wMin = values['warning_min'];
  final double? wMax = values['warning_max'];
  final double? aMin = values['alarm_min'];
  final double? aMax = values['alarm_max'];
  final double? maxDelta = values['delta_max_per_round'];
  if (wMin == null && wMax == null && aMin == null && aMax == null) {
    return fail('Isi minimal satu batas warning atau alarm.');
  }
  if (wMin != null && wMax != null && wMin > wMax) {
    return fail(
      'Warning minimum tidak boleh lebih besar dari warning maximum.',
    );
  }
  if (aMin != null && aMax != null && aMin > aMax) {
    return fail('Alarm minimum tidak boleh lebih besar dari alarm maximum.');
  }
  // Mirrors assessTemperature: the minimum wins, the maximum is a
  // fallback, and an empty pair falls back to the 60/70°C defaults.
  final double warningAt = wMin ?? wMax ?? 60;
  final double alarmAt = aMin ?? aMax ?? 70;
  if (warningAt >= alarmAt) {
    return fail(
      'Batas warning (${formatThresholdNumber(warningAt)}°C) harus lebih rendah dari batas alarm (${formatThresholdNumber(alarmAt)}°C).',
    );
  }
  if (maxDelta != null && maxDelta <= 0) {
    return fail('Perubahan maksimum antar ronde harus lebih dari 0.');
  }
  final String note = sourceNote.trim();
  if (note.isEmpty) {
    return fail('Sumber atau referensi engineering wajib diisi.');
  }
  return (
    payload: <String, Object?>{
      'measurement_point_id': pointId,
      'warning_min': wMin,
      'warning_max': wMax,
      'alarm_min': aMin,
      'alarm_max': aMax,
      'delta_max_per_round': maxDelta,
      'source_note': note,
      'is_active': isActive,
    },
    error: null,
  );
}
