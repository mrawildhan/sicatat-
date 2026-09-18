import 'package:flutter/material.dart';

/// The two paper check sheets that sit next to the Feeder/Sizer temperature
/// sheet. Everything about their layout lives here so the entry screen, the
/// sheet summary, and the PDF always agree.
enum DailyCheckFormType {
  hydraulicFeeder('hydraulic_feeder'),
  coalValve('coal_valve');

  const DailyCheckFormType(this.storageValue);

  /// Value of `daily_check_sheet.form_type`, also used in routes.
  final String storageValue;

  static DailyCheckFormType? fromStorage(String? value) {
    for (final type in values) {
      if (type.storageValue == value) return type;
    }
    return null;
  }

  DailyCheckForm get form => switch (this) {
    DailyCheckFormType.hydraulicFeeder => hydraulicFeederForm,
    DailyCheckFormType.coalValve => coalValveForm,
  };
}

/// What a unit (feeder) was doing at check time. Values are stored as-is.
enum DailyCheckUnitStatus {
  running('running', 'Beroperasi', Icons.check_circle_outline),
  notRunning('not_running', 'Tidak beroperasi', Icons.pause_circle_outline),
  notAccessible('not_accessible', 'Tidak dapat diakses', Icons.block_outlined);

  const DailyCheckUnitStatus(this.storageValue, this.label, this.icon);

  final String storageValue;
  final String label;
  final IconData icon;

  static DailyCheckUnitStatus? fromStorage(Object? value) {
    for (final status in values) {
      if (status.storageValue == value) return status;
    }
    return null;
  }
}

enum DailyCheckValueKind { temperature, pressure, speed }

class DailyCheckField {
  const DailyCheckField(
    this.key,
    this.label, {
    required this.kind,
    this.required = true,
  });

  final String key;
  final String label;
  final DailyCheckValueKind kind;
  final bool required;

  String? get unit => switch (kind) {
    DailyCheckValueKind.temperature => '°C',
    DailyCheckValueKind.pressure => 'bar',
    DailyCheckValueKind.speed => null,
  };
}

class DailyCheckSection {
  const DailyCheckSection(this.title, this.fields);

  final String title;
  final List<DailyCheckField> fields;
}

/// A column on the paper form: a feeder, or a side of the coal valves.
class DailyCheckUnit {
  const DailyCheckUnit(this.key, this.label);

  final String key;
  final String label;
}

/// One time on the paper form: Check I/II/III, or one coal valve time block.
class DailyCheckSlot {
  const DailyCheckSlot({
    required this.key,
    required this.label,
    required this.shortLabel,
    this.plannedTime,
  });

  final String key;
  final String label;
  final String shortLabel;

  /// The time printed on the paper form, when it has one.
  final String? plannedTime;
}

enum DailyCheckSlotState { empty, partial, complete }

class DailyCheckForm {
  const DailyCheckForm({
    required this.type,
    required this.title,
    required this.printBackground,
    required this.description,
    required this.icon,
    required this.units,
    required this.sections,
    required this.hasUnitStatus,
    required this.slotsForShift,
    required this.entryHint,
  });

  final DailyCheckFormType type;
  final String title;

  /// Blank paper form exported from the Excel sheet; the PDF writes the
  /// values on top of it (see daily_check_pdf.dart).
  final String printBackground;
  final String description;
  final IconData icon;
  final List<DailyCheckUnit> units;
  final List<DailyCheckSection> sections;

  /// Feeders can be stopped; each check records whether they were running.
  final bool hasUnitStatus;

  final List<DailyCheckSlot> Function(String? shiftCode) slotsForShift;
  final String entryHint;

  Iterable<DailyCheckField> get fields =>
      sections.expand((section) => section.fields);

  static String valueKey(DailyCheckUnit unit, DailyCheckField field) =>
      '${unit.key}.${field.key}';
  static String statusKey(DailyCheckUnit unit) => '${unit.key}.status';
  static String reasonKey(DailyCheckUnit unit) => '${unit.key}.reason';
  static const String remarksKey = 'remarks';
  static const String recordedAtKey = 'recorded_at';

  DailyCheckUnitStatus unitStatus(
    Map<String, Object?> slot,
    DailyCheckUnit unit,
  ) => hasUnitStatus
      ? DailyCheckUnitStatus.fromStorage(slot[statusKey(unit)]) ??
            DailyCheckUnitStatus.running
      : DailyCheckUnitStatus.running;

  /// Number of values still needed before this slot counts as complete.
  int missingCount(Map<String, Object?>? slot) {
    final values = slot ?? const <String, Object?>{};
    var missing = 0;
    for (final unit in units) {
      final status = unitStatus(values, unit);
      if (status != DailyCheckUnitStatus.running) {
        final reason = values[reasonKey(unit)];
        if (reason is! String || reason.trim().isEmpty) missing++;
        continue;
      }
      for (final field in fields) {
        if (field.required && values[valueKey(unit, field)] is! num) missing++;
      }
    }
    return missing;
  }

  DailyCheckSlotState slotState(Map<String, Object?>? slot) {
    if (slot == null || !slot.keys.any((key) => key != recordedAtKey)) {
      return DailyCheckSlotState.empty;
    }
    return missingCount(slot) == 0
        ? DailyCheckSlotState.complete
        : DailyCheckSlotState.partial;
  }

  DailyCheckLimits limitsFor(DailyCheckField field) =>
      DailyCheckThresholds.of(type, field.key);

  DailyCheckTemperatureLevel levelOf(DailyCheckField field, double value) =>
      temperatureLevel(value, limitsFor(field));

  /// Worst band on the sheet, judged against each point's own limits.
  DailyCheckTemperatureLevel worstLevel(
    Map<String, Map<String, Object?>> readings,
  ) {
    var worst = DailyCheckTemperatureLevel.normal;
    for (final slot in readings.values) {
      for (final unit in units) {
        for (final field in fields) {
          if (field.kind != DailyCheckValueKind.temperature) continue;
          final value = slot[valueKey(unit, field)];
          if (value is! num) continue;
          final level = levelOf(field, value.toDouble());
          if (level.index > worst.index) worst = level;
        }
      }
    }
    return worst;
  }

  /// Highest temperature on the sheet, for the "High temp" counter.
  double? highestTemperature(Map<String, Map<String, Object?>> readings) {
    double? highest;
    for (final slot in readings.values) {
      for (final unit in units) {
        for (final field in fields) {
          if (field.kind != DailyCheckValueKind.temperature) continue;
          final value = slot[valueKey(unit, field)];
          if (value is num && (highest == null || value > highest)) {
            highest = value.toDouble();
          }
        }
      }
    }
    return highest;
  }
}

/// Temperature bands. The app-wide default is 60–69 °C warning and 70 °C and
/// above critical; admins can set other limits per point (Data master →
/// Batas suhu lembar harian), for example for hydraulic oil.
enum DailyCheckTemperatureLevel { normal, warning, critical }

class DailyCheckLimits {
  const DailyCheckLimits(this.warning, this.critical);

  final double warning;
  final double critical;

  static const DailyCheckLimits standard = DailyCheckLimits(60, 70);
}

/// Limits loaded from `daily_check_threshold`; points without a row use
/// [DailyCheckLimits.standard].
abstract final class DailyCheckThresholds {
  static Map<String, DailyCheckLimits> _limits = <String, DailyCheckLimits>{};

  static String key(DailyCheckFormType type, String fieldKey) =>
      '${type.storageValue}:$fieldKey';

  static void replaceAll(Map<String, DailyCheckLimits> limits) =>
      _limits = Map<String, DailyCheckLimits>.unmodifiable(limits);

  static DailyCheckLimits of(DailyCheckFormType type, String fieldKey) =>
      _limits[key(type, fieldKey)] ?? DailyCheckLimits.standard;

  static bool isCustom(DailyCheckFormType type, String fieldKey) =>
      _limits.containsKey(key(type, fieldKey));
}

DailyCheckTemperatureLevel temperatureLevel(
  double value, [
  DailyCheckLimits limits = DailyCheckLimits.standard,
]) => value >= limits.critical
    ? DailyCheckTemperatureLevel.critical
    : value >= limits.warning
    ? DailyCheckTemperatureLevel.warning
    : DailyCheckTemperatureLevel.normal;

/// Readings outside this range are almost certainly typing mistakes.
const double minPlausibleTemperature = -50;
const double maxPlausibleTemperature = 250;

const int coalValveReadings = 4;

const _feeder1 = DailyCheckUnit('f1', 'Feeder 1');
const _feeder2 = DailyCheckUnit('f2', 'Feeder 2');

final DailyCheckForm hydraulicFeederForm = DailyCheckForm(
  type: DailyCheckFormType.hydraulicFeeder,
  title: 'Daily Check Sheet Hydraulic Feeder',
  printBackground: 'assets/forms/hydraulic_feeder_form.png',
  description: 'Suhu dan tekanan pompa hidrolik, 3 pengecekan per shift',
  icon: Icons.oil_barrel_outlined,
  units: const <DailyCheckUnit>[_feeder1, _feeder2],
  hasUnitStatus: true,
  entryHint:
      'Pantau suhu dan tekanan setiap 4 jam. Isi keterangan bila ditemukan '
      'gejala kerusakan pada unit.',
  sections: const <DailyCheckSection>[
    DailyCheckSection('Pemantauan suhu', <DailyCheckField>[
      DailyCheckField(
        'ambient',
        'Ambient temp',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'main_pump',
        'Main pump',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'hydraulic_motor',
        'Hydraulic motor',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'flushing_p1',
        'Flushing valve P1',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'flushing_p2',
        'Flushing valve P2',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'flushing_t',
        'Flushing valve T',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'heat_exchanger_a',
        'Heat exchanger A',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'heat_exchanger_b',
        'Heat exchanger B',
        kind: DailyCheckValueKind.temperature,
      ),
      DailyCheckField(
        'heat_exchanger_c',
        'Heat exchanger C',
        kind: DailyCheckValueKind.temperature,
      ),
    ]),
    DailyCheckSection('Pemantauan tekanan', <DailyCheckField>[
      DailyCheckField('forward', 'Forward', kind: DailyCheckValueKind.pressure),
      DailyCheckField('charge', 'Charge', kind: DailyCheckValueKind.pressure),
      DailyCheckField('case', 'Case', kind: DailyCheckValueKind.pressure),
      DailyCheckField('vacuum', 'Vacuum', kind: DailyCheckValueKind.pressure),
    ]),
    DailyCheckSection('Kecepatan', <DailyCheckField>[
      DailyCheckField(
        'speed',
        'Feeder speed',
        kind: DailyCheckValueKind.speed,
        required: false,
      ),
    ]),
  ],
  slotsForShift: (String? shiftCode) {
    // Printed on the paper form: day 10:00, 14:00, 18:00; night 22:00,
    // 02:00, 06:00.
    final times = shiftCode == 'MALAM'
        ? const <String>['22:00', '02:00', '06:00']
        : const <String>['10:00', '14:00', '18:00'];
    const numerals = <String>['I', 'II', 'III'];
    return <DailyCheckSlot>[
      for (var i = 0; i < 3; i++)
        DailyCheckSlot(
          key: 'check_${i + 1}',
          label: 'Pengecekan ${numerals[i]}',
          shortLabel: numerals[i],
          plannedTime: times[i],
        ),
    ];
  },
);

final DailyCheckForm coalValveForm = DailyCheckForm(
  type: DailyCheckFormType.coalValve,
  title: 'Temperature Coal Valve',
  printBackground: 'assets/forms/coal_valve_form.png',
  description: 'Suhu RV01–RV04 di sisi Barat, Timur, Utara, dan Selatan',
  icon: Icons.local_fire_department_outlined,
  units: const <DailyCheckUnit>[
    DailyCheckUnit('west', 'Sisi Barat'),
    DailyCheckUnit('east', 'Sisi Timur'),
    DailyCheckUnit('north', 'Sisi Utara'),
    DailyCheckUnit('south', 'Sisi Selatan'),
  ],
  hasUnitStatus: false,
  entryHint:
      'Tembak setiap sisi coal valve. Jam pembacaan tercatat otomatis saat '
      'pertama kali disimpan.',
  sections: const <DailyCheckSection>[
    DailyCheckSection('Suhu coal valve', <DailyCheckField>[
      DailyCheckField('rv01', 'RV01', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv02', 'RV02', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv03', 'RV03', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv04', 'RV04', kind: DailyCheckValueKind.temperature),
    ]),
  ],
  // The printed form shows four time blocks (its other rows are hidden)
  // without printed times.
  slotsForShift: (_) => <DailyCheckSlot>[
    for (var i = 1; i <= coalValveReadings; i++)
      DailyCheckSlot(
        key: 'reading_$i',
        label: 'Pembacaan $i',
        shortLabel: '$i',
      ),
  ],
);
