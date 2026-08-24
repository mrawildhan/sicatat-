import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/local/local_database.dart';
import '../../../data/models/field_entry_models.dart';
import '../../../data/models/master_data_models.dart';
import '../../../data/models/sheet_model.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class TemperatureFormScreen extends ConsumerStatefulWidget {
  const TemperatureFormScreen({
    required this.sheetId,
    this.initialSection,
    this.initialRound,
    this.initialSide,
    this.initialEntry,
    super.key,
  });

  final String? sheetId;
  final String? initialSection;
  final String? initialRound;
  final String? initialSide;
  final String? initialEntry;

  @override
  ConsumerState<TemperatureFormScreen> createState() =>
      _TemperatureFormScreenState();
}

class _TemperatureFormScreenState extends ConsumerState<TemperatureFormScreen> {
  final _reason = TextEditingController();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, bool?> _booleanValues = <String, bool?>{};
  InspectionFormConfig? _config;
  SheetModel? _sheet;
  RoundModel? _round;
  UnitOperationalStatus? _status;
  DateTime? _inspectedAt;
  int _stepIndex = 0;
  String _side = 'BARAT';
  bool _showEquipment = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<InspectionStep> get _steps =>
      _config?.steps ?? InspectionFormConfig.defaultSteps;

  @override
  void initState() {
    super.initState();
    if (widget.initialSide == 'TIMUR') _side = 'TIMUR';
    _showEquipment = widget.initialEntry != 'gearbox';
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  InspectionStep get _step => _steps[_stepIndex];
  InspectionSection get _section => _step.section;
  int get _roundNumber => _step.roundNumber;
  String get _sectionLabel => _section == InspectionSection.gearboxBreaker
      ? 'Gearbox Breaker'
      : 'Gearbox Sizer';
  String get _sideLabel => _side == 'BARAT' ? 'West' : 'East';
  List<InspectionEquipment> get _equipment =>
      _config?.equipmentFor(_section.storageValue) ?? const [];
  List<MeasurementPoint> get _gearboxPoints =>
      _config?.gearboxPoints ?? const [];
  List<MeasurementPoint> get _equipmentPoints => <MeasurementPoint>[
    for (final equipment in _equipment)
      ...(_config?.visiblePointsForEquipment(equipment) ?? const []),
  ];
  List<MeasurementPoint> get _activePoints =>
      _showEquipment ? _equipmentPoints : _gearboxPoints;

  Future<void> _load() async {
    final sheetId = widget.sheetId;
    if (sheetId == null || sheetId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Inspection sheet not found.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        LocalDatabase.instance.getSheet(sheetId),
        ref.read(sicatatRepositoryProvider).getInspectionFormConfig(),
      ]);
      final sheet = results[0] as SheetModel?;
      if (sheet == null) {
        throw const LocalRecordNotFoundException('Inspection sheet not found.');
      }
      if (sheet.status == SheetStatus.verified) {
        throw const FormatException(
          'This sheet is verified and locked. Ask a supervisor to return it before editing.',
        );
      }
      if (sheet.status == SheetStatus.submitted ||
          sheet.status == SheetStatus.submittedIncomplete) {
        throw const FormatException(
          'Reopen the submitted sheet from Sheet Summary before editing.',
        );
      }
      final config = results[1] as InspectionFormConfig;
      if (config.gearboxPoints.isEmpty) {
        throw const FormatException(
          'No gearbox temperature points are available in the active template.',
        );
      }
      _sheet = sheet;
      _config = config;
      final index = _steps.indexWhere(
        (step) =>
            step.section.storageValue == widget.initialSection &&
            step.roundNumber == int.tryParse(widget.initialRound ?? ''),
      );
      if (index >= 0) _stepIndex = index;
      for (final point in config.measurementPoints) {
        _controllers.putIfAbsent(point.id, TextEditingController.new);
      }
      await _loadCurrentEntry();
    } on LocalRecordNotFoundException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'The form could not be loaded. Check your connection or master data.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentEntry() async {
    final sheet = _sheet;
    if (sheet == null) return;
    final round = await LocalDatabase.instance.getOrCreateRound(
      sheetId: sheet.id,
      section: _section,
      roundNumber: _roundNumber,
    );
    final unit = _showEquipment
        ? null
        : await LocalDatabase.instance.getUnitStatus(
            roundId: round.id,
            unitCode: _side,
          );
    final values = await LocalDatabase.instance.getReadingValues(
      roundId: round.id,
      unitStatusId: unit?.id,
    );
    if (!mounted) return;
    setState(() {
      _round = round;
      _inspectedAt = round.inspectedAt;
      _status = unit?.status;
      _reason.text = unit?.reason ?? '';
      for (final point in _activePoints) {
        final value = values[point.id];
        _booleanValues[point.id] = value?.boolean;
        _controllers[point.id]!.text = point.dataType == 'text'
            ? value?.text ?? ''
            : value?.numeric?.toString() ?? '';
      }
    });
  }

  Future<DateTime> _ensureRecordedAt(RoundModel round) async {
    final current = _inspectedAt;
    if (current != null) return current;
    final now = DateTime.now();
    await LocalDatabase.instance.setRoundTime(
      roundId: round.id,
      inspectedAt: now,
    );
    if (mounted) setState(() => _inspectedAt = now);
    return now;
  }

  ReadingCommand? _commandFor(
    MeasurementPoint point,
    String roundId,
    String userId, {
    String? unitStatusId,
    String? anomalyNote,
  }) {
    final raw = _controllers[point.id]!.text.trim();
    if (point.dataType == 'boolean') {
      final value = _booleanValues[point.id];
      return value == null
          ? null
          : ReadingCommand(
              roundId: roundId,
              unitStatusId: unitStatusId,
              measurementPointId: point.id,
              recordedBy: userId,
              valueBoolean: value,
            );
    }
    if (point.dataType == 'text') {
      return raw.isEmpty
          ? null
          : ReadingCommand(
              roundId: roundId,
              unitStatusId: unitStatusId,
              measurementPointId: point.id,
              recordedBy: userId,
              valueText: raw,
            );
    }
    final value = double.tryParse(raw.replaceAll(',', '.'));
    return value == null
        ? null
        : ReadingCommand(
            roundId: roundId,
            unitStatusId: unitStatusId,
            measurementPointId: point.id,
            recordedBy: userId,
            valueNumeric: value,
            isAnomaly: _config!.assessTemperature(point, value).isAnomaly,
            anomalyNote: anomalyNote,
          );
  }

  List<_FlaggedTemperature> _flaggedTemperatures(
    Iterable<MeasurementPoint> points,
  ) {
    final config = _config;
    if (config == null) return const <_FlaggedTemperature>[];
    final flagged = <_FlaggedTemperature>[];
    for (final point in points) {
      if (point.dataType == 'text' || point.dataType == 'boolean') continue;
      final value = double.tryParse(
        (_controllers[point.id]?.text ?? '').trim().replaceAll(',', '.'),
      );
      if (value == null) continue;
      final assessment = config.assessTemperature(point, value);
      if (assessment.requiresConfirmation) {
        flagged.add(
          _FlaggedTemperature(
            point: point,
            value: value,
            assessment: assessment,
          ),
        );
      }
    }
    return flagged;
  }

  Future<_AnomalyDecision?> _confirmFlaggedTemperatures(
    Iterable<MeasurementPoint> points,
  ) async {
    final flagged = _flaggedTemperatures(points);
    if (flagged.isEmpty) return const _AnomalyDecision();
    final note = TextEditingController();
    try {
      return await showDialog<_AnomalyDecision>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm abnormal temperature'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'These readings will be marked as anomalies and included in the audit trail.',
                  ),
                  const SizedBox(height: 12),
                  ...flagged.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${item.point.label}: ${item.value.toStringAsFixed(1)} ${item.point.unit ?? '°C'} — ${item.assessment.message}',
                        style: TextStyle(
                          color:
                              item.assessment.level ==
                                      TemperatureAlertLevel.critical ||
                                  item.assessment.level ==
                                      TemperatureAlertLevel.invalid
                              ? AppColors.danger
                              : AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: note,
                    autofocus: true,
                    maxLines: 2,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Anomaly note *',
                      hintText: 'State the condition or confirm the reading',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Correct reading'),
              ),
              FilledButton(
                onPressed: note.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        _AnomalyDecision(note: note.text.trim()),
                      ),
                child: const Text('Save & flag'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // The dialog route keeps the TextField attached during its exit
      // animation. Disposing its controller immediately after Navigator.pop
      // triggers Flutter's `_dependents.isEmpty` assertion on Android.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      note.dispose();
    }
  }

  Future<void> _saveEquipment() async {
    final round = _round;
    final sheet = _sheet;
    final user = ref.read(currentUserProvider);
    if (round == null || sheet == null || user == null) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final anomalyDecision = await _confirmFlaggedTemperatures(
        _equipmentPoints,
      );
      if (anomalyDecision == null) return;
      final commands = _equipmentPoints
          .map(
            (point) => _commandFor(
              point,
              round.id,
              user.id,
              anomalyNote: anomalyDecision.note,
            ),
          )
          .whereType<ReadingCommand>()
          .toList(growable: false);
      if (commands.isNotEmpty) {
        final recordedAt = await _ensureRecordedAt(round);
        for (final command in commands) {
          await LocalDatabase.instance.saveReading(
            ReadingCommand(
              roundId: command.roundId,
              unitStatusId: command.unitStatusId,
              measurementPointId: command.measurementPointId,
              recordedBy: command.recordedBy,
              valueNumeric: command.valueNumeric,
              valueBoolean: command.valueBoolean,
              valueText: command.valueText,
              measuredAt: recordedAt,
              isAnomaly: command.isAnomaly,
              anomalyNote: command.anomalyNote,
            ),
          );
        }
        await LocalDatabase.instance.saveContributor(
          sheetId: sheet.id,
          userId: user.id,
        );
      }
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (!mounted) return;
      setState(() => _showEquipment = false);
      await _loadCurrentEntry();
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Equipment data could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveGearboxSide() async {
    final sheet = _sheet;
    final round = _round;
    final status = _status;
    final user = ref.read(currentUserProvider);
    if (sheet == null || round == null || user == null) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final anomalyDecision = status == UnitOperationalStatus.operating
          ? await _confirmFlaggedTemperatures(_gearboxPoints)
          : const _AnomalyDecision();
      if (anomalyDecision == null) return;
      if (status != null) {
        final unit = await LocalDatabase.instance.saveUnitStatus(
          roundId: round.id,
          unitCode: _side,
          status: status,
          reason: status == UnitOperationalStatus.operating
              ? null
              : _reason.text.trim(),
          answeredAt: DateTime.now(),
        );
        if (status == UnitOperationalStatus.operating) {
          final commands = _gearboxPoints
              .map(
                (point) => _commandFor(
                  point,
                  round.id,
                  user.id,
                  unitStatusId: unit.id,
                  anomalyNote: anomalyDecision.note,
                ),
              )
              .whereType<ReadingCommand>()
              .toList(growable: false);
          if (commands.isNotEmpty) {
            final recordedAt = await _ensureRecordedAt(round);
            for (final command in commands) {
              await LocalDatabase.instance.saveReading(
                ReadingCommand(
                  roundId: command.roundId,
                  unitStatusId: command.unitStatusId,
                  measurementPointId: command.measurementPointId,
                  recordedBy: command.recordedBy,
                  valueNumeric: command.valueNumeric,
                  valueBoolean: command.valueBoolean,
                  valueText: command.valueText,
                  measuredAt: recordedAt,
                  isAnomaly: command.isAnomaly,
                  anomalyNote: command.anomalyNote,
                ),
              );
            }
          }
        }
        await LocalDatabase.instance.saveContributor(
          sheetId: sheet.id,
          userId: user.id,
        );
      }
      await ref.read(sicatatRepositoryProvider).syncPending();
      if (!mounted) return;
      if (_side == 'BARAT') {
        setState(() => _side = 'TIMUR');
        await _loadCurrentEntry();
      } else if (_stepIndex < _steps.length - 1) {
        setState(() {
          _stepIndex += 1;
          _side = 'BARAT';
          _showEquipment = true;
        });
        await _loadCurrentEntry();
      } else {
        context.go('/summary?sheetId=${sheet.id}');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Data could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppBackScope(
        fallbackRoute: '/sheets',
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_sheet == null || _config == null) {
      return AppBackScope(
        fallbackRoute: '/sheets',
        child: Scaffold(
          appBar: AppBar(
            leading: const AppBackButton(fallbackRoute: '/sheets'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _errorMessage ?? 'Inspection sheet not found.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ),
      );
    }
    return AppBackScope(
      fallbackRoute: '/summary?sheetId=${_sheet!.id}',
      child: Scaffold(
        appBar: AppBar(
          leading: AppBackButton(
            fallbackRoute: '/summary?sheetId=${_sheet!.id}',
          ),
          title: Text(
            _showEquipment
                ? '$_sectionLabel - Round $_roundNumber'
                : 'Temperature $_sectionLabel',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Column(
          children: <Widget>[
            _progress(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: <Widget>[
                  _timeCard(),
                  const SizedBox(height: 16),
                  if (_errorMessage case final message?) ...<Widget>[
                    _validationNotice(message),
                    const SizedBox(height: 16),
                  ],
                  if (_showEquipment) ...<Widget>[
                    const Text(
                      'Equipment readings',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'You may save a partial draft and continue. Sheet Summary identifies every required point still missing.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    ..._equipment.map(_equipmentCard),
                  ] else ...<Widget>[
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: 'BARAT', label: Text('West')),
                        ButtonSegment(value: 'TIMUR', label: Text('East')),
                      ],
                      selected: <String>{_side},
                      onSelectionChanged: _isSaving
                          ? null
                          : (value) async {
                              setState(() => _side = value.first);
                              await _loadCurrentEntry();
                            },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '$_sectionLabel - $_sideLabel',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _statusSelector(),
                    const SizedBox(height: 16),
                    if (_status == UnitOperationalStatus.operating)
                      ..._gearboxPoints.map(_pointField)
                    else if (_status != null)
                      _reasonField()
                    else
                      _notice(
                        'Select a status for this side. The sheet cannot be submitted while any side is unanswered.',
                      ),
                  ],
                ],
              ),
            ),
            _bottomAction(),
          ],
        ),
      ),
    );
  }

  Widget _progress() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Row(
      children: List<Widget>.generate(
        _steps.length,
        (index) => Expanded(
          child: Column(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: index <= _stepIndex
                    ? AppColors.green
                    : AppColors.line,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: index <= _stepIndex ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_steps[index].section == InspectionSection.gearboxBreaker ? 'B' : 'S'} R${_steps[index].roundNumber}',
                style: TextStyle(
                  fontSize: 10,
                  color: index <= _stepIndex
                      ? AppColors.greenDark
                      : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _timeCard() => Card(
    child: ListTile(
      leading: const Icon(Icons.schedule_rounded, color: AppColors.green),
      title: Text(
        'Round $_roundNumber time (West & East)',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        _inspectedAt == null
            ? 'Recorded automatically when this round is saved.'
            : 'Recorded automatically: ${DateFormat('dd MMM yyyy, HH:mm').format(_inspectedAt!)}',
      ),
    ),
  );

  Widget _equipmentCard(InspectionEquipment equipment) {
    final points = _config!.visiblePointsForEquipment(equipment);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              equipment.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (points.isEmpty)
              const Text(
                'No measurement points are configured for this equipment.',
                style: TextStyle(color: AppColors.danger),
              )
            else
              ...points.map(_pointField),
          ],
        ),
      ),
    );
  }

  Widget _statusSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text(
        'Status of this side\'s unit',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      ...const <(UnitOperationalStatus, String, IconData)>[
        (
          UnitOperationalStatus.operating,
          'Operating',
          Icons.check_circle_outline,
        ),
        (
          UnitOperationalStatus.notOperating,
          'Not operating',
          Icons.pause_circle_outline,
        ),
        (
          UnitOperationalStatus.notAccessible,
          'Not accessible',
          Icons.block_outlined,
        ),
      ].map(
        (choice) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => setState(() => _status = choice.$1),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(50),
                foregroundColor: _status == choice.$1
                    ? Colors.white
                    : AppColors.greenDark,
                backgroundColor: _status == choice.$1
                    ? AppColors.green
                    : Colors.white,
                side: BorderSide(
                  color: _status == choice.$1
                      ? AppColors.green
                      : const Color(0xFFD6DDD8),
                ),
              ),
              icon: Icon(choice.$3),
              label: Text(choice.$2, overflow: TextOverflow.visible),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _pointField(MeasurementPoint point) {
    if (point.dataType == 'boolean') {
      final value = _booleanValues[point.id];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${point.label}${_config!.isRequired(point) ? ' *' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              // Required points start unselected. Keep the control renderable,
              // then enforce the requirement in _saveEquipment.
              emptySelectionAllowed: true,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment(value: true, label: Text('OK')),
                ButtonSegment(value: false, label: Text('Low')),
              ],
              selected: <bool>{if (value != null) value},
              onSelectionChanged: _isSaving
                  ? null
                  : (values) => setState(
                      () => _booleanValues[point.id] = values.isEmpty
                          ? null
                          : values.first,
                    ),
            ),
          ],
        ),
      );
    }
    final controller = _controllers[point.id]!;
    final numeric = point.dataType != 'text';
    final temperature = numeric
        ? double.tryParse(controller.text.replaceAll(',', '.'))
        : null;
    final assessment = temperature == null
        ? null
        : _config!.assessTemperature(point, temperature);
    final color = temperature == null
        ? AppColors.muted
        : assessment!.level == TemperatureAlertLevel.critical ||
              assessment.level == TemperatureAlertLevel.invalid
        ? AppColors.danger
        : assessment.level == TemperatureAlertLevel.warning
        ? AppColors.warning
        : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: !_isSaving,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLines: numeric ? 1 : 2,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: '${point.label}${_config!.isRequired(point) ? ' *' : ''}',
          hintText: _config!.isRequired(point) ? 'Required' : 'Optional',
          helperText: assessment?.requiresConfirmation == true
              ? '${assessment!.message} Confirmation is required to save.'
              : null,
          suffixText: numeric ? (point.unit ?? '°C') : null,
          prefixIcon: numeric
              ? Icon(Icons.thermostat_rounded, color: color)
              : const Icon(Icons.notes_rounded),
          filled: numeric && temperature != null,
          fillColor: numeric && temperature != null
              ? color.withValues(alpha: .08)
              : null,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: numeric && temperature != null ? color : AppColors.line,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: numeric ? color : AppColors.green,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasonField() => TextField(
    controller: _reason,
    enabled: !_isSaving,
    maxLines: 2,
    decoration: const InputDecoration(
      labelText: 'Reason *',
      hintText: 'Explain the unit condition',
    ),
  );

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.greenDark, height: 1.4),
    ),
  );

  Widget _validationNotice(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECEB),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.error_outline_rounded, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomAction() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isSaving
            ? null
            : _showEquipment
            ? _saveEquipment
            : _saveGearboxSide,
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                _showEquipment
                    ? Icons.arrow_forward_rounded
                    : Icons.save_rounded,
              ),
        label: Text(
          _showEquipment
              ? 'Save draft & continue'
              : _side == 'BARAT'
              ? 'Save West side'
              : _stepIndex == _steps.length - 1
              ? 'Save draft & view summary'
              : 'Save draft & continue',
        ),
      ),
    ),
  );
}

class _FlaggedTemperature {
  const _FlaggedTemperature({
    required this.point,
    required this.value,
    required this.assessment,
  });

  final MeasurementPoint point;
  final double value;
  final TemperatureAssessment assessment;
}

class _AnomalyDecision {
  const _AnomalyDecision({this.note});

  final String? note;
}
