import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _PointOption {
  const _PointOption({
    required this.id,
    required this.label,
    required this.unit,
    this.equipmentName,
  });
  final String id;
  final String label;
  final String unit;
  final String? equipmentName;
  factory _PointOption.fromJson(JsonMap json) {
    final Object? rawEquipment = json['equipment'];
    final JsonMap? equipment = rawEquipment == null
        ? null
        : requireJsonMap(rawEquipment, source: 'point equipment');
    return _PointOption(
      id: json.requiredString('id'),
      label: json.requiredString('label'),
      unit: json.optionalString('unit') ?? '',
      equipmentName: equipment?.optionalString('name'),
    );
  }
  String get display =>
      '${equipmentName == null ? '' : '$equipmentName · '}$label${unit.isEmpty ? '' : ' ($unit)'}';
}

class _Threshold {
  const _Threshold({
    required this.id,
    required this.pointId,
    required this.pointName,
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
  final bool isActive;
  final String sourceNote;
  final double? warningMin;
  final double? warningMax;
  final double? alarmMin;
  final double? alarmMax;
  final double? delta;
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
            .select('id,label,unit,equipment:equipment_id(name)')
            .eq('is_active', true)
            .order('code'),
        Supabase.instance.client
            .from('threshold')
            .select(
              'id,measurement_point_id,warning_min,warning_max,alarm_min,alarm_max,delta_max_per_round,is_active,source_note,measurement_point:measurement_point_id(label)',
            )
            .order('effective_from', ascending: false),
      ]);
      if (results[0] is! List || results[1] is! List) {
        throw const FormatException('Invalid threshold response.');
      }
      final List<_PointOption> points = (results[0] as List<Object?>)
          .map(
            (Object? row) => _PointOption.fromJson(
              requireJsonMap(row, source: 'measurement point'),
            ),
          )
          .toList(growable: false);
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
      if (mounted) _notice('Unable to load thresholds: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(double? value) => value == null ? '' : value.toString();
  Future<void> _edit(_Threshold? item) async {
    if (_points.isEmpty) {
      _notice('Add an active measurement point first.');
      return;
    }
    String pointId = item?.pointId ?? _points.first.id;
    bool active = item?.isActive ?? true;
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
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(item == null ? 'Add threshold' : 'Edit threshold'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      initialValue: pointId,
                      items: _points
                          .map(
                            (point) => DropdownMenuItem<String>(
                              value: point.id,
                              child: Text(point.display),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) =>
                          setModalState(() => pointId = value ?? pointId),
                      decoration: const InputDecoration(
                        labelText: 'Measurement point',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _numberField(warningMin, 'Warning minimum'),
                    const SizedBox(height: 10),
                    _numberField(warningMax, 'Warning maximum'),
                    const SizedBox(height: 10),
                    _numberField(alarmMin, 'Alarm minimum'),
                    const SizedBox(height: 10),
                    _numberField(alarmMax, 'Alarm maximum'),
                    const SizedBox(height: 10),
                    _numberField(delta, 'Maximum change between rounds'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: source,
                      decoration: const InputDecoration(
                        labelText: 'Source / engineering reference',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      onChanged: (bool value) =>
                          setModalState(() => active = value),
                      title: const Text('Active'),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            ),
      ),
    );
    if (saved != true) {
      _dispose(<TextEditingController>[
        warningMin,
        warningMax,
        alarmMin,
        alarmMax,
        delta,
        source,
      ]);
      return;
    }
    try {
      final String sourceNote = source.text.trim();
      if (sourceNote.isEmpty) {
        throw const FormatException(
          'A source or engineering reference is required.',
        );
      }
      final Map<String, Object?> payload = <String, Object?>{
        'measurement_point_id': pointId,
        'warning_min': _number(warningMin.text),
        'warning_max': _number(warningMax.text),
        'alarm_min': _number(alarmMin.text),
        'alarm_max': _number(alarmMax.text),
        'delta_max_per_round': _number(delta.text),
        'source_note': sourceNote,
        'is_active': active,
      };
      if (item == null) {
        await Supabase.instance.client.from('threshold').insert(payload);
      } else {
        await Supabase.instance.client
            .from('threshold')
            .update(payload)
            .eq('id', item.id);
      }
      if (mounted) {
        _notice('Threshold saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save threshold: $error');
    } finally {
      _dispose(<TextEditingController>[
        warningMin,
        warningMax,
        alarmMin,
        alarmMax,
        delta,
        source,
      ]);
    }
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label),
      );
  double? _number(String value) =>
      value.trim().isEmpty ? null : double.tryParse(value.trim());
  void _dispose(List<TextEditingController> controllers) {
    for (final TextEditingController controller in controllers) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallbackRoute: '/admin'),
      title: const Text('Thresholds'),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _edit(null),
      icon: const Icon(Icons.add),
      label: const Text('Add threshold'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, int index) {
                final _Threshold item = _items[index];
                return Card(
                  child: ListTile(
                    onTap: () => _edit(item),
                    title: Text(
                      item.pointName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Warning ${_value(item.warningMin)}-${_value(item.warningMax)} · Alarm ${_value(item.alarmMin)}-${_value(item.alarmMax)}${item.delta == null ? '' : ' · Δ ${_value(item.delta)}'}',
                    ),
                    trailing: Chip(
                      label: Text(item.isActive ? 'Active' : 'Inactive'),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}
