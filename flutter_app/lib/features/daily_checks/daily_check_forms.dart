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
  running('running', 'Running', Icons.check_circle_outline),
  notRunning('not_running', 'Not running', Icons.pause_circle_outline),
  notAccessible('not_accessible', 'Not accessible', Icons.block_outlined);

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
    DailyCheckValueKind.pressure => null,
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

/// One time on the paper form: Check I/II/III, or one coal valve reading.
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
    required this.printTitle,
    required this.description,
    required this.icon,
    required this.units,
    required this.sections,
    required this.hasUnitStatus,
    required this.unitsAreColumns,
    required this.slotsForShift,
    required this.entryHint,
  });

  final DailyCheckFormType type;
  final String title;
  final String printTitle;
  final String description;
  final IconData icon;
  final List<DailyCheckUnit> units;
  final List<DailyCheckSection> sections;

  /// Feeders can be stopped; each check records whether they were running.
  final bool hasUnitStatus;

  /// Hydraulic: fields are rows and feeders are columns. Coal valve: sides
  /// are rows and valves (fields) are columns.
  final bool unitsAreColumns;
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

/// App-wide temperature bands: 60–69 °C warning, 70 °C and above critical.
enum DailyCheckTemperatureLevel { normal, warning, critical }

DailyCheckTemperatureLevel temperatureLevel(double value) => value >= 70
    ? DailyCheckTemperatureLevel.critical
    : value >= 60
    ? DailyCheckTemperatureLevel.warning
    : DailyCheckTemperatureLevel.normal;

/// Readings outside this range are almost certainly typing mistakes.
const double minPlausibleTemperature = -50;
const double maxPlausibleTemperature = 250;

const _feeder1 = DailyCheckUnit('f1', 'Feeder 1');
const _feeder2 = DailyCheckUnit('f2', 'Feeder 2');

final DailyCheckForm hydraulicFeederForm = DailyCheckForm(
  type: DailyCheckFormType.hydraulicFeeder,
  title: 'Daily Check Sheet Hydraulic Feeder',
  printTitle: 'DAILY CHECK SHEET HYDRAULIC PUMP FEEDER CPP',
  description: 'Hydraulic pump temperature & pressure, 3 checks per shift',
  icon: Icons.oil_barrel_outlined,
  units: const <DailyCheckUnit>[_feeder1, _feeder2],
  hasUnitStatus: true,
  unitsAreColumns: true,
  entryHint:
      'Monitor temperature and pressure every 4 hours. Write a remark if you '
      'find any sign of damage on the unit.',
  sections: const <DailyCheckSection>[
    DailyCheckSection('Monitoring temperature', <DailyCheckField>[
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
    DailyCheckSection('Monitoring pressure', <DailyCheckField>[
      DailyCheckField('forward', 'Forward', kind: DailyCheckValueKind.pressure),
      DailyCheckField('charge', 'Charge', kind: DailyCheckValueKind.pressure),
      DailyCheckField('case', 'Case', kind: DailyCheckValueKind.pressure),
      DailyCheckField('vacuum', 'Vacuum', kind: DailyCheckValueKind.pressure),
    ]),
    DailyCheckSection('Speed', <DailyCheckField>[
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
    const names = <String>['Check I', 'Check II', 'Check III'];
    return <DailyCheckSlot>[
      for (var i = 0; i < 3; i++)
        DailyCheckSlot(
          key: 'check_${i + 1}',
          label: names[i],
          shortLabel: 'C${i + 1}',
          plannedTime: times[i],
        ),
    ];
  },
);

final DailyCheckForm coalValveForm = DailyCheckForm(
  type: DailyCheckFormType.coalValve,
  title: 'Temperature Coal Valve',
  printTitle: 'DATA TEMPERATURE COAL VALVE',
  description: 'RV01–RV04 on the west, east, north & south sides',
  icon: Icons.local_fire_department_outlined,
  units: const <DailyCheckUnit>[
    DailyCheckUnit('west', 'West side'),
    DailyCheckUnit('east', 'East side'),
    DailyCheckUnit('north', 'North side'),
    DailyCheckUnit('south', 'South side'),
  ],
  hasUnitStatus: false,
  unitsAreColumns: false,
  entryHint:
      'Shoot each side of every coal valve. The reading time is recorded '
      'automatically when you first save it.',
  sections: const <DailyCheckSection>[
    DailyCheckSection('Coal valve temperature', <DailyCheckField>[
      DailyCheckField('rv01', 'RV01', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv02', 'RV02', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv03', 'RV03', kind: DailyCheckValueKind.temperature),
      DailyCheckField('rv04', 'RV04', kind: DailyCheckValueKind.temperature),
    ]),
  ],
  // The paper form has ten time rows without printed times.
  slotsForShift: (_) => <DailyCheckSlot>[
    for (var i = 1; i <= 10; i++)
      DailyCheckSlot(key: 'reading_$i', label: 'Reading $i', shortLabel: '$i'),
  ],
);
