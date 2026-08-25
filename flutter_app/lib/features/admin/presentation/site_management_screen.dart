import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _SiteRecord {
  const _SiteRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;

  factory _SiteRecord.fromJson(JsonMap json) => _SiteRecord(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    name: json.requiredString('name'),
    isActive: json.requiredBool('is_active'),
  );
}

class SiteManagementScreen extends StatefulWidget {
  const SiteManagementScreen({super.key});

  @override
  State<SiteManagementScreen> createState() => _SiteManagementScreenState();
}

class _SiteManagementScreenState extends State<SiteManagementScreen> {
  List<_SiteRecord> _items = const <_SiteRecord>[];
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
      final Object response = await Supabase.instance.client
          .from('site')
          .select('id,code,name,is_active')
          .order('name');
      if (response is! List) {
        throw const FormatException('Invalid site response.');
      }
      final List<_SiteRecord> items = response
          .map(
            (Object? row) =>
                _SiteRecord.fromJson(requireJsonMap(row, source: 'site')),
          )
          .toList(growable: false);
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) _notice('Unable to load sites: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(_SiteRecord? record) async {
    final TextEditingController code = TextEditingController(
      text: record?.code ?? '',
    );
    final TextEditingController name = TextEditingController(
      text: record?.name ?? '',
    );
    bool active = record?.isActive ?? true;
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(record == null ? 'Add site' : 'Edit site'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Site code'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Site name'),
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
    if (save != true) {
      code.dispose();
      name.dispose();
      return;
    }
    try {
      final String cleanCode = code.text.trim().toUpperCase();
      final String cleanName = name.text.trim();
      if (cleanCode.isEmpty || cleanName.isEmpty) {
        throw const FormatException('Site code and name are required.');
      }
      final Map<String, Object?> payload = <String, Object?>{
        'code': cleanCode,
        'name': cleanName,
        'is_active': active,
      };
      if (record == null) {
        await Supabase.instance.client.from('site').insert(payload);
      } else {
        await Supabase.instance.client
            .from('site')
            .update(payload)
            .eq('id', record.id);
      }
      await _load();
      if (mounted) _notice('Site saved.');
    } on Object catch (error) {
      if (mounted) _notice('Unable to save site: $error');
    } finally {
      code.dispose();
      name.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Sites'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add site'),
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
                  final _SiteRecord item = _items[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(item),
                      leading: const Icon(Icons.location_city_rounded),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('Code: ${item.code}'),
                      trailing: Chip(
                        label: Text(item.isActive ? 'Active' : 'Inactive'),
                      ),
                    ),
                  );
                },
              ),
            ),
    ),
  );
}
