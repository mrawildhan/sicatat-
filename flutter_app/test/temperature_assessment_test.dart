import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/master_data_models.dart';

void main() {
  const point = MeasurementPoint(
    id: 'motor-de',
    code: 'motor_de',
    label: 'Motor DE',
    dataType: 'numeric',
    unit: '°C',
  );

  test('uses configured warning and alarm thresholds per point', () {
    const config = InspectionFormConfig(
      equipment: <InspectionEquipment>[],
      measurementPoints: <MeasurementPoint>[point],
      thresholds: <ThresholdRule>[
        ThresholdRule(
          measurementPointId: 'motor-de',
          warningMin: 55,
          alarmMin: 65,
        ),
      ],
    );

    expect(
      config.assessTemperature(point, 54).level,
      TemperatureAlertLevel.normal,
    );
    expect(
      config.assessTemperature(point, 55).level,
      TemperatureAlertLevel.warning,
    );
    expect(
      config.assessTemperature(point, 65).level,
      TemperatureAlertLevel.critical,
    );
  });

  test('rejects temperatures outside a plausible physical range', () {
    const config = InspectionFormConfig(
      equipment: <InspectionEquipment>[],
      measurementPoints: <MeasurementPoint>[point],
      thresholds: <ThresholdRule>[],
    );

    expect(
      config.assessTemperature(point, 6363).level,
      TemperatureAlertLevel.invalid,
    );
  });

  test(
    'active master equipment and points are rendered without a code whitelist',
    () {
      const config = InspectionFormConfig(
        equipment: <InspectionEquipment>[
          InspectionEquipment(
            id: 'new-equipment',
            code: 'added_later',
            name: 'Added later',
            section: 'gearbox_breaker',
            sortOrder: 99,
          ),
        ],
        measurementPoints: <MeasurementPoint>[
          MeasurementPoint(
            id: 'new-point',
            code: 'bearing_new',
            label: 'New bearing',
            equipmentId: 'new-equipment',
            dataType: 'numeric',
            unit: '°C',
          ),
        ],
        thresholds: <ThresholdRule>[],
      );

      expect(config.equipmentFor('gearbox_breaker').single.code, 'added_later');
      expect(
        config.pointsForEquipment('new-equipment').single.code,
        'bearing_new',
      );
    },
  );

  test('keeps oil level only on the feeder breaker and sizer motor', () {
    const feeder = InspectionEquipment(
      id: 'feeder',
      code: 'feeder_breaker',
      name: 'Feeder Breaker',
      section: 'gearbox_breaker',
      sortOrder: 1,
    );
    const pump = InspectionEquipment(
      id: 'pump',
      code: 'hydraulic_pump_1',
      name: 'Hydraulic Pump 1',
      section: 'gearbox_breaker',
      sortOrder: 2,
    );
    const sizerMotor = InspectionEquipment(
      id: 'sizer-motor',
      code: 'motor',
      name: 'Motor',
      section: 'gearbox_sizer',
      sortOrder: 1,
    );
    const config = InspectionFormConfig(
      equipment: <InspectionEquipment>[feeder, pump, sizerMotor],
      measurementPoints: <MeasurementPoint>[
        MeasurementPoint(
          id: 'feeder-oil',
          code: 'oil_level',
          label: 'Oil level',
          equipmentId: 'feeder',
          dataType: 'boolean',
        ),
        MeasurementPoint(
          id: 'pump-oil',
          code: 'oil_level',
          label: 'Oil level',
          equipmentId: 'pump',
          dataType: 'boolean',
        ),
        MeasurementPoint(
          id: 'sizer-oil',
          code: 'oil_level',
          label: 'Oil level',
          equipmentId: 'sizer-motor',
          dataType: 'boolean',
        ),
      ],
      thresholds: <ThresholdRule>[],
    );

    expect(config.visiblePointsForEquipment(feeder), hasLength(1));
    expect(config.visiblePointsForEquipment(pump), isEmpty);
    expect(config.visiblePointsForEquipment(sizerMotor), hasLength(1));
  });

  test('normalizes legacy Indonesian shift names for the English UI', () {
    expect(displayShiftName('Pagi'), 'Day shift');
    expect(displayShiftName('Shift Malam'), 'Night shift');
    expect(displayShiftName('Custom shift'), 'Custom shift');
  });
}
