import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

/// Fills one check (hydraulic) or one reading (coal valve).
///
/// Hydraulic feeders are entered one feeder at a time, like West/East on the
/// Feeder/Sizer form. Coal valve sides are short, so all four sit on one page.
class DailyCheckEntryScreen extends ConsumerStatefulWidget {
  const DailyCheckEntryScreen({
    required this.type,
    required this.sheetId,
    required this.slotKey,
    super.key,
  });

  final DailyCheckFormType type;
  final String sheetId;
  final String slotKey;

  @override
  ConsumerState<DailyCheckEntryScreen> createState() =>
      _DailyCheckEntryScreenState();
}

class _DailyCheckEntryScreenState extends ConsumerState<DailyCheckEntryScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  final ScrollController _scroll = ScrollController();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final TextEditingController _remarks = TextEditingController();
  final Map<String, DailyCheckUnitStatus> _statuses =
      <String, DailyCheckUnitStatus>{};
  DailyCheckSheet? _sheet;
  String? _recordedAt;
  int _unitIndex = 0;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  DailyCheckForm get _form => widget.type.form;
  String get _sheetRoute =>
      '/daily-checks/${widget.type.storageValue}/sheet/${widget.sheetId}';
  bool get _tabbed => _form.hasUnitStatus;

  @override
  void initState() {
    super.initState();
    for (final unit in _form.units) {
      _controllers[DailyCheckForm.reasonKey(unit)] = TextEditingController();
      for (final field in _form.fields) {
        _controllers[DailyCheckForm.valueKey(unit, field)] =
            TextEditingController();
      }
    }
    _load();
  }

  @override
  void didUpdateWidget(DailyCheckEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slotKey != widget.slotKey ||
        oldWidget.sheetId != widget.sheetId) {
      _unitIndex = 0;
      _load();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _remarks.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = await _repository.get(widget.sheetId);
      if (!mounted) return;
      final values =
          sheet?.readings[widget.slotKey] ?? const <String, Object?>{};
      for (final entry in _controllers.entries) {
        final value = values[entry.key];
        entry.value.text = value is num
            ? formatReading(value)
            : value is String
            ? value
            : '';
      }
      _remarks.text = values[DailyCheckForm.remarksKey] as String? ?? '';
      for (final unit in _form.units) {
        _statuses[unit.key] = _form.unitStatus(values, unit);
      }
      final recorded = values[DailyCheckForm.recordedAtKey];
      setState(() {
        _sheet = sheet;
        _recordedAt = recorded is String ? recorded : null;
        _dirty = false;
        if (sheet == null) {
          _error = 'Lembar tidak ditemukan atau tidak dapat Anda buka.';
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Lembar tidak dapat dimuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _editable {
    final sheet = _sheet;
    final user = ref.read(currentUserProvider);
    if (sheet == null || user == null || !sheet.isDraft) return false;
    return user.role.isGlobalTemperatureManager ||
        (user.role == UserRole.crew && user.teamId == sheet.teamId);
  }

  List<DailyCheckSlot> get _slots => _sheet?.slots ?? const <DailyCheckSlot>[];

  int get _slotIndex => _slots.indexWhere((slot) => slot.key == widget.slotKey);

  DailyCheckSlot? get _slot {
    final index = _slotIndex;
    return index < 0 ? null : _slots[index];
  }

  double? _number(String key) => double.tryParse(
    (_controllers[key]?.text ?? '').trim().replaceAll(',', '.'),
  );

  /// Values of the whole slot as they will be stored.
  Map<String, Object?> _collect() {
    final values = <String, Object?>{};
    for (final unit in _form.units) {
      final status = _statuses[unit.key] ?? DailyCheckUnitStatus.running;
      if (_form.hasUnitStatus && status != DailyCheckUnitStatus.running) {
        values[DailyCheckForm.statusKey(unit)] = status.storageValue;
        final reason = _controllers[DailyCheckForm.reasonKey(unit)]!.text
            .trim();
        if (reason.isNotEmpty) values[DailyCheckForm.reasonKey(unit)] = reason;
        continue;
      }
      for (final field in _form.fields) {
        final key = DailyCheckForm.valueKey(unit, field);
        final number = _number(key);
        if (number != null) values[key] = number;
      }
    }
    final remarks = _remarks.text.trim();
    if (remarks.isNotEmpty) values[DailyCheckForm.remarksKey] = remarks;
    if (values.isNotEmpty) {
      values[DailyCheckForm.recordedAtKey] =
          _recordedAt ?? DateTime.now().toUtc().toIso8601String();
    }
    return values;
  }

  String? _validate() {
    for (final unit in _form.units) {
      for (final field in _form.fields) {
        if (field.kind != DailyCheckValueKind.temperature) continue;
        final value = _number(DailyCheckForm.valueKey(unit, field));
        if (value != null &&
            (value < minPlausibleTemperature ||
                value > maxPlausibleTemperature)) {
          return '${unit.label} · ${field.label}: ${formatReading(value)} °C '
              'berada di luar ${minPlausibleTemperature.toInt()}–'
              '${maxPlausibleTemperature.toInt()} °C. Periksa kembali nilainya.';
        }
      }
    }
    return null;
  }

  Future<bool> _save() async {
    final sheet = _sheet;
    if (sheet == null || !_editable) return true;
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = _collect();
      await _repository.saveSlot(sheet.id, widget.slotKey, values);
      _recordedAt = values[DailyCheckForm.recordedAtKey] as String?;
      _dirty = false;
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Belum tersimpan: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _saveAndContinue() async {
    if (!_editable) {
      _goNext();
      return;
    }
    if (!await _save() || !mounted) return;
    _goNext();
  }

  void _goNext() {
    if (_tabbed && _unitIndex < _form.units.length - 1) {
      setState(() => _unitIndex += 1);
      _toTop();
      return;
    }
    final next = _slotIndex + 1;
    if (next < _slots.length) {
      context.go('$_sheetRoute/${_slots[next].key}');
    } else {
      context.go(_sheetRoute);
    }
  }

  Future<void> _jumpTo(DailyCheckSlot slot) async {
    if (slot.key == widget.slotKey) return;
    if (_dirty && !await _save()) return;
    if (mounted) context.go('$_sheetRoute/${slot.key}');
  }

  Future<void> _leave() async {
    if (_dirty && !await _save()) return;
    if (mounted) context.go(_sheetRoute);
  }

  void _changed() {
    if (!_dirty || _error != null) {
      setState(() {
        _dirty = true;
        _error = null;
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    return AppBackScope(
      fallbackRoute: _sheetRoute,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Kembali ke lembar',
            onPressed: _saving ? null : _leave,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            slot == null
                ? _form.title
                : '${slot.label}${slot.plannedTime == null ? '' : ' · ${slot.plannedTime}'}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sheet == null || slot == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? 'Pengecekan ini tidak ditemukan.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  _progress(),
                  Expanded(child: _formBody(slot)),
                  _bottom(),
                ],
              ),
      ),
    );
  }

  Widget _progress() {
    final sheet = _sheet!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: <Widget>[
          for (final slot in _slots)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _saving ? null : () => _jumpTo(slot),
                child: SizedBox(
                  width: 84,
                  child: Column(
                    children: <Widget>[
                      _progressDot(sheet, slot),
                      const SizedBox(height: 4),
                      Text(
                        slot.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: slot.key == widget.slotKey
                              ? AppColors.greenDark
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressDot(DailyCheckSheet sheet, DailyCheckSlot slot) {
    final current = slot.key == widget.slotKey;
    final state = sheet.form.slotState(sheet.readings[slot.key]);
    final color = current ? AppColors.green : slotStateColor(state);
    return CircleAvatar(
      radius: 14,
      backgroundColor: current || state != DailyCheckSlotState.empty
          ? color
          : AppColors.line,
      child: state == DailyCheckSlotState.complete && !current
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : Text(
              slot.shortLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: current || state != DailyCheckSlotState.empty
                    ? Colors.white
                    : AppColors.muted,
              ),
            ),
    );
  }

  Widget _formBody(DailyCheckSlot slot) {
    final units = _tabbed
        ? <DailyCheckUnit>[_form.units[_unitIndex]]
        : _form.units;
    final recordedAt = _recordedAt == null
        ? null
        : DateTime.tryParse(_recordedAt!)?.toLocal();
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.schedule_rounded, color: AppColors.green),
            title: Text(
              slot.plannedTime == null
                  ? 'Jam ${slot.label.toLowerCase()}'
                  : '${slot.label} · jadwal pukul ${slot.plannedTime}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              recordedAt == null
                  ? 'Tercatat otomatis saat pertama kali disimpan.'
                  : 'Tercatat ${DateFormat('dd/MM/yyyy, HH:mm').format(recordedAt)}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!_editable) ...<Widget>[
          const DailyCheckNotice(
            'Lembar ini hanya dapat dilihat. Buka kembali lembar untuk mengubah nilai.',
          ),
          const SizedBox(height: 12),
        ] else ...<Widget>[
          DailyCheckNotice(_form.entryHint),
          const SizedBox(height: 12),
        ],
        if (_error case final error?) ...<Widget>[
          DailyCheckNotice(error, error: true),
          const SizedBox(height: 12),
        ],
        if (_tabbed) ...<Widget>[
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (var i = 0; i < _form.units.length; i++)
                ButtonSegment<int>(
                  value: i,
                  label: Text(_form.units[i].label),
                  icon: Icon(
                    _unitComplete(_form.units[i])
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                  ),
                ),
            ],
            selected: <int>{_unitIndex},
            onSelectionChanged: _saving
                ? null
                : (value) {
                    setState(() => _unitIndex = value.first);
                    _toTop();
                  },
          ),
          const SizedBox(height: 16),
        ],
        for (final unit in units) _unitCard(unit),
        const SizedBox(height: 4),
        TextField(
          controller: _remarks,
          enabled: _editable && !_saving,
          maxLines: 2,
          maxLength: 500,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: 'Keterangan (opsional)',
            hintText: _form.hasUnitStatus
                ? 'Isi bila ditemukan gejala kerusakan pada unit'
                : 'Hal tidak biasa pada pembacaan ini',
            prefixIcon: const Icon(Icons.notes_rounded),
          ),
        ),
      ],
    );
  }

  bool _unitComplete(DailyCheckUnit unit) {
    final status = _statuses[unit.key] ?? DailyCheckUnitStatus.running;
    if (status != DailyCheckUnitStatus.running) {
      return _controllers[DailyCheckForm.reasonKey(unit)]!.text
          .trim()
          .isNotEmpty;
    }
    return _form.fields.every(
      (field) =>
          !field.required ||
          _number(DailyCheckForm.valueKey(unit, field)) != null,
    );
  }

  Widget _unitCard(DailyCheckUnit unit) {
    final status = _statuses[unit.key] ?? DailyCheckUnitStatus.running;
    final enabled = _editable && !_saving;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    unit.label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.greenDark,
                    ),
                  ),
                ),
                if (_unitComplete(unit))
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.green,
                  ),
              ],
            ),
            if (_form.hasUnitStatus) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'Status unit',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final choice in DailyCheckUnitStatus.values)
                    ChoiceChip(
                      avatar: Icon(
                        choice.icon,
                        size: 18,
                        color: status == choice
                            ? Colors.white
                            : AppColors.greenDark,
                      ),
                      showCheckmark: false,
                      label: Text(choice.label),
                      selected: status == choice,
                      selectedColor: AppColors.green,
                      labelStyle: TextStyle(
                        color: status == choice
                            ? Colors.white
                            : AppColors.greenDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: enabled
                          ? (_) {
                              _statuses[unit.key] = choice;
                              _changed();
                            }
                          : null,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (status != DailyCheckUnitStatus.running)
              TextField(
                controller: _controllers[DailyCheckForm.reasonKey(unit)],
                enabled: enabled,
                maxLines: 2,
                maxLength: 300,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Alasan *',
                  hintText: 'Mengapa tidak ada pembacaan?',
                ),
              )
            else
              for (final section in _form.sections) ...<Widget>[
                if (_form.sections.length > 1) ...<Widget>[
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _fieldGrid(unit, section.fields, enabled),
                const SizedBox(height: 6),
              ],
          ],
        ),
      ),
    );
  }

  Widget _fieldGrid(
    DailyCheckUnit unit,
    List<DailyCheckField> fields,
    bool enabled,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640
          ? 4
          : constraints.maxWidth >= 300
          ? 2
          : 1;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 0,
        children: <Widget>[
          for (final field in fields)
            SizedBox(width: width, child: _field(unit, field, enabled)),
        ],
      );
    },
  );

  Widget _field(DailyCheckUnit unit, DailyCheckField field, bool enabled) {
    final key = DailyCheckForm.valueKey(unit, field);
    final controller = _controllers[key]!;
    final value = _number(key);
    final isTemperature = field.kind == DailyCheckValueKind.temperature;
    final color = isTemperature && value != null
        ? temperatureColor(value)
        : AppColors.green;
    final showColor = isTemperature && value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*[.,]?\d*')),
        ],
        onChanged: (_) => _changed(),
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.required ? null : 'Opsional',
          suffixText: field.unit,
          isDense: true,
          prefixIcon: Icon(
            switch (field.kind) {
              DailyCheckValueKind.temperature => Icons.thermostat_rounded,
              DailyCheckValueKind.pressure => Icons.speed_rounded,
              DailyCheckValueKind.speed => Icons.rotate_right_rounded,
            },
            color: showColor ? color : AppColors.muted,
            size: 20,
          ),
          filled: showColor,
          fillColor: showColor ? color.withValues(alpha: .08) : null,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: showColor ? color : AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: color, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _bottom() {
    final isLastUnit = !_tabbed || _unitIndex == _form.units.length - 1;
    final isLastSlot = _slotIndex == _slots.length - 1;
    final String label;
    if (!_editable) {
      label = isLastUnit && isLastSlot ? 'Kembali ke lembar' : 'Berikutnya';
    } else if (!isLastUnit) {
      label = 'Simpan ${_form.units[_unitIndex].label} & lanjutkan';
    } else if (isLastSlot) {
      label = 'Simpan & lihat lembar';
    } else {
      label = 'Simpan & lanjutkan';
    }
    return DailyCheckBottomBar(
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _saveAndContinue,
        icon: busyIcon(
          _saving,
          _editable ? Icons.save_rounded : Icons.arrow_forward_rounded,
        ),
        label: Text(label),
      ),
    );
  }
}
