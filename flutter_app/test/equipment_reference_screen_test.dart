import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/documents/presentation/equipment_reference_screen.dart';

void main() {
  testWidgets('equipment reference mencari unit dari workbook Asam-Asam', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: EquipmentReferenceScreen()),
    );

    expect(find.text('Cari equipment'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ADS01');
    await tester.pump();

    expect(find.text('ADS01'), findsNWidgets(2));
    expect(find.text('DUMP STATION 01 ASAM-ASAM'), findsOneWidget);
  });
}
