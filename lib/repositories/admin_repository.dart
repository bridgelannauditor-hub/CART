import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin operations. Every RPC re-checks `private.is_admin()` on the server;
/// nothing here is trusted because the client called it.
class AdminRepository {
  final SupabaseClient _supabase;

  AdminRepository({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  Future<bool> isAdmin() async {
    try {
      return await _supabase.rpc('am_i_admin') as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listSellerApplications({
    String? status,
  }) async {
    final response = await _supabase.rpc(
      'admin_list_seller_applications',
      params: {'status_filter': status},
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<void> reviewApplication({
    required int profileId,
    required int revision,
    required String decision,
    String? reasonCode,
  }) async {
    await _supabase.rpc(
      'admin_review_seller_application',
      params: {
        'target_profile_id': profileId,
        'expected_revision': revision,
        'decision': decision,
        'reason_code': reasonCode,
      },
    );
  }

  Future<void> resolveIdentityReview({
    required int profileId,
    required bool verified,
    required String reasonCode,
  }) async {
    await _supabase.rpc(
      'admin_resolve_identity_review',
      params: {
        'target_profile_id': profileId,
        'verified': verified,
        'reason_code': reasonCode,
      },
    );
  }
}
