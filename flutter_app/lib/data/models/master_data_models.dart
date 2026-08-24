import 'field_entry_models.dart';
import 'sicatat_types.dart';

class ShiftOption {
  const ShiftOption({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  factory ShiftOption.fromJson(JsonMap json) => ShiftOption(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    name: json.requiredString('name'),
  );

  JsonMap toJson() => <String, Object?>{'id': id, 'code': code, 'name': name};
}

/// Keeps legacy Indonesian shift names in the database while presenting a
/// consistent English operational UI.
String displayShiftName(String value) {
  switch (value.trim().toLowerCase()) {
    case 'pagi':
    case 'shift pagi':
    case 'day':
    case 'day shift':
      return 'Day shift';
    case 'malam':
    case 'shift malam':
    case 'night':
    case 'night shift':
      return 'Night shift';
    default:
      return value;
  }
}

class TemperatureTemplate {
  const TemperatureTemplate({
    required this.moduleId,
    required this.version,
    this.schema,
  });

  final String moduleId;
  final String version;
  final JsonMap? schema;
}

class ThresholdRule {
  const ThresholdRule({
    required this.measurementPointId,
    this.warningMin,
    this.warningMax,
    this.alarmMin,
    this.alarmMax,
    this.deltaMaxPerRound,
  });

  final String measurementPointId;
  final double? warningMin;
  final double? warningMax;
  final double? alarmMin;
  final double? alarmMax;
  final double? deltaMaxPerRound;

  factory ThresholdRule.fromJson(JsonMap json) => ThresholdRule(
    measurementPointId: json.requiredString('measurement_point_id'),
    warningMin: _asDouble(json['warning_min']),
    warningMax: _asDouble(json['warning_max']),
    alarmMin: _asDouble(json['alarm_min']),
    alarmMax: _asDouble(json['alarm_max']),
    deltaMaxPerRound: _asDouble(json['delta_max_per_round']),
  );
}

enum TemperatureAlertLevel { normal, warning, critical, invalid }

class TemperatureAssessment {
  const TemperatureAssessment({required this.level, required this.message});

  final TemperatureAlertLevel level;
  final String message;

  bool get requiresConfirmation => level != TemperatureAlertLevel.normal;
  bool get isAnomaly => level != TemperatureAlertLevel.normal;
}

class InspectionStep {
  const InspectionStep({required this.section, required this.roundNumber});

  final InspectionSection section;
  final int roundNumber;
}

class MeasurementPoint {
  const MeasurementPoint({
    required this.id,
    required this.code,
    required this.label,
    this.equipmentId,
    this.dataType = 'number',
    this.unit,
    this.isRequired = true,
    this.sortOrder = 0,
  });

  final String id;
  final String code;
  final String label;
  final String? equipmentId;
  final String dataType;
  final String? unit;
  final bool isRequired;
  final int sortOrder;

  factory MeasurementPoint.fromJson(JsonMap json) => MeasurementPoint(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    label: json.requiredString('label'),
    equipmentId: json.optionalString('equipment_id'),
    dataType: json.optionalString('data_type') ?? 'number',
    unit: json.optionalString('unit'),
    isRequired: json['is_required'] is bool || json['is_required'] is int
        ? json.requiredBool('is_required')
        : true,
    sortOrder: json['sort_order'] is num ? json.requiredInt('sort_order') : 0,
  );

  JsonMap toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'label': label,
    'equipment_id': equipmentId,
    'data_type': dataType,
    'unit': unit,
    'is_required': isRequired,
    'sort_order': sortOrder,
  };
}

class InspectionEquipment {
  const InspectionEquipment({
    required this.id,
    required this.code,
    required this.name,
    required this.section,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String name;
  final String section;
  final int sortOrder;

  factory InspectionEquipment.fromJson(JsonMap json) => InspectionEquipment(
    id: json.requiredString('id'),
    code: json.requiredString('code'),
    name: json.requiredString('name'),
    section: json.requiredString('section'),
    sortOrder: json.requiredInt('sort_order'),
  );
}

class InspectionFormConfig {
  const InspectionFormConfig({
    required this.equipment,
    required this.measurementPoints,
    required this.thresholds,
    this.steps = defaultSteps,
  });

  final List<InspectionEquipment> equipment;
  final List<MeasurementPoint> measurementPoints;
  final List<ThresholdRule> thresholds;
  final List<InspectionStep> steps;

  static const defaultSteps = <InspectionStep>[
    InspectionStep(section: InspectionSection.gearboxBreaker, roundNumber: 1),
    InspectionStep(section: InspectionSection.gearboxSizer, roundNumber: 1),
    InspectionStep(section: InspectionSection.gearboxBreaker, roundNumber: 2),
    InspectionStep(section: InspectionSection.gearboxSizer, roundNumber: 2),
  ];

  List<InspectionEquipment> equipmentFor(String section) {
    final items = equipment
        .where((item) => item.section == section)
        .toList(growable: false);
    items.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return items;
  }

  List<MeasurementPoint> pointsForEquipment(String equipmentId) {
    final points = measurementPoints
        .where((point) => point.equipmentId == equipmentId)
        .toList(growable: false);
    points.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return points;
  }

  /// Oil level is an operational check only for the feeder breaker and the
  /// sizer motor. Hide accidental legacy oil points on pumps or other units
  /// even before the server migration deactivates them.
  List<MeasurementPoint> visiblePointsForEquipment(
    InspectionEquipment equipment,
  ) {
    return pointsForEquipment(equipment.id)
        .where((point) => !_isOilLevel(point) || _allowsOilLevel(equipment))
        .toList(growable: false);
  }

  bool _isOilLevel(MeasurementPoint point) =>
      point.code.trim().toLowerCase().contains('oil') ||
      point.label.trim().toLowerCase().contains('oil level');

  bool _allowsOilLevel(InspectionEquipment equipment) {
    final code = equipment.code.trim().toLowerCase();
    final name = equipment.name.trim().toLowerCase();
    return code == 'feeder_breaker' ||
        (equipment.section == 'gearbox_sizer' &&
            (code == 'motor' || name == 'motor'));
  }

  List<MeasurementPoint> get gearboxPoints {
    final points = measurementPoints
        .where((point) => point.equipmentId == null)
        .toList(growable: false);
    points.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    return points;
  }

  bool isRequired(MeasurementPoint point) =>
      point.isRequired && point.code != 'remark';

  ThresholdRule? thresholdFor(String measurementPointId) {
    for (final item in thresholds) {
      if (item.measurementPointId == measurementPointId) return item;
    }
    return null;
  }

  TemperatureAssessment assessTemperature(
    MeasurementPoint point,
    double value,
  ) {
    if (value < -50 || value > 250) {
      return const TemperatureAssessment(
        level: TemperatureAlertLevel.invalid,
        message: 'Outside the accepted physical range (-50 to 250 °C).',
      );
    }
    final threshold = thresholdFor(point.id);
    // Current operational thresholds are high-temperature limits. Prefer the
    // explicit minimum when configured; older master rows may only contain a
    // maximum, so retain a safe fallback for those rows.
    final alarmAtOrAbove = threshold?.alarmMin ?? threshold?.alarmMax ?? 70;
    final warningAtOrAbove =
        threshold?.warningMin ?? threshold?.warningMax ?? 60;
    if (value >= alarmAtOrAbove) {
      return const TemperatureAssessment(
        level: TemperatureAlertLevel.critical,
        message: 'Critical: exceeds the alarm threshold.',
      );
    }
    if (value >= warningAtOrAbove) {
      return const TemperatureAssessment(
        level: TemperatureAlertLevel.warning,
        message: 'Warning: outside the normal temperature range.',
      );
    }
    return const TemperatureAssessment(
      level: TemperatureAlertLevel.normal,
      message: 'Within the configured normal range.',
    );
  }
}

double? _asDouble(Object? value) => value is num
    ? value.toDouble()
    : value is String
    ? double.tryParse(value)
    : null;
