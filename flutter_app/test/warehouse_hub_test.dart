import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sicatat_flutter/data/models/app_user.dart';
import 'package:sicatat_flutter/features/auth/application/current_user_provider.dart';
import 'package:sicatat_flutter/features/warehouse/presentation/warehouse_hub_screen.dart';

Future<void> _pumpHub(WidgetTester tester, UserRole role) async {
  final GoRouter router = GoRouter(
    initialLocation: '/warehouse',
    routes: <RouteBase>[
      GoRoute(
        path: '/warehouse',
        builder: (_, __) => const WarehouseHubScreen(),
      ),
      GoRoute(
        path: '/warehouse/search',
        builder: (_, __) => const Scaffold(body: Text('HALAMAN CARI')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => AppUser(
            id: '1',
            nik: '1',
            name: 'Uji',
            role: role,
            isActive: true,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('crew hanya melihat Cari barang, tidak langsung pencarian', (
    tester,
  ) async {
    await _pumpHub(tester, UserRole.crew);
    expect(find.text('Cari barang'), findsOneWidget);
    expect(find.text('Pengambilan Barang'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Cari barang'));
    await tester.pumpAndSettle();
    expect(find.text('HALAMAN CARI'), findsOneWidget);
  });

  testWidgets('pengelola gudang melihat semua transaksi', (tester) async {
    await _pumpHub(tester, UserRole.warehouseman);
    for (final String title in <String>[
      'Cari barang',
      'Pengambilan Barang',
      'Peminjaman Alat',
      'Penerimaan Barang',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });
}
