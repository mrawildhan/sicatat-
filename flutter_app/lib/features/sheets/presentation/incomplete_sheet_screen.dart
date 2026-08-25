import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../auth/application/current_user_provider.dart';
import '../../../core/widgets/app_navigation.dart';

class _IncompleteSheet {
  const _IncompleteSheet({
    required this.id,
    required this.date,
    required this.status,
    required this.teamName,
    required this.shiftCode,
    required this.completed,
  });
  final String id;
  final String date;
  final String status;
  final String teamName;
  final String shiftCode;
  final int completed;
  factory _IncompleteSheet.fromJson(JsonMap json, int completed) {
    final Object? rawTeam = json['team'];
    final Object? rawShift = json['shift'];
    final JsonMap? team = rawTeam == null
        ? null
        : requireJsonMap(rawTeam, source: 'sheet team');
    final JsonMap? shift = rawShift == null
        ? null
        : requireJsonMap(rawShift, source: 'sheet shift');
    return _IncompleteSheet(
      id: json.requiredString('id'),
      date: json.requiredString('tanggal'),
      status: json.requiredString('status'),
      teamName: team?.optionalString('name') ?? 'Unassigned',
      shiftCode: shift?.optionalString('code') ?? '—',
      completed: completed,
    );
  }
}

class IncompleteSheetScreen extends ConsumerStatefulWidget {
  const IncompleteSheetScreen({super.key});
  @override
  ConsumerState<IncompleteSheetScreen> createState() =>
      _IncompleteSheetScreenState();
}

class _IncompleteSheetScreenState extends ConsumerState<IncompleteSheetScreen> {
  static const int _expectedSides = 8;
  List<_IncompleteSheet> _items = const <_IncompleteSheet>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppUser? user = ref.read(currentUserProvider);
      final Object response;
      if (user?.role.isTeamScopedTemperature == true && user?.teamId != null) {
        response = await Supabase.instance.client
            .from('sheet')
            .select('id,tanggal,status,team:team_id(name),shift:shift_id(code)')
            .inFilter('status', const <String>['draft', 'submitted_incomplete'])
            .eq('team_id', user!.teamId!)
            .order('tanggal', ascending: false);
      } else {
        response = await Supabase.instance.client
            .from('sheet')
            .select('id,tanggal,status,team:team_id(name),shift:shift_id(code)')
            .inFilter('status', const <String>['draft', 'submitted_incomplete'])
            .order('tanggal', ascending: false);
      }
      if (response is! List) {
        throw const FormatException('Invalid sheet response.');
      }
      final List<_IncompleteSheet> loaded = <_IncompleteSheet>[];
      for (final Object? rawSheet in response) {
        final JsonMap sheet = requireJsonMap(
          rawSheet,
          source: 'incomplete sheet',
        );
        final String sheetId = sheet.requiredString('id');
        final Object roundsResponse = await Supabase.instance.client
            .from('round')
            .select('id')
            .eq('sheet_id', sheetId);
        if (roundsResponse is! List) {
          throw const FormatException('Invalid round response.');
        }
        final List<String> roundIds = roundsResponse
            .map(
              (Object? rawRound) => requireJsonMap(
                rawRound,
                source: 'round',
              ).requiredString('id'),
            )
            .toList(growable: false);
        int completed = 0;
        if (roundIds.isNotEmpty) {
          final PostgrestResponse<List<Map<String, dynamic>>> countResponse =
              await Supabase.instance.client
                  .from('unit_status')
                  .select('id')
                  .inFilter('round_id', roundIds)
                  .not('unit_code', 'is', null)
                  .not('status', 'is', null)
                  .count(CountOption.exact);
          completed = countResponse.count;
        }
        loaded.add(_IncompleteSheet.fromJson(sheet, completed));
      }
      if (mounted) setState(() => _items = loaded);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUser? user = ref.watch(currentUserProvider);
    final bool teamOnly = user?.role.isTeamScopedTemperature == true;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text('Incomplete sheets'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Text(
                      teamOnly
                          ? 'Showing your team only.'
                          : 'Showing all teams.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 14),
                    if (_error != null) _errorCard(),
                    if (_error == null && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 36),
                        child: Center(child: Text('No incomplete sheets.')),
                      ),
                    ..._items.map(_tile),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _errorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Unable to load: $_error'),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    ),
  );
  Widget _tile(_IncompleteSheet sheet) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        leading: Icon(
          sheet.status == 'submitted_incomplete'
              ? Icons.warning_amber_rounded
              : Icons.edit_note_rounded,
        ),
        title: Text(
          sheet.date,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${sheet.teamName} · ${sheet.shiftCode}'),
        trailing: Chip(
          label: Text(
            '${sheet.completed}/$_expectedSides · ${sheet.status == 'submitted_incomplete' ? 'Override' : 'Draft'}',
          ),
        ),
      ),
    ),
  );
}
