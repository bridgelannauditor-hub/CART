import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/seller_onboarding_model.dart';

class VerificationSessionStart {
  final String sessionId;
  final Uri? verificationUrl;
  final bool demoCompleted;

  const VerificationSessionStart({
    required this.sessionId,
    required this.verificationUrl,
    this.demoCompleted = false,
  });
}

class SchoolEmailChallengeStart {
  final String challengeId;
  final String maskedEmail;
  final String? prototypeCode;

  const SchoolEmailChallengeStart({
    required this.challengeId,
    required this.maskedEmail,
    this.prototypeCode,
  });
}

class SellerApplicationRepository {
  final SupabaseClient _supabase;

  SellerApplicationRepository({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  Future<Map<String, String>> _authenticatedHeaders() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      throw const AuthException('Sign in to continue.');
    }
    if (session.isExpired) {
      session = (await _supabase.auth.refreshSession()).session;
    }
    if (session == null) {
      throw const AuthException('Your session expired. Sign in again.');
    }
    return {'Authorization': 'Bearer ${session.accessToken}'};
  }

  Future<String> submit(Map<String, dynamic> application) async {
    final response = await _supabase.rpc(
      'submit_seller_application',
      params: {'payload': application},
    );
    final result = Map<String, dynamic>.from(response as Map);
    return result['status'] as String? ?? 'under_review';
  }

  Future<SellerOnboardingState> fetchOnboarding() async {
    final response = await _supabase.rpc('get_my_seller_onboarding');
    return SellerOnboardingState.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<SchoolEmailChallengeStart> requestSchoolEmailVerification() async {
    final response = await _supabase.functions.invoke(
      'request-school-email-verification',
      headers: await _authenticatedHeaders(),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return SchoolEmailChallengeStart(
      challengeId: data['challengeId'] as String,
      maskedEmail: data['maskedEmail'] as String,
      prototypeCode: data['prototypeCode'] as String?,
    );
  }

  Future<void> verifySchoolEmailCode({
    required String challengeId,
    required String code,
  }) async {
    await _supabase.functions.invoke(
      'verify-school-email-code',
      headers: await _authenticatedHeaders(),
      body: {'challengeId': challengeId, 'code': code},
    );
  }

  /// Asks the trusted backend to open a provider session. The provider key and
  /// the evidence never pass through the app.
  Future<VerificationSessionStart> startIdentityVerification() async {
    final response = await _supabase.functions.invoke(
      'create-verification-session',
      headers: await _authenticatedHeaders(),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return VerificationSessionStart(
      sessionId: data['sessionId'] as String,
      verificationUrl: data['verificationUrl'] is String
          ? Uri.parse(data['verificationUrl'] as String)
          : null,
      demoCompleted: data['demoCompleted'] == true,
    );
  }

  static const identityBucket = 'seller-verification';

  /// The ID type the applicant chose on the application form.
  Future<String> identityDocumentType() async {
    final row = await _supabase
        .from('seller_verification_applications')
        .select('identity_document_type')
        .single();
    return row['identity_document_type'] as String? ?? 'national_id';
  }

  /// Uploads the captured photos to the private verification bucket and
  /// queues the application for manual identity review. [backPath] is null
  /// for IDs that have no back (e.g. a passport).
  Future<void> submitIdentityDocuments({
    required File front,
    required File selfie,
    File? back,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in to continue.');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storage = _supabase.storage.from(identityBucket);

    Future<String> upload(File file, String name) async {
      final path = '$userId/${stamp}_$name.jpg';
      await storage.upload(
        path,
        file,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      return path;
    }

    final frontPath = await upload(front, 'front');
    final selfiePath = await upload(selfie, 'selfie');
    final backPath = back == null ? null : await upload(back, 'back');

    await _supabase.rpc(
      'submit_identity_documents',
      params: {
        'front_path': frontPath,
        'selfie_path': selfiePath,
        'back_path': backPath,
      },
    );
  }

  Future<String> saveShop(
    Map<String, dynamic> shop, {
    required bool submit,
  }) async {
    final response = await _supabase.rpc(
      'save_shop_draft',
      params: {
        'payload': {...shop, 'submit': submit},
      },
    );
    final result = Map<String, dynamic>.from(response as Map);
    return result['shop_status'] as String? ?? 'draft';
  }

  Future<void> appeal(String message) async {
    await _supabase.rpc(
      'appeal_seller_application',
      params: {'message': message},
    );
  }
}
