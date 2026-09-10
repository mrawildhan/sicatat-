import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/operations/presentation/operational_sections_screen.dart';

void main() {
  testWidgets('anggaran menampilkan keadaan data belum tersedia', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BudgetOverviewScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Anggaran Operasional'), findsOneWidget);
    expect(find.text('Anggaran belum dapat dimuat'), findsOneWidget);
    expect(
      find.text('Data anggaran Asam-Asam belum tersedia.'),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsOneWidget);
  });

  testWidgets('tampilan awal MOM menjelaskan alur draf', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MeetingMinutesScreen()));

    expect(find.text('Notulen Rapat'), findsOneWidget);
    expect(find.text('Belum ada notulen'), findsOneWidget);
    expect(find.text('Draf  0'), findsOneWidget);
    expect(find.text('Buat notulen'), findsOneWidget);
  });

  testWidgets('permintaan barang dapat difilter dari ringkasan status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MaterialRequestOverviewScreen()),
      ),
    );

    expect(find.text('Butuh barang atau alat?'), findsNothing);
    expect(find.text('Ringkasan status'), findsOneWidget);
    expect(find.text('Diajukan'), findsOneWidget);
    expect(find.text('Diproses'), findsOneWidget);
    expect(find.text('Ditolak'), findsOneWidget);
    expect(find.text('Ajukan kebutuhan barang'), findsOneWidget);
    expect(find.text('Pengajuan saya'), findsOneWidget);

    await tester.tap(find.text('Diproses'));
    await tester.pump();

    expect(find.text('Pengajuan: Diproses'), findsOneWidget);
    expect(find.text('Semua'), findsOneWidget);
  });

  testWidgets(
    'outstanding membuka crew PM dan lokasi CM sebagai section penuh',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: OutstandingMaintenanceScreen()),
      );
      await tester.pump();

      expect(find.text('PM per crew & lokasi'), findsOneWidget);
      expect(find.text('CPP'), findsOneWidget);
      expect(find.text('PORT'), findsOneWidget);
      expect(find.text('Crew A'), findsNWidgets(2));
      expect(find.text('Crew B'), findsNWidgets(2));
      expect(find.text('Crew C'), findsNWidgets(2));
      expect(find.text('CM CPP'), findsOneWidget);
      expect(find.text('CM PORT'), findsOneWidget);

      await tester.tap(find.text('Crew A').first);
      await tester.pumpAndSettle();

      expect(find.text('PM Crew A · CPP'), findsOneWidget);
      expect(
        find.text('Tidak ada PM outstanding yang sesuai pencarian.'),
        findsOneWidget,
      );
    },
  );
}
