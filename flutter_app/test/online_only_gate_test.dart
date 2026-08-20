import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/core/widgets/online_only_gate.dart';

void main() {
  testWidgets('blocks the application while connection is being checked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnlineOnlyGate(
          probe: _unreachable,
          child: Scaffold(body: Text('Protected application')),
        ),
      ),
    );
    expect(find.text('Checking connection'), findsOneWidget);
    expect(find.text('Protected application'), findsOneWidget);
  });
}

Future<bool> _unreachable() async => false;
