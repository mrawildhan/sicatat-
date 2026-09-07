import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/operations/presentation/operational_sections_screen.dart';

void main() {
  testWidgets('tampilan awal anggaran menjelaskan sumber data', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BudgetOverviewScreen()));

    expect(find.text('Anggaran Operasional'), findsOneWidget);
    expect(find.text('Anggaran'), findsOneWidget);
    expect(find.text('Aktual'), findsOneWidget);
    expect(find.text('Sisa anggaran'), findsOneWidget);
    expect(find.text('Spreadsheet budget dan aktual'), findsOneWidget);
  });

  testWidgets('tampilan awal MOM menjelaskan alur draf', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MeetingMinutesScreen()));

    expect(find.text('Notulen Rapat'), findsOneWidget);
    expect(find.text('Belum ada notulen'), findsOneWidget);
    expect(find.text('Draf  0'), findsOneWidget);
    expect(find.text('Buat notulen'), findsOneWidget);
  });
}
