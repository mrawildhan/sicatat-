import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

/// Small, safe editor for the operational sequence. Equipment and measurement
/// points remain managed on their dedicated screens; this page controls how
/// many Breaker/Sizer rounds the active temperature template exposes.
class FormTemplateManagementScreen extends StatefulWidget {
  const FormTemplateManagementScreen({super.key});

  @override
  State<FormTemplateManagementScreen> createState() =>
      _FormTemplateManagementScreenState();
}

class _FormTemplateManagementScreenState
    extends State<FormTemplateManagementScreen> {
  String? _templateId;
  JsonMap _schema = <String, Object?>{};
  int _roundCount = 2;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final Object module = await Supabase.instance.client
          .from('module')
          .select('id')
          .eq('code', 'temperature_check')
          .eq('is_active', true)
          .single();
      final moduleId = requireJsonMap(
        module,
        source: 'temperature module',
      ).requiredString('id');
      final Object template = await Supabase.instance.client
          .from('form_template')
          .select('id,schema_json')
          .eq('module_id', moduleId)
          .eq('is_active', true)
          .order('effective_from', ascending: false)
          .limit(1)
          .single();
      final json = requireJsonMap(template, source: 'form template');
      final rawSchema = json['schema_json'];
      final schema = rawSchema is Map
          ? requireJsonMap(rawSchema, source: 'template schema')
          : <String, Object?>{};
      final rounds = _roundsIn(schema);
      if (!mounted) return;
      setState(() {
        _templateId = json.requiredString('id');
        _schema = schema;
        _roundCount = rounds;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Template aktif tidak dapat dimuat. Buat template di Supabase terlebih dahulu: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _roundsIn(JsonMap schema) {
    final raw = schema['steps'];
    if (raw is! List) return 2;
    var highest = 0;
    for (final Object? value in raw) {
      if (value is! Map) continue;
      final number = value['round_number'];
      if (number is num && number > highest) highest = number.toInt();
    }
    return highest.clamp(1, 2).toInt();
  }

  List<JsonMap> get _steps => <JsonMap>[
    for (var round = 1; round <= _roundCount; round++) ...<JsonMap>[
      <String, Object?>{'section': 'gearbox_breaker', 'round_number': round},
      <String, Object?>{'section': 'gearbox_sizer', 'round_number': round},
    ],
  ];

  Future<void> _save() async {
    final id = _templateId;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('form_template')
          .update(<String, Object?>{
            'schema_json': <String, Object?>{..._schema, 'steps': _steps},
          })
          .eq('id', id);
      if (mounted) {
        setState(
          () => _message = 'Template tersimpan. Sheet baru memakai urutan ini.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Template tidak dapat disimpan: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Template formulir suhu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const Text(
                  'Template mengatur urutan ronde. Peralatan dan titik ukur dimuat dari data master, sehingga titik baru dapat muncul tanpa perubahan kode aplikasi.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<int>(
                  initialValue: _roundCount,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah ronde per shift',
                  ),
                  items: <int>[1, 2]
                      .map(
                        (count) => DropdownMenuItem<int>(
                          value: count,
                          child: Text('$count ronde: Breaker lalu Sizer'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _roundCount = value ?? 2),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Preview',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                ..._steps.map(
                  (step) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(
                        '${step.requiredString('section') == 'gearbox_breaker' ? 'Gearbox Breaker' : 'Gearbox Sizer'} — Ronde ${step.requiredInt('round_number')}',
                      ),
                    ),
                  ),
                ),
                if (_message case final message?) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(message),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saving || _templateId == null ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Menyimpan...' : 'Simpan template'),
                ),
              ],
            ),
    ),
  );
}
