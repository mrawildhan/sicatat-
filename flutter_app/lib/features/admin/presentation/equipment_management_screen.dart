import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _Equipment {
  const _Equipment({
    required this.id,
    required this.code,
    required this.name,
    required this.section,
    required this.sortOrder,
    required this.isActive,
  });
  final String id;
  final String code;
  final String name;
  final String section;
  final int sortOrder;
  final bool isActive;
  factory _Equipment.fromJson(JsonMap json) => _Equipment(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    name: json.requiredString('name'),
    section: json.requiredString('section'),
    sortOrder: json.requiredInt('sort_order'),
    isActive: json.requiredBool('is_active'),
  );
}

class EquipmentManagementScreen extends StatefulWidget {
  const EquipmentManagementScreen({super.key});
  @override
  State<EquipmentManagementScreen> createState() =>
      _EquipmentManagementScreenState();
}

class _EquipmentManagementScreenState extends State<EquipmentManagementScreen> {
  List<_Equipment> _items = const <_Equipment>[];
  String? _moduleId;
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
      final Object moduleResponse = await Supabase.instance.client
          .from('module')
          .select('id')
          .eq('code', 'temperature_check')
          .single();
      final String moduleId = requireJsonMap(
        moduleResponse,
        source: 'temperature module',
      ).requiredString('id');
      final Object response = await Supabase.instance.client
          .from('equipment')
          .select('id,code,name,section,sort_order,is_active')
          .eq('module_id', moduleId)
          .order('section')
          .order('sort_order');
      if (response is! List) {
        throw const FormatException('Invalid equipment response.');
      }
      final List<_Equipment> items = response
          .map(
            (Object? row) =>
                _Equipment.fromJson(requireJsonMap(row, source: 'equipment')),
          )
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _moduleId = moduleId;
          _items = items;
        });
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to load equipment: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(_Equipment? item) async {
    final TextEditingController code = TextEditingController(
      text: item?.code ?? '',
    );
    final TextEditingController name = TextEditingController(
      text: item?.name ?? '',
    );
    final TextEditingController sort = TextEditingController(
      text: '${item?.sortOrder ?? 0}',
    );
    String section = item?.section ?? 'gearbox_breaker';
    bool active = item?.isActive ?? true;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(item == null ? 'Add equipment' : 'Edit equipment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'Code'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: section,
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'gearbox_breaker',
                          child: Text('Gearbox Breaker'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'gearbox_sizer',
                          child: Text('Gearbox Sizer'),
                        ),
                      ],
                      onChanged: (String? value) =>
                          setModalState(() => section = value ?? section),
                      decoration: const InputDecoration(labelText: 'Section'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sort order',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: (bool value) =>
                          setModalState(() => active = value),
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
      code.dispose();
      name.dispose();
      sort.dispose();
      return;
    }
    try {
      final String cleanCode = code.text.trim();
      final String cleanName = name.text.trim();
      final int? sortOrder = int.tryParse(sort.text.trim());
      if (cleanCode.isEmpty || cleanName.isEmpty || sortOrder == null) {
        throw const FormatException(
          'Code, display name, and numeric sort order are required.',
        );
      }
      final Map<String, Object?> payload = <String, Object?>{
        'code': cleanCode,
        'name': cleanName,
        'section': section,
        'sort_order': sortOrder,
        'is_active': active,
      };
      if (item == null) {
        final String? moduleId = _moduleId;
        if (moduleId == null) {
          throw StateError('Temperature module is not loaded.');
        }
        payload['module_id'] = moduleId;
        await Supabase.instance.client.from('equipment').insert(payload);
      } else {
        await Supabase.instance.client
            .from('equipment')
            .update(payload)
            .eq('id', item.id);
      }
      if (mounted) {
        _notice('Equipment saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save equipment: $error');
    } finally {
      code.dispose();
      name.dispose();
      sort.dispose();
    }
  }

  String _section(String value) => value == 'gearbox_breaker'
      ? 'Gearbox Breaker'
      : value == 'gearbox_sizer'
      ? 'Gearbox Sizer'
      : value;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallbackRoute: '/admin'),
      title: const Text('Equipment & measurement points'),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _edit(null),
      icon: const Icon(Icons.add),
      label: const Text('Add equipment'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const Text(
                  'Equipment controls the measurement points visible in field entry.',
                ),
                const SizedBox(height: 12),
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        onTap: () => _edit(item),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${_section(item.section)} · ${item.code} · order ${item.sortOrder}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Chip(
                              label: Text(
                                item.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                            IconButton(
                              onPressed: () => context.go(
                                '/admin/measurement-points?equipmentId=${item.id}&equipmentName=${Uri.encodeComponent(item.name)}',
                              ),
                              icon: const Icon(Icons.list_alt_rounded),
                              tooltip: 'Measurement points',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    onTap: () => context.go(
                      '/admin/measurement-points?equipmentName=${Uri.encodeComponent('Shared gearbox points')}',
                    ),
                    leading: const Icon(Icons.hub_outlined),
                    title: const Text(
                      'Shared gearbox measurement points',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Points not assigned to a specific equipment',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
  );
}

class _MeasurementPoint {
  const _MeasurementPoint({
    required this.id,
    required this.code,
    required this.label,
    required this.dataType,
    required this.required,
    required this.sortOrder,
    required this.isActive,
    this.unit,
  });
  final String id;
  final String code;
  final String label;
  final String dataType;
  final bool required;
  final int sortOrder;
  final bool isActive;
  final String? unit;
  factory _MeasurementPoint.fromJson(JsonMap json) => _MeasurementPoint(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    label: json.requiredString('label'),
    dataType: json.requiredString('data_type'),
    required: json.requiredBool('is_required'),
    sortOrder: json.requiredInt('sort_order'),
    isActive: json.requiredBool('is_active'),
    unit: json.optionalString('unit'),
  );
}

class MeasurementPointManagementScreen extends StatefulWidget {
  const MeasurementPointManagementScreen({
    required this.equipmentId,
    required this.equipmentName,
    super.key,
  });
  final String? equipmentId;
  final String equipmentName;
  @override
  State<MeasurementPointManagementScreen> createState() =>
      _MeasurementPointManagementScreenState();
}

class _MeasurementPointManagementScreenState
    extends State<MeasurementPointManagementScreen> {
  List<_MeasurementPoint> _items = const <_MeasurementPoint>[];
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
      final Object response = widget.equipmentId == null
          ? await Supabase.instance.client
                .from('measurement_point')
                .select(
                  'id,code,label,data_type,unit,is_required,sort_order,is_active',
                )
                .isFilter('equipment_id', null)
                .order('sort_order')
          : await Supabase.instance.client
                .from('measurement_point')
                .select(
                  'id,code,label,data_type,unit,is_required,sort_order,is_active',
                )
                .eq('equipment_id', widget.equipmentId!)
                .order('sort_order');
      if (response is! List) {
        throw const FormatException('Invalid measurement point response.');
      }
      final List<_MeasurementPoint> items = response
          .map(
            (Object? row) => _MeasurementPoint.fromJson(
              requireJsonMap(row, source: 'measurement point'),
            ),
          )
          .toList(growable: false);
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) _notice('Unable to load measurement points: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(_MeasurementPoint? item) async {
    final TextEditingController code = TextEditingController(
      text: item?.code ?? '',
    );
    final TextEditingController label = TextEditingController(
      text: item?.label ?? '',
    );
    final TextEditingController unit = TextEditingController(
      text: item?.unit ?? '',
    );
    final TextEditingController sort = TextEditingController(
      text: '${item?.sortOrder ?? 0}',
    );
    String dataType = item?.dataType ?? 'numeric';
    bool required = item?.required ?? true;
    bool active = item?.isActive ?? true;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(
                item == null
                    ? 'Add measurement point'
                    : 'Edit measurement point',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'Code'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: label,
                      decoration: const InputDecoration(labelText: 'Label'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: dataType,
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'numeric',
                          child: Text('Numeric'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'boolean',
                          child: Text('Boolean'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'text',
                          child: Text('Text'),
                        ),
                      ],
                      onChanged: (String? value) =>
                          setModalState(() => dataType = value ?? dataType),
                      decoration: const InputDecoration(labelText: 'Data type'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unit,
                      decoration: const InputDecoration(
                        labelText: 'Unit (for example: °C)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sort order',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Required'),
                      value: required,
                      onChanged: (bool value) =>
                          setModalState(() => required = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: (bool value) =>
                          setModalState(() => active = value),
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
      code.dispose();
      label.dispose();
      unit.dispose();
      sort.dispose();
      return;
    }
    try {
      final String cleanCode = code.text.trim();
      final String cleanLabel = label.text.trim();
      final int? sortOrder = int.tryParse(sort.text.trim());
      if (cleanCode.isEmpty || cleanLabel.isEmpty || sortOrder == null) {
        throw const FormatException(
          'Code, label, and numeric sort order are required.',
        );
      }
      final Map<String, Object?> payload = <String, Object?>{
        'code': cleanCode,
        'label': cleanLabel,
        'data_type': dataType,
        'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
        'is_required': required,
        'sort_order': sortOrder,
        'is_active': active,
      };
      if (item == null) {
        payload['equipment_id'] = widget.equipmentId;
        await Supabase.instance.client
            .from('measurement_point')
            .insert(payload);
      } else {
        await Supabase.instance.client
            .from('measurement_point')
            .update(payload)
            .eq('id', item.id);
      }
      if (mounted) {
        _notice('Measurement point saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save measurement point: $error');
    } finally {
      code.dispose();
      label.dispose();
      unit.dispose();
      sort.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.equipmentName)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _edit(null),
      icon: const Icon(Icons.add),
      label: const Text('Add point'),
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
                final _MeasurementPoint item = _items[index];
                return Card(
                  child: ListTile(
                    onTap: () => _edit(item),
                    title: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${item.code} · ${item.dataType}${item.unit == null ? '' : ' · ${item.unit}'}${item.required ? '' : ' · optional'}',
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
