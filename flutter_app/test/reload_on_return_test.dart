import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sicatat_flutter/features/daily_checks/presentation/daily_check_widgets.dart';

class _Parent extends StatefulWidget {
  const _Parent();

  @override
  State<_Parent> createState() => _ParentState();
}

int returns = 0;

class _ParentState extends State<_Parent> with ReloadOnReturn<_Parent> {
  @override
  String get ownPath => '/sheet';

  @override
  void onReturnToPage() => returns++;

  @override
  Widget build(BuildContext context) => const Text('parent');
}

void main() {
  testWidgets('a parent page reloads when its child route closes', (
    WidgetTester tester,
  ) async {
    returns = 0;
    final GoRouter router = GoRouter(
      initialLocation: '/sheet',
      routes: <RouteBase>[
        GoRoute(
          path: '/sheet',
          builder: (_, __) => const _Parent(),
          routes: <RouteBase>[
            GoRoute(path: 'entry', builder: (_, __) => const Text('entry')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(returns, 0);

    router.go('/sheet/entry');
    await tester.pumpAndSettle();
    expect(find.text('entry'), findsOneWidget);
    expect(returns, 0);

    router.go('/sheet');
    await tester.pumpAndSettle();
    expect(find.text('parent'), findsOneWidget);
    expect(returns, 1);
  });
}
