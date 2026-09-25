import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/documents/presentation/cost_code_reference_screen.dart';

void main() {
  testWidgets('struktur cost code membuka angka sesuai segmen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CostCodeReferenceScreen()));

    expect(find.text('Struktur kode biaya'), findsOneWidget);
    expect(find.text('Expense element'), findsOneWidget);

    await tester.tap(find.text('Site').first);
    await tester.pumpAndSettle();

    // Every site from the manual, smallest code first.
    expect(find.text('2 digit · 14 kode tersedia'), findsOneWidget);
    expect(find.text('Support Office Jakarta'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('10')).dy,
      lessThan(tester.getTopLeft(find.text('11')).dy),
    );
  });
}
