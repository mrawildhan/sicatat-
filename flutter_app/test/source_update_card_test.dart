import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/core/widgets/source_update_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('kartu pembaruan menampilkan waktu berubah dan diperiksa', (
    tester,
  ) async {
    int refreshed = 0;
    final DateTime checked = DateTime(2026, 9, 24, 15, 5);
    await tester.pumpWidget(
      _wrap(
        SourceUpdateCard(
          title: 'Pembaruan data PM & CM',
          changes: const <String>['PM: berubah 9/9/26', 'CM: berubah 23/9/26'],
          checking: false,
          checkedAt: checked,
          onRefresh: () => refreshed++,
        ),
      ),
    );
    expect(find.text('PM: berubah 9/9/26'), findsOneWidget);
    expect(find.text('CM: berubah 23/9/26'), findsOneWidget);
    expect(find.text('Terakhir diperiksa 24/9/26 15.05'), findsOneWidget);
    await tester.tap(find.byTooltip('Periksa ulang spreadsheet'));
    expect(refreshed, 1);
  });

  testWidgets('kartu pembaruan: sedang memeriksa dan gagal', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SourceUpdateCard(
          title: 'Pembaruan data PR',
          changes: <String>[],
          checking: true,
          onRefresh: _noop,
        ),
      ),
    );
    expect(find.text('Memeriksa perubahan spreadsheet…'), findsOneWidget);
    final IconButton button = tester.widget<IconButton>(
      find.byType(IconButton),
    );
    expect(button.onPressed, isNull);

    await tester.pumpWidget(
      _wrap(
        const SourceUpdateCard(
          title: 'Pembaruan data PR',
          changes: <String>[],
          checking: false,
          error: 'HTTP 404',
        ),
      ),
    );
    expect(find.text('Pemeriksaan terakhir gagal: HTTP 404'), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
  });
}

void _noop() {}
