import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';
import '../models/user_model.dart';
import 'flash_sale_repository.dart';
import 'product_repository.dart';
import 'voucher_repository.dart';
import 'user_repository.dart';

class FollowedShopsPage {
  final List<UserModel> items;
  final String? cursor;
  final bool hasMore;

  const FollowedShopsPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class ShopRepository {
  SupabaseClient get _supabase => Supabase.instance.client;
  final ProductRepository _productRepository = ProductRepository();
  final FlashSaleRepository _flashSaleRepository = FlashSaleRepository();
  final UserRepository _userRepository = UserRepository();

  Future<UserModel?> getShop(int sellerId) {
    return _userRepository.getUserById(sellerId);
  }

  Future<List<UserModel>> searchShops(String query, {int limit = 8}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final rows = await _supabase
        .from('marketplace_profiles')
        .select(
          'id,first_name,last_name,account_type,shop_name,cover_image,'
          'profile_image,is_live,is_verified_seller,seller_tier,'
          'trust_score,created_at',
        )
        .eq('account_type', 'Seller')
        .not('shop_name', 'is', null)
        .ilike('shop_name', '%$term%')
        .order('is_live', ascending: false)
        .order('shop_name')
        .limit(limit);

    return rows.map(UserModel.fromSupabaseMap).toList();
  }

  Future<ProductPage> getShopProductsPage(
    int sellerId, {
    int? afterProductId,
    int pageSize = 20,
  }) {
    return _productRepository.getSellerProductsPage(
      sellerId,
      afterProductId: afterProductId,
      pageSize: pageSize,
    );
  }

  Future<SellerProductMetrics> getProductMetrics(int sellerId) {
    return _productRepository.getSellerProductMetrics(sellerId);
  }

  /// Products in a live Marketing Centre flash sale. The shop page still
  /// loads if the lookup fails.
  Future<List<ProductModel>> getFlashSaleProducts(int sellerId) async {
    try {
      return await _flashSaleRepository.liveProductsForShop(sellerId);
    } catch (_) {
      return const [];
    }
  }

  Future<List<ProductModel>> getTopProducts(int sellerId) {
    return _productRepository.getSellerTopProducts(sellerId);
  }

  Future<int> getFollowerCount(int sellerId) async {
    final rows = await _supabase
        .from('shop_follows')
        .select('follower_id')
        .eq('seller_id', sellerId);
    return rows.length;
  }

  Future<bool> isFollowing(int followerId, int sellerId) async {
    final row = await _supabase
        .from('shop_follows')
        .select('follower_id')
        .eq('follower_id', followerId)
        .eq('seller_id', sellerId)
        .maybeSingle();
    return row != null;
  }

  Future<bool> toggleFollow(int followerId, int sellerId) async {
    return (await VoucherRepository().toggleFollow(
      followerId,
      sellerId,
    )).following;
  }

  Future<List<UserModel>> getFollowedShops(int followerId) async {
    final rows = await _supabase
        .from('shop_follows')
        .select('seller_id')
        .eq('follower_id', followerId)
        .order('created_at', ascending: false);
    return _shopsInFollowOrder(rows);
  }

  /// The people following a shop, newest first.
  Future<FollowedShopsPage> getFollowersPage(
    int sellerId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase
        .from('shop_follows')
        .select('follower_id,created_at')
        .eq('seller_id', sellerId);
    if (after != null) query = query.lt('created_at', after);
    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();
    final followerIds = [
      for (final row in pageRows) ?(row['follower_id'] as num?)?.toInt(),
    ];
    final users = await _userRepository.getUsersByIds(followerIds);
    final byId = {for (final user in users) user.id: user};
    return FollowedShopsPage(
      items: [for (final id in followerIds) ?byId[id]],
      cursor: pageRows.isEmpty ? after : pageRows.last['created_at'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<FollowedShopsPage> getFollowedShopsPage(
    int followerId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase
        .from('shop_follows')
        .select('seller_id,created_at')
        .eq('follower_id', followerId);
    if (after != null) query = query.lt('created_at', after);
    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();

    return FollowedShopsPage(
      items: await _shopsInFollowOrder(pageRows),
      cursor: pageRows.isEmpty ? after : pageRows.last['created_at'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<List<UserModel>> _shopsInFollowOrder(
    List<Map<String, dynamic>> rows,
  ) async {
    final sellerIds = rows
        .map((row) => (row['seller_id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final shops = await _userRepository.getUsersByIds(sellerIds);
    final byId = {for (final shop in shops) shop.id: shop};
    return sellerIds.map((id) => byId[id]).whereType<UserModel>().toList();
  }

  Future<int> getFollowedShopCount(int followerId) async {
    final rows = await _supabase
        .from('shop_follows')
        .select('seller_id')
        .eq('follower_id', followerId);
    return rows.length;
  }

  Future<List<UserModel>> getLiveShops() async {
    final rows = await _supabase
        .from('marketplace_profiles')
        .select()
        .eq('account_type', 'Seller')
        .eq('is_live', true);
    return rows.map(UserModel.fromSupabaseMap).toList();
  }

  Future<void> setLiveStatus(
    int sellerId,
    bool isLive, {
    String? firebaseUid,
  }) async {
    await _supabase.rpc('set_my_live_status', params: {'new_is_live': isLive});
  }

  Future<void> recordVisit(int visitorId, int sellerId) async {
    await _supabase.from('shop_visits').insert({
      'seller_id': sellerId,
      'visitor_id': visitorId,
    });
  }

  Future<int> getVisitorCount(int sellerId) async {
    final rows = await _supabase
        .from('shop_visits')
        .select('visitor_id')
        .eq('seller_id', sellerId);
    return rows
        .map((row) => (row['visitor_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .length;
  }
}
