import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';

/// Authentication and profile access backed by Supabase Auth + Postgres.
class AuthService {
  static const _mobileRedirect = 'io.supabase.flutter://login-callback/';

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final SupabaseClient _client = Supabase.instance.client;

  GoTrueClient get _auth => _client.auth;

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
          'account_type': user.accountType,
          'shop_name': user.shopName?.trim(),
          'avatar_url': user.profileImage,
          if (user.sellerVerification != null)
            'seller_verification': user.sellerVerification!.toApplicationMap(),
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

  Future<SocialSignInResult> signInWithGoogle({
    String accountType = 'Customer',
    String? shopName,
  }) {
    return _beginOAuth(
      OAuthProvider.google,
      providerName: 'Google',
      accountType: accountType,
    );
  }

  Future<SocialSignInResult> signInWithFacebook({
    String accountType = 'Customer',
    String? shopName,
  }) {
    return _beginOAuth(
      OAuthProvider.facebook,
      providerName: 'Facebook',
      accountType: accountType,
    );
  }

  Future<SocialSignInResult> _beginOAuth(
    OAuthProvider provider, {
    required String providerName,
    required String accountType,
  }) async {
    if (accountType == 'Seller') {
      return const SocialSignInResult.failure(
        'Create seller accounts with email and password so verification details are preserved.',
      );
    }
    try {
      final launched = await _auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : _mobileRedirect,
      );
      if (!launched) {
        return SocialSignInResult.failure(
          '$providerName sign-in could not be opened.',
        );
      }
      // OAuth completes through the app redirect. Splash restores the session.
      return const SocialSignInResult.cancelled();
    } on AuthException catch (error) {
      return SocialSignInResult.failure(error.message);
    } catch (_) {
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
  final bool wasCancelled;

  const SocialSignInResult.success(UserModel this.user)
    : error = null,
      wasCancelled = false;

  const SocialSignInResult.failure(this.error)
    : user = null,
      wasCancelled = false;

  const SocialSignInResult.cancelled()
    : user = null,
      error = null,
      wasCancelled = true;
}
