class AppConfig {
  static const appVersion = '2.1.5';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ofczleeyqrxyuuupzirq.supabase.co',
  );
  // A Supabase publishable key is intentionally embedded in mobile clients;
  // it is not a service-role secret. This value preserves the working legacy
  // application's connection while --dart-define can still override it.
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_e85vPiEENe19yCviVUzuLg_nTewJBSW',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
