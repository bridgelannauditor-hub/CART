import 'package:supabase_flutter/supabase_flutter.dart';

/// Build-time Supabase configuration.
///
/// Use `--dart-define-from-file=supabase.env.json`. Only the publishable key
/// belongs in a Flutter build; secret/service-role keys must stay server-side.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      url.startsWith('https://') && publishableKey.startsWith('sb_publishable_');

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}
