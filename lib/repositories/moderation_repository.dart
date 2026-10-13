import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> reportListingAsNotHandmade({
    required int productId,
    required int reporterId,
    String? details,
  }) async {
    await _supabase.from('listing_reports').insert({
      'product_id': productId,
      'reporter_id': reporterId,
      'reason': 'not_handmade',
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }
}
