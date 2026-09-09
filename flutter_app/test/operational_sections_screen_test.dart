import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  testWidgets('outstanding memisahkan PM crew lokasi dan CM global', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OutstandingMaintenanceScreen()),
    );
    await tester.pump();

    expect(find.text('PM'), findsOneWidget);
    expect(find.text('CM'), findsOneWidget);
    expect(find.text('CPP'), findsOneWidget);
    expect(find.text('PORT'), findsOneWidget);
    expect(find.text('Crew A'), findsNWidgets(2));
    expect(find.text('Crew B'), findsNWidgets(2));
    expect(find.text('Crew C'), findsNWidgets(2));
    expect(find.textContaining('CM CPP'), findsOneWidget);
    expect(find.textContaining('CM PORT'), findsOneWidget);

    await tester.tap(find.text('Crew A').first);
    await tester.pumpAndSettle();

    expect(find.text('PM Crew A · CPP'), findsOneWidget);
    expect(
      find.text('Tidak ada PM outstanding untuk crew dan lokasi ini.'),
      findsOneWidget,
    );
  });
}
