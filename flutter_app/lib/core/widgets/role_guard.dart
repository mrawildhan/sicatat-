import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../features/auth/application/current_user_provider.dart';
import 'app_navigation.dart';

class RoleGuard extends ConsumerWidget {
  const RoleGuard({required this.allowed, required this.child, super.key});
  final Set<UserRole> allowed;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(currentUserProvider);
    if (user != null && allowed.contains(user.role)) return child;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(title: const Text('Access restricted')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, size: 46),
                const SizedBox(height: 14),
                const Text(
                  'You do not have permission to access this page.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
