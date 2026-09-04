import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Keeps every top-level page reachable when it was opened with `context.go`.
///
/// GoRouter replaces the current location for those links, so Android's system
/// Back button has no route to pop. Pages wrap their scaffold in [AppBackScope]
/// and provide a meaningful in-app destination instead of closing the app.
class AppBackScope extends StatelessWidget {
  const AppBackScope({
    required this.fallbackRoute,
    required this.child,
    super.key,
  });

  final String fallbackRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go(fallbackRoute);
    },
    child: child,
  );
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({required this.fallbackRoute, super.key});

  final String fallbackRoute;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Kembali',
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: () => context.go(fallbackRoute),
  );
}
