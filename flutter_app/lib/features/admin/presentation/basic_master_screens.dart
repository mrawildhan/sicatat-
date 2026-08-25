import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class _TeamRecord {
  const _TeamRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.siteId,
    required this.siteName,
    required this.isActive,
  });
  final String id;
  final String code;
  final String name;
  final String siteId;
  final String siteName;
  final bool isActive;
  factory _TeamRecord.fromJson(JsonMap json) {
    final JsonMap site = requireJsonMap(json['site'], source: 'team site');
    return _TeamRecord(
      id: json.requiredString('id'),
      code: json.requiredString('code'),
      name: json.requiredString('name'),
      siteId: json.requiredString('site_id'),
      siteName: site.requiredString('name'),
      isActive: json.requiredBool('is_active'),
    );
  }
}

class _SiteChoice {
  const _SiteChoice({required this.id, required this.name});
  final String id;
  final String name;
  factory _SiteChoice.fromJson(JsonMap json) => _SiteChoice(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});
  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  List<_TeamRecord> _items = const <_TeamRecord>[];
  List<_SiteChoice> _sites = const <_SiteChoice>[];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
        Supabase.instance.client
            .from('team')
            .select('id,code,name,site_id,is_active,site:site_id(name)')
            .order('code'),
        Supabase.instance.client
            .from('site')
            .select('id,name')
            .eq('is_active', true)
            .order('name'),
      ]);
      final Object response = responses[0];
      final Object siteResponse = responses[1];
      if (response is! List || siteResponse is! List) {
        throw const FormatException('Invalid team response.');
      }
      final List<_TeamRecord> items = response
          .map(
            (Object? row) =>
                _TeamRecord.fromJson(requireJsonMap(row, source: 'team')),
          )
          .toList(growable: false);
      final List<_SiteChoice> sites = siteResponse
          .map(
            (Object? row) =>
                _SiteChoice.fromJson(requireJsonMap(row, source: 'site')),
          )
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _items = items;
          _sites = sites;
        });
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to load teams: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  Future<void> _edit(_TeamRecord? record) async {
    final TextEditingController code = TextEditingController(
      text: record?.code ?? '',
    );
    final TextEditingController name = TextEditingController(
      text: record?.name ?? '',
    );
    String? siteId =
        record?.siteId ?? (_sites.isEmpty ? null : _sites.first.id);
    bool active = record?.isActive ?? true;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(record == null ? 'Add team' : 'Edit team'),
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
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: siteId,
                      decoration: const InputDecoration(labelText: 'Site'),
                      items: _sites
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) =>
                          setModalState(() => siteId = value),
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
      return;
    }
    try {
      final String cleanCode = code.text.trim();
      final String cleanName = name.text.trim();
      if (cleanCode.isEmpty || cleanName.isEmpty || siteId == null) {
        throw const FormatException('Code, name, and site are required.');
      }
      final Map<String, Object?> payload = <String, Object?>{
        'code': cleanCode,
        'name': cleanName,
        'site_id': siteId,
        'is_active': active,
      };
      if (record == null) {
        await Supabase.instance.client.from('team').insert(payload);
      } else {
        await Supabase.instance.client
            .from('team')
            .update(payload)
            .eq('id', record.id);
      }
      if (mounted) {
        _notice('Team saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save team: $error');
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
        title: const Text('Teams'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add team'),
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
                  final _TeamRecord item = _items[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(item),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${item.siteName} · Code: ${item.code}'),
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

class _ShiftRecord {
  const _ShiftRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isActive,
  });
  final String id;
  final String code;
  final String name;
  final String startTime;
  final String endTime;
  final bool isActive;
  factory _ShiftRecord.fromJson(JsonMap json) => _ShiftRecord(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    name: json.requiredString('name'),
    startTime: json.requiredString('start_time'),
    endTime: json.requiredString('end_time'),
    isActive: json.requiredBool('is_active'),
  );
}

class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});
  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  List<_ShiftRecord> _items = const <_ShiftRecord>[];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Object response = await Supabase.instance.client
          .from('shift')
          .select('id,code,name,start_time,end_time,is_active')
          .order('code');
      if (response is! List) {
        throw const FormatException('Invalid shift response.');
      }
      final List<_ShiftRecord> items = response
          .map(
            (Object? row) =>
                _ShiftRecord.fromJson(requireJsonMap(row, source: 'shift')),
          )
          .toList(growable: false);
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) _notice('Unable to load shifts: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  Future<void> _edit(_ShiftRecord? record) async {
    final TextEditingController code = TextEditingController(
      text: record?.code ?? '',
    );
    final TextEditingController name = TextEditingController(
      text: record?.name ?? '',
    );
    final TextEditingController start = TextEditingController(
      text: record?.startTime.substring(0, 5) ?? '07:00',
    );
    final TextEditingController end = TextEditingController(
      text: record?.endTime.substring(0, 5) ?? '19:00',
    );
    bool active = record?.isActive ?? true;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(record == null ? 'Add shift' : 'Edit shift'),
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
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: start,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'Start time (HH:mm)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: end,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'End time (HH:mm)',
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
      start.dispose();
      end.dispose();
      return;
    }
    try {
      final String cleanCode = code.text.trim();
      final String cleanName = name.text.trim();
      final String cleanStart = start.text.trim();
      final String cleanEnd = end.text.trim();
      if (cleanCode.isEmpty ||
          cleanName.isEmpty ||
          !_time(cleanStart) ||
          !_time(cleanEnd)) {
        throw const FormatException(
          'Code, name, and time in HH:mm format are required.',
        );
      }
      final Map<String, Object?> payload = <String, Object?>{
        'code': cleanCode,
        'name': cleanName,
        'start_time': cleanStart,
        'end_time': cleanEnd,
        'is_active': active,
      };
      if (record == null) {
        await Supabase.instance.client.from('shift').insert(payload);
      } else {
        await Supabase.instance.client
            .from('shift')
            .update(payload)
            .eq('id', record.id);
      }
      if (mounted) {
        _notice('Shift saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save shift: $error');
    } finally {
      code.dispose();
      name.dispose();
      start.dispose();
      end.dispose();
    }
  }

  bool _time(String value) =>
      RegExp(r'^([01]\\d|2[0-3]):[0-5]\\d$').hasMatch(value);
  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Shifts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add shift'),
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
                  final _ShiftRecord item = _items[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(item),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${item.code} · ${item.startTime.substring(0, 5)}-${item.endTime.substring(0, 5)}',
                      ),
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

class _RosterAnchor {
  const _RosterAnchor({
    required this.id,
    required this.startDate,
    required this.teamOrder,
  });
  final String id;
  final String startDate;
  final List<String> teamOrder;
  factory _RosterAnchor.fromJson(JsonMap json) {
    final Object? rawOrder = json['urutan_regu'];
    if (rawOrder is! List) {
      throw const FormatException('Roster team order is invalid.');
    }
    return _RosterAnchor(
      id: json.requiredString('id'),
      startDate: json.requiredString('tanggal_mula'),
      teamOrder: rawOrder
          .map((Object? item) {
            if (item is! String) {
              throw const FormatException('Roster team code is invalid.');
            }
            return item;
          })
          .toList(growable: false),
    );
  }
}

class RosterManagementScreen extends StatefulWidget {
  const RosterManagementScreen({super.key});
  @override
  State<RosterManagementScreen> createState() => _RosterManagementScreenState();
}

class _RosterManagementScreenState extends State<RosterManagementScreen> {
  _RosterAnchor? _anchor;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Object response = await Supabase.instance.client
          .from('roster_anchor')
          .select('id,tanggal_mula,urutan_regu')
          .eq('is_active', true)
          .order('tanggal_mula', ascending: false)
          .limit(1);
      if (response is! List) {
        throw const FormatException('Invalid roster response.');
      }
      final _RosterAnchor? anchor = response.isEmpty
          ? null
          : _RosterAnchor.fromJson(
              requireJsonMap(response.first, source: 'roster anchor'),
            );
      if (mounted) setState(() => _anchor = anchor);
    } on Object catch (error) {
      if (mounted) _notice('Unable to load roster: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  Future<void> _edit() async {
    final TextEditingController date = TextEditingController(
      text:
          _anchor?.startDate ??
          DateTime.now().toIso8601String().substring(0, 10),
    );
    final TextEditingController order = TextEditingController(
      text: _anchor?.teamOrder.join(',') ?? 'A,B,C',
    );
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          _anchor == null ? 'Set roster rotation' : 'Edit roster rotation',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'The legacy 3-day Day - 3-day Night - 3-day Off rotation is calculated from this reference.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Cycle start date (YYYY-MM-DD)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: order,
              decoration: const InputDecoration(
                labelText: 'Team order (for example: A,B,C)',
              ),
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
    );
    if (saved != true) {
      date.dispose();
      order.dispose();
      return;
    }
    try {
      final String startDate = date.text.trim();
      final List<String> teamOrder = order.text
          .split(',')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
      if (!RegExp(r'^\\d{4}-\\d{2}-\\d{2}$').hasMatch(startDate) ||
          teamOrder.isEmpty) {
        throw const FormatException(
          'Enter a valid date and at least one team code.',
        );
      }
      if (_anchor == null) {
        await Supabase.instance.client
            .from('roster_anchor')
            .update(<String, Object?>{'is_active': false})
            .eq('is_active', true);
        await Supabase.instance.client.from('roster_anchor').insert(
          <String, Object?>{
            'tanggal_mula': startDate,
            'urutan_regu': teamOrder,
            'is_active': true,
          },
        );
      } else {
        await Supabase.instance.client
            .from('roster_anchor')
            .update(<String, Object?>{
              'tanggal_mula': startDate,
              'urutan_regu': teamOrder,
            })
            .eq('id', _anchor!.id);
      }
      if (mounted) {
        _notice('Roster rotation saved.');
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _notice('Unable to save roster: $error');
    } finally {
      date.dispose();
      order.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Roster rotation'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const Text(
                  'Set the reference used for the three-day Day - Night - Off rotation.',
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _anchor == null
                        ? const Text(
                            'No active roster rotation has been configured.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Cycle starts: ${_anchor!.startDate}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Team order: ${_anchor!.teamOrder.join(', ')}',
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_calendar_rounded),
                  label: Text(
                    _anchor == null
                        ? 'Set roster rotation'
                        : 'Edit roster rotation',
                  ),
                ),
              ],
            ),
    ),
  );
}
