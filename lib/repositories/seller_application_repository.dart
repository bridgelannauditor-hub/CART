import 'package:supabase_flutter/supabase_flutter.dart';

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
}
