/// Supabase configuration that reads values from compile-time environment.
///
/// Provide values via --dart-define when running or building, for example:
///   flutter run \
///     --dart-define=SUPABASE_URL=... \
///     --dart-define=SUPABASE_ANON_KEY=...
import 'supabase_local.dart';

class SupabaseConfig {
  // Supabase project credentials from environment; fall back to local file if
  // not provided via --dart-define. The local file is intended for development
  // only and should NOT be committed with secrets.
  static const String url = String.fromEnvironment('SUPABASE_URL', defaultValue: SupabaseLocal.url);
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: SupabaseLocal.anonKey);

  /// Returns true if both SUPABASE_URL and SUPABASE_ANON_KEY were provided.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// Helpful message to show when config is missing.
  static String get missingConfigMessage {
    if (isConfigured) return '';
    return 'Supabase configuration missing. Provide SUPABASE_URL and SUPABASE_ANON_KEY to the app via --dart-define or set them in your CI/build environment. Example:\n'
        'flutter run --dart-define=SUPABASE_URL=<your_supabase_url> --dart-define=SUPABASE_ANON_KEY=<your_anon_key>';
  }

  // Configuration options
  static const bool enableDebug = false;
}
