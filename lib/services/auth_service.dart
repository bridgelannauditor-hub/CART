import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';

/// Authentication and profile access backed by Supabase Auth + Postgres.
class AuthService {
  static const _mobileRedirect = 'io.supabase.flutter://login-callback/';
  static bool _oauthRedirectPending = false;

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final SupabaseClient _client = Supabase.instance.client;

  GoTrueClient get _auth => _client.auth;

  static bool takeOAuthRedirectPending() {
    final pending = _oauthRedirectPending;
    _oauthRedirectPending = false;
    return pending;
  }

  static void clearOAuthRedirectPending() {
    _oauthRedirectPending = false;
  }

  Future<String> register(UserModel user, {required String password}) async {
    final email = user.email.trim().toLowerCase();
    try {
      final response = await _auth.signUp(
        email: email,
        password: password.trim(),
        emailRedirectTo: kIsWeb ? null : _mobileRedirect,
        data: {
          'first_name': user.firstName.trim(),
          'last_name': user.lastName.trim(),
          'phone': user.phone?.trim(),
          'account_type': 'Customer',
          'avatar_url': user.profileImage,
        },
      );

      if (response.user == null) {
        return 'The account could not be created. Please try again.';
      }

      // Registration screens return to login. Avoid leaving an automatic
      // session active when email confirmations are disabled for development.
      if (response.session != null) await _auth.signOut();
      return 'success';
    } on AuthException catch (error) {
      return _mapAuthError(error);
    } catch (_) {
      return 'Something went wrong creating your account. Please try again.';
    }
  }

  Future<UserModel?> login(String email, String password) async {
    try {
      await _auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password.trim(),
      );
      final profile = await _loadAuthenticatedProfile();
      if (profile == null) await _auth.signOut();
      return profile;
    } on AuthException {
      return null;
    }
  }

  Future<UserModel?> restoreSession() async {
    if (_auth.currentSession == null) return null;
    try {
      // The profile request validates the access token (and lets Supabase
      // refresh it when necessary), so a separate getUser request only adds a
      // second network round trip during startup.
      return await _loadAuthenticatedProfile();
    } catch (_) {
      return null;
    }
  }

  /// Warnings from an administrator that the user has not acknowledged yet.
  /// A failed lookup returns none so a network hiccup never blocks sign-in.
  Future<List<Map<String, dynamic>>> pendingWarnings() async {
    try {
      final result = await _client.rpc('my_warnings');
      if (result is List) {
        return [for (final w in result) Map<String, dynamic>.from(w as Map)];
      }
    } catch (_) {}
    return const [];
  }

  Future<void> acknowledgeWarning(int warningId) async {
    try {
      await _client.rpc(
        'acknowledge_account_warning',
        params: {'warning_id': warningId},
      );
    } catch (_) {}
  }

  /// The suspension reason ('' when none was given) or null when the account
  /// is in good standing. A failed lookup is treated as not suspended: the
  /// database refuses a suspended account's writes regardless.
  Future<String?> suspensionReason() async {
    try {
      final result = await _client.rpc('my_suspension');
      if (result is Map && result['suspended'] == true) {
        return result['reason'] as String? ?? '';
      }
    } catch (_) {}
    return null;
  }

  Future<UserModel?> _loadAuthenticatedProfile() async {
    final authUser = _auth.currentUser;
    if (authUser == null) return null;

    final row = await _client
        .from('profiles')
        .select()
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (row == null) return null;

    final profile = UserModel.fromSupabaseMap(row);
    try {
      await _ensureLocalProfile(profile);
    } catch (_) {
      // Postgres remains the source of truth if the local mirror is unavailable.
    }
    return profile;
  }

  Future<SocialSignInResult> signInWithGoogle() {
    return _beginOAuth(OAuthProvider.google, providerName: 'Google');
  }

  Future<SocialSignInResult> signInWithFacebook() {
    return _beginOAuth(OAuthProvider.facebook, providerName: 'Facebook');
  }

  Future<SocialSignInResult> _beginOAuth(
    OAuthProvider provider, {
    required String providerName,
  }) async {
    try {
      _oauthRedirectPending = true;
      final launched = await _auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : _mobileRedirect,
      );
      if (!launched) {
        _oauthRedirectPending = false;
        return SocialSignInResult.failure(
          '$providerName sign-in could not be opened.',
        );
      }
      return const SocialSignInResult.pending();
    } on AuthException catch (error) {
      _oauthRedirectPending = false;
      return SocialSignInResult.failure(error.message);
    } catch (_) {
      _oauthRedirectPending = false;
      return SocialSignInResult.failure(
        '$providerName sign-in is not configured in Supabase yet.',
      );
    }
  }

  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? null : _mobileRedirect,
      );
      return null;
    } on AuthException catch (error) {
      if (error.code == 'over_email_send_rate_limit') {
        return 'Too many attempts. Please wait before trying again.';
      }
      return error.message;
    } catch (_) {
      return 'Could not send the reset email. Please try again.';
    }
  }

  Future<String?> completePasswordRecovery(String newPassword) async {
    if (_auth.currentSession == null) {
      return 'This password reset link has expired. Request a new one.';
    }
    try {
      await _auth.updateUser(UserAttributes(password: newPassword.trim()));
      return null;
    } on AuthException catch (error) {
      if (error.code == 'weak_password') {
        return 'Password is too weak — use at least 8 characters';
      }
      return error.message;
    } catch (_) {
      return 'Could not update your password. Please try again.';
    }
  }

  Future<String> updateProfile({
    required int userId,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) return 'Sign in again to update your profile.';

    try {
      final updates = <String, dynamic>{};
      if (firstName != null) updates['first_name'] = firstName.trim();
      if (lastName != null) updates['last_name'] = lastName.trim();
      if (phone != null) updates['phone'] = phone.trim();

      final requestedEmail = email?.trim().toLowerCase();
      final currentEmail = authUser.email?.trim().toLowerCase() ?? '';
      final emailChanged =
          requestedEmail != null &&
          requestedEmail.isNotEmpty &&
          requestedEmail != currentEmail;
      if (emailChanged) {
        await _auth.updateUser(
          UserAttributes(email: requestedEmail),
          emailRedirectTo: kIsWeb ? null : _mobileRedirect,
        );
      }

      if (updates.isNotEmpty) {
        await _client.from('profiles').update(updates).eq('id', userId);
      }
      await _databaseHelper.updateUserProfile(
        userId,
        firstName: firstName,
        lastName: lastName,
        email: currentEmail,
        phone: phone,
      );
      return emailChanged ? 'email_verification_sent' : 'success';
    } on AuthException catch (error) {
      return error.message;
    } on PostgrestException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not update your profile. Please try again.';
    }
  }

  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      return 'You need to be logged in to change your password.';
    }
    try {
      await _auth.signInWithPassword(email: email, password: currentPassword);
      await _auth.updateUser(UserAttributes(password: newPassword.trim()));
      return 'success';
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        return 'Current password is incorrect';
      }
      if (error.code == 'weak_password') {
        return 'Password is too weak — use at least 8 characters';
      }
      return error.message;
    }
  }

  Future<void> logout() => _auth.signOut();

  Future<void> _ensureLocalProfile(UserModel profile) async {
    final id = profile.id;
    if (id == null) return;
    final existingById = await _databaseHelper.getUserById(id);
    if (existingById != null) {
      await _databaseHelper.updateUserProfile(
        id,
        firstName: profile.firstName,
        lastName: profile.lastName,
        email: profile.email,
        phone: profile.phone,
      );
      return;
    }
    if (await _databaseHelper.getUserByEmail(profile.email) == null) {
      await _databaseHelper.registerUser(profile.toMap());
    }
  }

  String _mapAuthError(AuthException error) {
    switch (error.code) {
      case 'user_already_exists':
      case 'email_exists':
        return 'Email already exists';
      case 'weak_password':
        return 'Password is too weak — use at least 8 characters';
      case 'validation_failed':
        return 'Enter a valid email address';
      case 'unexpected_failure':
        return 'We could not finish creating your profile. Please try again or use account recovery if this email was used before.';
      default:
        return error.message;
    }
  }
}

class SocialSignInResult {
  final UserModel? user;
  final String? error;
  final bool isPending;

  const SocialSignInResult.success(UserModel this.user)
    : error = null,
      isPending = false;

  const SocialSignInResult.failure(this.error) : user = null, isPending = false;

  const SocialSignInResult.pending()
    : user = null,
      error = null,
      isPending = true;
}
