import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/platform/local_database_setup.dart';
import 'data/sync/sync_coordinator.dart';
import 'data/sync/sync_service.dart';

SyncCoordinator? _syncCoordinator;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureLocalDatabaseForPlatform();
  // Android 15 draws applications edge-to-edge by default. Every screen owns
  // its safe area, while this sets a predictable default for the system bars.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  if (AppConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    // Retry queues left by both Flutter and legacy Capacitor applications on
    // launch, after connectivity returns, and once per minute while open.
    _syncCoordinator = SyncCoordinator(SyncService(Supabase.instance.client));
    _syncCoordinator!.start();
  }
  runApp(const ProviderScope(child: SicatatApp()));
}
