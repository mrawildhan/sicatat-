import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'sicatat_repository.dart';
import 'supabase_sicatat_repository.dart';

final sicatatRepositoryProvider = Provider<SicatatRepository>((ref) {
  if (!AppConfig.isSupabaseConfigured) {
    throw StateError('Konfigurasi server belum tersedia di aplikasi ini.');
  }
  return SupabaseSicatatRepository(Supabase.instance.client);
});
