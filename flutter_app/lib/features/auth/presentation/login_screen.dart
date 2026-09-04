import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../data/repositories/repository_providers.dart';
import '../application/current_user_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nik = TextEditingController();
  final _pin = TextEditingController();
  final _scrollController = ScrollController(keepScrollOffset: false);
  bool _obscure = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Never reopen the login screen at the position left by the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final user = await ref.read(sicatatRepositoryProvider).restoreSession();
      if (user == null || !mounted) return;
      ref.read(currentUserProvider.notifier).state = user;
      context.go('/dashboard');
    } catch (_) {
      // First-run, offline, and configuration failures should leave the crew
      // at the sign-in screen without exposing transport details.
    }
  }

  @override
  void dispose() {
    _nik.dispose();
    _pin.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = await ref
          .read(sicatatRepositoryProvider)
          .signIn(nik: _nik.text, pin: _pin.text);
      ref.read(currentUserProvider.notifier).state = user;
      if (mounted) context.go('/dashboard');
    } on FormatException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message.toString());
    } on StateError {
      if (mounted) {
        setState(
          () => _errorMessage =
              'The application is not configured to connect to the server.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Unable to sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) {},
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 42, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logo-full.png',
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to',
                        style: TextStyle(fontSize: 18, color: AppColors.muted),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'sicatat',
                        style: TextStyle(
                          fontSize: 40,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: AppColors.greenDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Field data recording application',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Masuk ke akun crew Anda',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _nik,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        enabled: !_isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Crew ID / NIK',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _pin,
                        obscureText: _obscure,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        enabled: !_isSubmitting,
                        autofillHints: const <String>[AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        onSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_errorMessage case final message?) ...[
                        const SizedBox(height: 14),
                        Text(
                          message,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _signIn,
                        icon: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          _isSubmitting ? 'Memeriksa akun...' : 'Masuk',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          'Version ${AppConfig.appVersion} • Online-only',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
