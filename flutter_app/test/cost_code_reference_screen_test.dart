import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/documents/presentation/cost_code_reference_screen.dart';

void main() {
  testWidgets('struktur cost code membuka angka sesuai segmen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CostCodeReferenceScreen()));

    expect(find.text('Struktur cost code'), findsOneWidget);
    expect(find.text('Expense element'), findsOneWidget);

    await tester.tap(find.text('Site').first);
    await tester.pumpAndSettle();

    expect(find.text('2 digit · 2 kode tersedia'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(find.text('Asam Asam'), findsOneWidget);
  });
}
