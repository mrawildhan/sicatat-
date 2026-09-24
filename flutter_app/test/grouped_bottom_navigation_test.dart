import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/dashboard/presentation/grouped_bottom_navigation.dart';

void main() {
  testWidgets(
    'menu referensi menyertakan dokumen dan equipment serta versi tanpa nama',
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
      // Gudang moved to Operasional on 2026-09-24.
      expect(find.text('Gudang'), findsNothing);
      expect(find.text('Pusat Dokumen'), findsOneWidget);
      expect(find.text('Referensi Alat'), findsOneWidget);
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
    expect(find.text('Gudang'), findsNothing);
  });
  testWidgets('gudang ada di operasional dan menu berurutan abjad', (
    tester,
  ) async {
    // Tall enough that every card of the grid is laid out.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GroupedBottomNavigation(
            selected: 'warehouse',
            canTemperature: true,
            canReminders: true,
            canWarehouse: true,
          ),
        ),
      ),
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.text('Operasional'));
    await tester.pumpAndSettle();
    final List<String> titles = <String>[
      'Anggaran Operasional',
      'Data PR',
      'Gudang',
      'Notulen Rapat',
      'Pengingat',
      'Permintaan Barang',
      'PM & CM Tertunda',
      'Suhu',
    ];
    final List<double> tops = titles
        .map(
          (String title) => tester.getTopLeft(
            find.ancestor(of: find.text(title), matching: find.byType(Card)),
          ),
        )
        .map((Offset o) => o.dy * 10000 + o.dx)
        .toList();
    expect(tops, List<double>.of(tops)..sort());
  });
}
