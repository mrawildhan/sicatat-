import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/app_user.dart';
import 'package:sicatat_flutter/features/admin/presentation/master_data_hub_screen.dart';
import 'package:sicatat_flutter/features/auth/application/current_user_provider.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: '1',
            nik: '1',
            name: 'Uji',
            role: UserRole.admin,
            isActive: true,
          ),
        ),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title! as Text).data!)
    .toList();

void main() {
  testWidgets('data master urut abjad, menu suhu dikelompokkan', (
    tester,
  ) async {
    await _pump(tester, const MasterDataHubScreen());
    expect(_titles(tester), <String>[
      'Ekspor rentang tanggal',
      'Jadwal regu',
      'Lokasi kerja',
      'Pengaturan suhu',
      'Pengguna',
      'Regu',
      'Shift',
      'Unggah data',
    ]);
  });

  testWidgets('pengaturan suhu berisi empat menu suhu urut abjad', (
    tester,
  ) async {
    await _pump(tester, const TemperatureSettingsHubScreen());
    expect(_titles(tester), <String>[
      'Batas & peringatan suhu',
      'Batas suhu',
      'Peralatan & titik ukur',
      'Template formulir suhu',
    ]);
  });
}
