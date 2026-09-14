import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/local/local_database.dart';

void main() {
  test('local SQLite values drop nulls and store booleans as 0/1', () {
    final values = LocalDatabase.sqliteValues(<String, Object?>{
      'id': 'reading-1',
      'value_boolean': true,
      'is_anomaly': false,
      'value_numeric': 62.5,
      'anomaly_note': null,
    });

    expect(values, <String, Object?>{
      'id': 'reading-1',
      'value_boolean': 1,
      'is_anomaly': 0,
      'value_numeric': 62.5,
    });
    expect(values.values.whereType<bool>(), isEmpty);
  });
}
