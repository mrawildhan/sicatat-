import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'sicatat_repository.dart';
import 'supabase_sicatat_repository.dart';

final sicatatRepositoryProvider = Provider<SicatatRepository>((ref) {
  if (!AppConfig.isSupabaseConfigured) {
    throw StateError(
      'Supabase configuration is not available in this application.',
    );
  }
  return SupabaseSicatatRepository(Supabase.instance.client);
});
