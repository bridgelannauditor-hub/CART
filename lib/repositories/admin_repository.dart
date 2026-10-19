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

  Future<Map<String, dynamic>> dashboardSummary() async {
    final response = await _supabase.rpc('admin_dashboard_summary');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> listProfiles({
    String? query,
    int limit = 100,
  }) async {
    final response = await _supabase.rpc(
      'admin_list_profiles',
      params: {'search_query': query, 'row_limit': limit},
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  /// Suspends or restores a customer or seller account. The server requires a
  /// reason, protects administrators, and records the change in the audit log.
  Future<void> setAccountSuspension({
    required int profileId,
    required bool suspend,
    required String reason,
    List<String> categories = const [],
  }) async {
    await _supabase.rpc(
      'admin_set_account_suspension',
      params: {
        'target_profile_id': profileId,
        'suspend': suspend,
        'reason': reason,
        'categories': categories,
      },
    );
  }

  /// Warns an account (a step before suspension). The server records the
  /// evidence, logs it in the account history and notifies the user.
  Future<void> warnAccount({
    required int profileId,
    required String message,
    required List<String> categories,
  }) async {
    await _supabase.rpc(
      'admin_warn_account',
      params: {
        'target_profile_id': profileId,
        'message': message,
        'categories': categories,
      },
    );
  }

  /// Reports found against an account, used to suggest suspension reasons.
  Future<Map<String, dynamic>> accountEvidence(int profileId) async {
    final response = await _supabase.rpc(
      'admin_account_evidence',
      params: {'target_profile_id': profileId},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Status changes and reviews for one account, newest first.
  Future<List<Map<String, dynamic>>> accountHistory(int profileId) async {
    final response = await _supabase.rpc(
      'admin_account_history',
      params: {'target_profile_id': profileId},
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listListingReports({
    String? status,
  }) async {
    final response = await _supabase.rpc(
      'admin_list_listing_reports',
      params: {'status_filter': status},
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listShopReports({String? status}) async {
    final response = await _supabase.rpc(
      'admin_list_shop_reports',
      params: {'status_filter': status},
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<void> updateShopReport({
    required int reportId,
    required String status,
  }) async {
    await _supabase.rpc(
      'admin_update_shop_report',
      params: {'target_report_id': reportId, 'new_status': status},
    );
  }

  /// Reports per status for both kinds: {listing: {open: n, ...}, shop: {...}}.
  Future<Map<String, dynamic>> reportCounts() async {
    final response = await _supabase.rpc('admin_report_counts');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> updateListingReport({
    required int reportId,
    required String status,
  }) async {
    await _supabase.rpc(
      'admin_update_listing_report',
      params: {'target_report_id': reportId, 'new_status': status},
    );
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

  /// Short-lived signed URLs (front, back, selfie) for an applicant's ID
  /// photos. Each call is written to the server's audit log.
  Future<Map<String, String>> identityPhotoUrls(int profileId) async {
    final response = await _supabase.rpc(
      'admin_get_identity_document_paths',
      params: {'target_profile_id': profileId},
    );
    final paths = Map<String, dynamic>.from(response as Map);
    final storage = _supabase.storage.from('seller-verification');
    final urls = <String, String>{};
    for (final entry in paths.entries) {
      final path = entry.value as String?;
      if (path == null) continue;
      urls[entry.key] = await storage.createSignedUrl(path, 120);
    }
    return urls;
  }

  Future<void> requestIdentityRetry({
    required int profileId,
    required String reasonCode,
  }) async {
    await _supabase.rpc(
      'admin_request_identity_retry',
      params: {'target_profile_id': profileId, 'reason_code': reasonCode},
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
