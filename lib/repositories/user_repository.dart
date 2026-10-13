import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';

/// Reads user and shop profiles from Supabase by their stable numeric id.
class UserRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<UserModel?> getUserById(int id) async {
    final row = await _supabase
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : UserModel.fromSupabaseMap(row);
  }

  Future<List<UserModel>> getUsersByIds(Iterable<int> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final rows = await _supabase
        .from('profiles')
        .select()
        .inFilter('id', uniqueIds);
    return rows.map(UserModel.fromSupabaseMap).toList();
  }

  Future<void> updateShopImages({
    required int sellerId,
    String? firebaseUid,
    String? coverImage,
    String? profileImage,
  }) async {
    final updates = <String, dynamic>{};
    if (coverImage != null) updates['cover_image'] = coverImage;
    if (profileImage != null) updates['profile_image'] = profileImage;
    if (updates.isEmpty) return;

    await _supabase.from('profiles').update(updates).eq('id', sellerId);
  }

  Future<void> updateShopName({
    required int sellerId,
    required String shopName,
    String? firebaseUid,
  }) async {
    await _supabase
        .from('profiles')
        .update({'shop_name': shopName})
        .eq('id', sellerId);
  }
}
