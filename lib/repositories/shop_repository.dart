import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';
import '../models/user_model.dart';
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
  final UserRepository _userRepository = UserRepository();

  Future<UserModel?> getShop(int sellerId) {
    return _userRepository.getUserById(sellerId);
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

  Future<List<ProductModel>> getFlashSaleProducts(int sellerId) {
    return _productRepository.getSellerFlashSaleProducts(sellerId);
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
        .from('profiles')
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
    await _supabase
        .from('profiles')
        .update({'is_live': isLive})
        .eq('id', sellerId);
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
