import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Reports a whole shop. Throws [PostgrestException]; code `23505` means
  /// this reporter already reported the shop for the same reason.
  Future<void> reportShop({
    required int shopId,
    required int reporterId,
    required String reason,
    String? details,
  }) async {
    await _supabase.from('shop_reports').insert({
      'shop_id': shopId,
      'reporter_id': reporterId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

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
