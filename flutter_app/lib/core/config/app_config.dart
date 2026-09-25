class AppConfig {
  static const appVersion = '2.8.43';

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

  /// Folder publik yang menjadi satu-satunya ruang lingkup Pusat Dokumen.
  /// Ini bukan kredensial; pemrosesan AI dan kunci model berada di server.
  static const technicalDocumentsFolderUrl = String.fromEnvironment(
    'TECHNICAL_DOCUMENTS_FOLDER_URL',
    defaultValue: 'https://drive.google.com/drive/folders/1Mrt4ND-wPgkfmCngbmTfHBwyAo1oclxp?usp=sharing',
  );

  /// Worker Cloudflare Major Job (D1 + KV, bukan Supabase). Aksesnya memakai
  /// token login SICATAT yang sama dan hanya menerima admin aktif.
  static const majorJobApiUrl = String.fromEnvironment(
    'MAJOR_JOB_API_URL',
    defaultValue: 'https://sicatat-major-job.sicatat.workers.dev',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
