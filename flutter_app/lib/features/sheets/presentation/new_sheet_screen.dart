import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/local/local_database.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/models/sicatat_types.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class NewSheetScreen extends ConsumerStatefulWidget {
  const NewSheetScreen({super.key});

  @override
  ConsumerState<NewSheetScreen> createState() => _NewSheetScreenState();
}

class _NewSheetScreenState extends ConsumerState<NewSheetScreen> {
  DateTime _date = DateTime.now();
  List<ShiftOption> _shifts = const <ShiftOption>[];
  ShiftOption? _selectedShift;
  TemperatureTemplate? _template;
  Set<String> _occupiedShiftIds = <String>{};
  List<_TeamOption> _teams = const <_TeamOption>[];
  String? _selectedTeamId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository = ref.read(sicatatRepositoryProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        repository.getActiveShifts(),
        repository.getActiveTemperatureTemplate(),
      ]);
      final shifts = results[0] as List<ShiftOption>;
      final template = results[1] as TemperatureTemplate;
      await LocalDatabase.instance.cacheShifts(shifts);
      await LocalDatabase.instance.cacheTemperatureTemplate(template);
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _template = template;
        _selectedShift = _initialShift(shifts);
      });
      await _loadAdminTeams();
      await _refreshShiftAvailability();
    } catch (_) {
      final cachedResults = await Future.wait<Object?>(<Future<Object?>>[
        LocalDatabase.instance.getCachedShifts(),
        LocalDatabase.instance.getCachedTemperatureTemplate(),
      ]);
      final cachedShifts = cachedResults[0] as List<ShiftOption>;
      final cachedTemplate = cachedResults[1] as TemperatureTemplate?;
      if (!mounted) return;
      setState(() {
        _shifts = cachedShifts;
        _template = cachedTemplate;
        _selectedShift = _initialShift(cachedShifts);
        _errorMessage = cachedShifts.isEmpty || cachedTemplate == null
            ? 'Shift data is not available yet. Connect to the internet once to load the initial data.'
            : 'Offline mode: using saved shift data.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAdminTeams() async {
    if (ref.read(currentUserProvider)?.role.isGlobalTemperatureManager !=
        true) {
      return;
    }
    final Object response = await Supabase.instance.client
        .from('team')
        .select('id,name,site_id')
        .eq('is_active', true)
        .order('code');
    if (response is! List) {
      throw const FormatException('Invalid team response.');
    }
    final teams = response
        .map((row) => _TeamOption.fromJson(requireJsonMap(row, source: 'team')))
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _selectedTeamId ??= teams.firstOrNull?.id;
    });
  }

  ShiftOption? _initialShift(List<ShiftOption> shifts) {
    final available = shifts
        .where((shift) => !_occupiedShiftIds.contains(shift.id))
        .toList(growable: false);
    if (available.isEmpty) return null;
    final hour = DateTime.now().hour;
    final preferredCode = hour >= 7 && hour < 19 ? 'PAGI' : 'MALAM';
    return available
            .where((shift) => shift.code == preferredCode)
            .firstOrNull ??
        available.first;
  }

  Future<void> _refreshShiftAvailability() async {
    final user = ref.read(currentUserProvider);
    final template = _template;
    if (user == null || template == null) return;
    try {
      final siteId = _siteIdForSelectedTeam(user);
      if (siteId == null) return;
      final Object response = await Supabase.instance.client.rpc(
        'occupied_temperature_shift_ids',
        params: <String, Object?>{
          'p_module_id': template.moduleId,
          'p_tanggal': _dateOnly(_date),
          'p_site_id': siteId,
        },
      );
      if (response is! List) {
        throw const FormatException('Invalid occupied shift response.');
      }
      final occupied = response
          .map(
            (Object? row) => requireJsonMap(
              row,
              source: 'occupied shift',
            ).requiredString('shift_id'),
          )
          .toSet();
      if (!mounted) return;
      setState(() {
        _occupiedShiftIds = occupied;
        if (_selectedShift == null || occupied.contains(_selectedShift!.id)) {
          _selectedShift = _initialShift(_shifts);
        }
      });
    } catch (_) {
      // Online-only validation still runs again immediately before creating a
      // sheet. Do not discard usable master data while the list refreshes.
    }
  }

  String? _siteIdForSelectedTeam(AppUser user) {
    if (!user.role.isGlobalTemperatureManager) return user.siteId;
    final String? teamId = _selectedTeamId;
    if (teamId == null) return null;
    return _teams.where((team) => team.id == teamId).firstOrNull?.siteId;
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _changeDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      initialDate: _date,
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _occupiedShiftIds = <String>{};
      _selectedShift = _initialShift(_shifts);
    });
    await _refreshShiftAvailability();
  }

  Future<void> _createSheet() async {
    final user = ref.read(currentUserProvider);
    final shift = _selectedShift;
    final template = _template;
    if (user == null) {
      setState(
        () => _errorMessage = 'Please sign in again before creating a sheet.',
      );
      return;
    }
    final teamId = user.role.isGlobalTemperatureManager
        ? _selectedTeamId
        : user.teamId;
    final siteId = _siteIdForSelectedTeam(user);
    if (teamId == null) {
      setState(
        () => _errorMessage = user.role.isGlobalTemperatureManager
            ? 'Select a crew before creating this sheet.'
            : 'Your account has no active crew assignment. Ask an admin to assign your crew before creating a sheet.',
      );
      return;
    }
    if (siteId == null) {
      setState(
        () => _errorMessage = 'The selected team has no site assignment.',
      );
      return;
    }
    if (template == null) {
      setState(
        () => _errorMessage = 'The temperature template is not available yet. Refresh this page while connected to the internet.',
      );
      return;
    }
    if (shift == null) {
      setState(
        () => _errorMessage = 'Both shifts already have sheets for this date. Choose another date, or open the existing sheet from My sheets.',
      );
      return;
    }
    if (_occupiedShiftIds.contains(shift.id)) {
      setState(
        () => _errorMessage = 'This shift already has a sheet for the selected date. Choose the other shift.',
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      // Recheck the shared server list immediately before writing. This stops
      // a second crew from opening the same date/shift after the form screen
      // has been left open for a while.
      final Object response = await Supabase.instance.client.rpc(
        'occupied_temperature_shift_ids',
        params: <String, Object?>{
          'p_module_id': template.moduleId,
          'p_tanggal': _dateOnly(_date),
          'p_site_id': siteId,
        },
      );
      if (response is! List) {
        throw const FormatException('Invalid occupied shift response.');
      }
      final duplicate = response.any(
        (Object? row) =>
            requireJsonMap(
              row,
              source: 'occupied shift',
            ).requiredString('shift_id') ==
            shift.id,
      );
      if (duplicate) {
        setState(() {
          _occupiedShiftIds = <String>{..._occupiedShiftIds, shift.id};
          _selectedShift = _initialShift(_shifts);
          _errorMessage = 'A crew has already opened this date and shift. Only the remaining shift can be created.';
        });
        return;
      }
      final sheet = await LocalDatabase.instance.insertSheet(
        CreateSheetCommand(
          date: _date,
          shiftId: shift.id,
          teamId: teamId,
          moduleId: template.moduleId,
          templateVersion: template.version,
          createdBy: user.id,
        ),
      );
      // Kirim header draft lebih dahulu agar admin/foreman dapat langsung
      // melihat lembar yang baru dibuka. Saat offline, SyncService menyimpan
      // kegagalan di antrean dan data lokal tetap aman untuk dicoba kembali.
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (mounted) context.go('/temperature?sheetId=${sheet.id}');
    } on SheetAlreadyExistsException {
      if (mounted) {
        setState(
          () => _errorMessage = 'A sheet for this date and shift already exists. Open it from My sheets.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'The sheet could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final dateText =
        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';
    return AppBackScope(
      fallbackRoute: '/sheets',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/sheets'),
          title: const Text(
            'Create new sheet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select the date and shift that match the work schedule. Past dates are allowed for missed inspections. One team uses one sheet for each date and shift.',
                      style: TextStyle(
                        height: 1.45,
                        color: AppColors.greenDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Inspection date',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 9),
            InkWell(
              onTap: _isLoading || _isSaving ? null : _changeDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_month_rounded),
                ),
                child: Text(dateText),
              ),
            ),
            const SizedBox(height: 22),
            if (user?.role.isGlobalTemperatureManager == true) ...<Widget>[
              const Text(
                'Record for crew',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                initialValue: _selectedTeamId,
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
                onChanged: _isSaving
                    ? null
                    : (String? value) async {
                        setState(() {
                          _selectedTeamId = value;
                          _occupiedShiftIds = <String>{};
                          _selectedShift = _initialShift(_shifts);
                        });
                        await _refreshShiftAvailability();
                      },
              ),
              const SizedBox(height: 22),
            ],
            const Text('Shift', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_shifts.isEmpty)
              const Text(
                'No shifts are available.',
                style: TextStyle(color: AppColors.danger),
              )
            else
              SegmentedButton<String>(
                segments: _shifts
                    .map(
                      (shift) => ButtonSegment(
                        value: shift.id,
                        enabled: !_occupiedShiftIds.contains(shift.id),
                        label: Text(displayShiftName(shift.name)),
                        icon: Icon(
                          shift.code == 'PAGI'
                              ? Icons.wb_sunny_outlined
                              : Icons.nightlight_outlined,
                        ),
                      ),
                    )
                    .toList(growable: false),
                selected: <String>{
                  if (_selectedShift != null) _selectedShift!.id,
                },
                onSelectionChanged: (value) => setState(
                  () => _selectedShift = _shifts.firstWhere(
                    (shift) => shift.id == value.first,
                  ),
                ),
              ),
            if (!_isLoading && _occupiedShiftIds.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'A used shift is locked to prevent duplicate temperature sheets.',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ],
            const SizedBox(height: 34),
            const Text(
              'Assigned crew',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 9),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const CircleAvatar(
                backgroundColor: AppColors.mint,
                child: Icon(Icons.groups_rounded, color: AppColors.green),
              ),
              title: Text(
                ref.watch(currentUserProvider)?.name ?? 'Account unavailable',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'The team is determined by the signed-in account',
              ),
            ),
            if (_errorMessage case final message?) ...[
              const SizedBox(height: 14),
              Text(
                message,
                style: TextStyle(
                  color: message.startsWith('Offline mode')
                      ? AppColors.warning
                      : AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _isLoading || _isSaving ? null : _createSheet,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _isSaving ? 'Saving draft...' : 'Create and start entry',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamOption {
  const _TeamOption({
    required this.id,
    required this.name,
    required this.siteId,
  });

  final String id;
  final String name;
  final String siteId;

  factory _TeamOption.fromJson(JsonMap json) => _TeamOption(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
    siteId: json.requiredString('site_id'),
  );
}
