import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/core/widgets/source_update_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('kartu pembaruan: judul dan tanggal diperbarui 24 jam', (
    tester,
  ) async {
    int refreshed = 0;
    await tester.pumpWidget(
      _wrap(
        SourceUpdateCard(
          title: 'Pembaruan data PR',
          updatedAt: DateTime(2026, 9, 24, 14, 13),
          checking: false,
          onRefresh: () => refreshed++,
        ),
      ),
    );
    expect(find.text('Pembaruan data PR'), findsOneWidget);
    expect(find.text('Terakhir diperbarui 24/9/26 14.13'), findsOneWidget);
    // Two lines only: the title and the update time.
    expect(find.byType(Text), findsNWidgets(2));
    await tester.tap(find.byTooltip('Periksa ulang'));
    expect(refreshed, 1);
  });

  testWidgets('kartu pembaruan: sedang memeriksa dan gagal', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SourceUpdateCard(
          title: 'Pembaruan data Gudang',
          checking: true,
          onRefresh: _noop,
        ),
      ),
    );
    expect(find.text('Memeriksa pembaruan…'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );

    await tester.pumpWidget(
      _wrap(
        const SourceUpdateCard(
          title: 'Pembaruan data Gudang',
          checking: false,
          error: 'HTTP 404',
        ),
      ),
    );
    expect(find.text('Gagal memeriksa: HTTP 404'), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
  });
}

void _noop() {}
