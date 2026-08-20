import 'sicatat_types.dart';

enum InspectionSection { gearboxBreaker, gearboxSizer }

enum UnitOperationalStatus { operating, notOperating, notAccessible }

class RoundModel {
  const RoundModel({
    required this.id,
    required this.clientUuid,
    required this.sheetId,
    required this.section,
    required this.roundNumber,
    required this.syncStatus,
    this.inspectedAt,
  });

  final String id;
  final String clientUuid;
  final String sheetId;
  final InspectionSection section;
  final int roundNumber;
  final DateTime? inspectedAt;
  final String syncStatus;

  factory RoundModel.fromLocalRow(JsonMap row) => RoundModel(
    id: row.requiredString('id'),
    clientUuid: row.requiredString('client_uuid'),
    sheetId: row.requiredString('sheet_id'),
    section: InspectionSectionX.fromStorage(row.requiredString('section')),
    roundNumber: row.requiredInt('round_number'),
    inspectedAt: _parseOptionalDate(row.optionalString('jam')),
    syncStatus: row.requiredString('sync_status'),
  );
}

class UnitStatusModel {
  const UnitStatusModel({
    required this.id,
    required this.clientUuid,
    required this.roundId,
    required this.status,
    required this.answeredAt,
    required this.syncStatus,
    this.unitCode,
    this.equipmentId,
    this.reason,
  });

  final String id;
  final String clientUuid;
  final String roundId;
  final String? unitCode;
  final String? equipmentId;
  final UnitOperationalStatus status;
  final String? reason;
  final DateTime answeredAt;
  final String syncStatus;

  factory UnitStatusModel.fromLocalRow(JsonMap row) => UnitStatusModel(
    id: row.requiredString('id'),
    clientUuid: row.requiredString('client_uuid'),
    roundId: row.requiredString('round_id'),
    unitCode: row.optionalString('unit_code'),
    equipmentId: row.optionalString('equipment_id'),
    status: UnitOperationalStatusX.fromStorage(row.requiredString('status')),
    reason: row.optionalString('reason'),
    answeredAt: DateTime.parse(row.requiredString('answered_at')),
    syncStatus: row.requiredString('sync_status'),
  );
}

class TemperatureReadingCommand {
  const TemperatureReadingCommand({
    required this.roundId,
    required this.measurementPointId,
    required this.recordedBy,
    required this.value,
    this.unitStatusId,
    this.measuredAt,
  });

  final String roundId;
  final String? unitStatusId;
  final String measurementPointId;
  final String recordedBy;
  final double value;
  final DateTime? measuredAt;
}

class ReadingCommand {
  const ReadingCommand({
    required this.roundId,
    required this.measurementPointId,
    required this.recordedBy,
    this.unitStatusId,
    this.valueNumeric,
    this.valueBoolean,
    this.valueText,
    this.measuredAt,
    this.isAnomaly = false,
    this.anomalyNote,
  }) : assert(
         valueNumeric != null || valueBoolean != null || valueText != null,
         'A reading needs a value.',
       );

  final String roundId;
  final String? unitStatusId;
  final String measurementPointId;
  final String recordedBy;
  final double? valueNumeric;
  final bool? valueBoolean;
  final String? valueText;
  final DateTime? measuredAt;
  final bool isAnomaly;
  final String? anomalyNote;
}

class FieldReadingValue {
  const FieldReadingValue({this.numeric, this.boolean, this.text});

  final double? numeric;
  final bool? boolean;
  final String? text;

  bool get hasValue => numeric != null || boolean != null || text != null;
}

extension InspectionSectionX on InspectionSection {
  static InspectionSection fromStorage(String value) => switch (value) {
    'gearbox_breaker' => InspectionSection.gearboxBreaker,
    'gearbox_sizer' => InspectionSection.gearboxSizer,
    _ => throw FormatException('Unknown inspection section: $value'),
  };

  String get storageValue => switch (this) {
    InspectionSection.gearboxBreaker => 'gearbox_breaker',
    InspectionSection.gearboxSizer => 'gearbox_sizer',
  };
}

extension UnitOperationalStatusX on UnitOperationalStatus {
  static UnitOperationalStatus fromStorage(String value) => switch (value) {
    'beroperasi' => UnitOperationalStatus.operating,
    'tidak_beroperasi' => UnitOperationalStatus.notOperating,
    'tidak_dapat_diakses' => UnitOperationalStatus.notAccessible,
    _ => throw FormatException('Unknown unit status: $value'),
  };

  String get storageValue => switch (this) {
    UnitOperationalStatus.operating => 'beroperasi',
    UnitOperationalStatus.notOperating => 'tidak_beroperasi',
    UnitOperationalStatus.notAccessible => 'tidak_dapat_diakses',
  };
}

DateTime? _parseOptionalDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toLocal();
  // A legacy installation could contain a time-only value (HH:mm). It has no
  // date context here, so do not crash the form; saving a draft replaces it
  // with the current round's full timestamp before it is synced.
  return null;
}

class ExpectedSide {
  const ExpectedSide({
    required this.section,
    required this.roundNumber,
    required this.unitCode,
  });

  final InspectionSection section;
  final int roundNumber;
  final String unitCode;

  String get label {
    final sectionLabel = section == InspectionSection.gearboxBreaker
        ? 'Gearbox Breaker'
        : 'Gearbox Sizer';
    final sideLabel = unitCode == 'BARAT' ? 'West' : 'East';
    return '$sectionLabel • Round $roundNumber • $sideLabel';
  }
}

const expectedSides = <ExpectedSide>[
  ExpectedSide(
    section: InspectionSection.gearboxBreaker,
    roundNumber: 1,
    unitCode: 'BARAT',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxBreaker,
    roundNumber: 1,
    unitCode: 'TIMUR',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxSizer,
    roundNumber: 1,
    unitCode: 'BARAT',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxSizer,
    roundNumber: 1,
    unitCode: 'TIMUR',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxBreaker,
    roundNumber: 2,
    unitCode: 'BARAT',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxBreaker,
    roundNumber: 2,
    unitCode: 'TIMUR',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxSizer,
    roundNumber: 2,
    unitCode: 'BARAT',
  ),
  ExpectedSide(
    section: InspectionSection.gearboxSizer,
    roundNumber: 2,
    unitCode: 'TIMUR',
  ),
];
