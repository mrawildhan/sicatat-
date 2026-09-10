import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/operational_budget_models.dart';
import 'package:sicatat_flutter/features/operations/presentation/budget_item_sections.dart';
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

  testWidgets('rincian realisasi dan anggaran dapat dibuka', (tester) async {
    final OperationalBudgetSummary summary = OperationalBudgetSummary(
      <OperationalBudgetMonth>[
        OperationalBudgetMonth(
          site: 'CPP',
          period: DateTime(2026, 1),
          budgetUsd: 1500,
          actualUsd: 900,
          syncedAt: DateTime(2026, 9, 10),
        ),
      ],
    );
    final OperationalBudgetItem item = OperationalBudgetItem(
      site: 'CPP',
      accountCode: '00396',
      description: 'MINOR EQUIPMENT',
      budgetUsd: 9000,
      actualUsd: 4674,
      budgetMonths: const <String, double>{'202601': 1500},
      actualMonths: const <String, double>{'202601': 900},
      peakPeriod: '202601',
      peakActualUsd: 900,
      largestTransactionUsd: 500,
      largestTransactionDate: DateTime(2026, 1, 2),
      largestTransactionNo: 'TRX-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: <Widget>[
                FilledButton(
                  onPressed: () => showBudgetMonthlyDetail(context, summary),
                  child: const Text('Buka bulanan'),
                ),
                FilledButton(
                  onPressed: () async {
                    final OperationalBudgetItem? selected =
                        await showBudgetItemBrowser(
                          context,
                          <OperationalBudgetItem>[item],
                        );
                    if (selected != null && context.mounted) {
                      await showBudgetItemDetail(context, selected);
                    }
                  },
                  child: const Text('Buka rincian'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka bulanan'));
    await tester.pumpAndSettle();
    expect(find.text('Realisasi per bulan'), findsOneWidget);
    expect(find.text('Januari 2026'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka rincian'));
    await tester.pumpAndSettle();
    expect(find.text('Rincian anggaran'), findsOneWidget);
    await tester.tap(find.textContaining('00396'));
    await tester.pumpAndSettle();
    expect(find.text('MINOR EQUIPMENT'), findsOneWidget);
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
