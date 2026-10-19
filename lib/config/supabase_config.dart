import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Build-time Supabase configuration.
///
/// Use `--dart-define-from-file=supabase.env.json`. Only the publishable key
/// belongs in a Flutter build; secret/service-role keys must stay server-side.
abstract final class SupabaseConfig {
  static AuthChangeEvent? _startupAuthEvent;

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static bool get isConfigured =>
      url.startsWith('https://') &&
      url.endsWith('.supabase.co') &&
      publishableKey.startsWith('sb_publishable_');

  /// Returns the auth callback received while Supabase was starting, if any.
  ///
  /// Supabase processes a cold-start deep link before [runApp], so the app's
  /// normal auth listener cannot observe that event directly.
  static AuthChangeEvent? takeStartupAuthEvent() {
    final event = _startupAuthEvent;
    _startupAuthEvent = null;
    return event;
  }

  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'Supabase configuration is missing or invalid. Provide an HTTPS '
        'SUPABASE_URL and an sb_publishable_ SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    final initialization = Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
    );

    // Supabase creates its client synchronously before it begins restoring
    // storage and processing the initial deep link. Subscribe during that
    // window so cold-start OAuth and recovery callbacks are not lost.
    final startupSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((state) {
          if (state.event == AuthChangeEvent.passwordRecovery ||
              state.event == AuthChangeEvent.signedIn) {
            _startupAuthEvent = state.event;
          }
        });
    try {
      await initialization;
    } finally {
      await startupSubscription.cancel();
    }
  }
}
