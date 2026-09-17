import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

class DailyCheckNewScreen extends ConsumerStatefulWidget {
  const DailyCheckNewScreen({required this.type, super.key});

  final DailyCheckFormType type;

  @override
  ConsumerState<DailyCheckNewScreen> createState() =>
      _DailyCheckNewScreenState();
}

class _DailyCheckNewScreenState extends ConsumerState<DailyCheckNewScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  List<ShiftOption> _shifts = const <ShiftOption>[];
  List<DailyCheckTeam> _teams = const <DailyCheckTeam>[];
  Set<String> _occupied = <String>{};
  String? _shiftId;
  String? _teamId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _hubRoute => '/daily-checks/${widget.type.storageValue}';

  bool get _picksTeam =>
      ref.read(currentUserProvider)?.role.isGlobalTemperatureManager == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = ref.read(currentUserProvider);
      final shifts = await ref
          .read(sicatatRepositoryProvider)
          .getActiveShifts();
      final teams = _picksTeam
          ? await _repository.activeTeams()
          : const <DailyCheckTeam>[];
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _teams = teams;
        _teamId = _picksTeam ? teams.firstOrNull?.id : user?.teamId;
      });
      await _refreshOccupied();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Shifts could not be loaded: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOccupied() async {
    final teamId = _teamId;
    if (teamId == null) return;
    final occupied = await _repository.occupiedShiftIds(
      type: widget.type,
      date: _date,
      teamId: teamId,
    );
    if (!mounted) return;
    setState(() {
      _occupied = occupied;
      final available = _shifts.where((shift) => !occupied.contains(shift.id));
      if (_shiftId == null || occupied.contains(_shiftId)) {
        final hour = DateTime.now().hour;
        final preferred = hour >= 7 && hour < 19 ? 'PAGI' : 'MALAM';
        _shiftId =
            (available.where((shift) => shift.code == preferred).firstOrNull ??
                    available.firstOrNull)
                ?.id;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _refreshOccupied();
  }

  Future<void> _create() async {
    final user = ref.read(currentUserProvider);
    final shiftId = _shiftId;
    final teamId = _teamId;
    if (user == null || shiftId == null || teamId == null) {
      setState(
        () => _error = teamId == null
            ? 'Your account has no team. Ask an admin to set your team.'
            : 'Choose an available shift.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sheet = await _repository.create(
        type: widget.type,
        date: _date,
        shiftId: shiftId,
        teamId: teamId,
        createdBy: user.id,
      );
      if (!mounted) return;
      final first = sheet.slots.first.key;
      context.go('$_hubRoute/sheet/${sheet.id}/$first');
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
      await _refreshOccupied();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.type.form;
    final user = ref.watch(currentUserProvider);
    return AppBackScope(
      fallbackRoute: _hubRoute,
      child: Scaffold(
        appBar: AppBar(
          leading: AppBackButton(fallbackRoute: _hubRoute),
          title: const Text(
            'New sheet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  DailyCheckNotice(
                    '${form.title}. Choose the date and shift you are '
                    'recording. Each shift has one sheet; past dates can be '
                    'chosen for a missed check.',
                  ),
                  const SizedBox(height: 24),
                  _label('Date'),
                  InkWell(
                    onTap: _saving ? null : _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.calendar_month_rounded),
                      ),
                      child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_picksTeam) ...<Widget>[
                    _label('Team'),
                    DropdownButtonFormField<String>(
                      initialValue: _teamId,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                      items: _teams
                          .map(
                            (team) => DropdownMenuItem<String>(
                              value: team.id,
                              child: Text(team.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving
                          ? null
                          : (value) async {
                              setState(() => _teamId = value);
                              await _refreshOccupied();
                            },
                    ),
                    const SizedBox(height: 20),
                  ],
                  _label('Shift'),
                  if (_shifts.isEmpty)
                    const Text(
                      'No active shifts.',
                      style: TextStyle(color: AppColors.danger),
                    )
                  else
                    SegmentedButton<String>(
                      emptySelectionAllowed: true,
                      segments: _shifts
                          .map(
                            (shift) => ButtonSegment<String>(
                              value: shift.id,
                              enabled: !_occupied.contains(shift.id),
                              icon: Icon(
                                shift.code == 'PAGI'
                                    ? Icons.wb_sunny_outlined
                                    : Icons.nightlight_outlined,
                              ),
                              label: Text(
                                shift.code == 'PAGI'
                                    ? 'Day shift'
                                    : shift.code == 'MALAM'
                                    ? 'Night shift'
                                    : shift.name,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      selected: <String>{?_shiftId},
                      onSelectionChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _shiftId = value.firstOrNull ?? _shiftId,
                            ),
                    ),
                  if (_occupied.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text(
                      'Shifts that already have a sheet on this date are locked.',
                      style: TextStyle(color: Color(0xFF9A6A00), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _label('Recorded by'),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.mint,
                      child: Icon(Icons.person_rounded, color: AppColors.green),
                    ),
                    title: Text(
                      user?.name ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _picksTeam
                          ? 'Recording for the team selected above'
                          : 'Your team members can fill this sheet too',
                    ),
                  ),
                  if (_error case final error?) ...<Widget>[
                    const SizedBox(height: 12),
                    DailyCheckNotice(error, error: true),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _saving || _shiftId == null ? null : _create,
                    icon: busyIcon(_saving, Icons.check_rounded),
                    label: Text(_saving ? 'Creating…' : 'Create and start'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}
