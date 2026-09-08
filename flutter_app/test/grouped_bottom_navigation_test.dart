import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/dashboard/presentation/grouped_bottom_navigation.dart';

void main() {
  testWidgets(
    'menu referensi menyertakan gudang dan dokumen serta versi tanpa nama',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: GroupedBottomNavigation(
              selected: 'documents',
              canTemperature: true,
              canReminders: true,
              canWarehouse: true,
            ),
          ),
        ),
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.textContaining('WIL'), findsNothing);
      expect(find.textContaining('© 2026 • Versi'), findsOneWidget);
      await tester.tap(find.text('Referensi'));
      await tester.pumpAndSettle();
      expect(find.text('Gudang'), findsOneWidget);
      expect(find.text('Pusat Dokumen'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    },
  );
  testWidgets('kelompok operasional mengikuti hak akses', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GroupedBottomNavigation(
            selected: 'temperature',
            canTemperature: true,
            canReminders: false,
            canWarehouse: false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Operasional'));
    await tester.pumpAndSettle();
    expect(find.text('Suhu'), findsOneWidget);
    expect(find.text('Pengingat'), findsNothing);
  });
}
