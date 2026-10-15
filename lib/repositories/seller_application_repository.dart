import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/seller_onboarding_model.dart';

class VerificationSessionStart {
  final String sessionId;
  final Uri verificationUrl;

  const VerificationSessionStart({
    required this.sessionId,
    required this.verificationUrl,
  });
}

class SellerApplicationRepository {
  final SupabaseClient _supabase;

  SellerApplicationRepository({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

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

  /// Asks the trusted backend to open a provider session. The provider key and
  /// the evidence never pass through the app.
  Future<VerificationSessionStart> startIdentityVerification() async {
    final response = await _supabase.functions.invoke(
      'create-verification-session',
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return VerificationSessionStart(
      sessionId: data['sessionId'] as String,
      verificationUrl: Uri.parse(data['verificationUrl'] as String),
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
