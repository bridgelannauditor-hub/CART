import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/flash_sale_model.dart';
import '../models/product_model.dart';

class FlashSaleListing {
  final FlashSaleModel sale;
  final ProductModel? product;

  const FlashSaleListing({required this.sale, required this.product});
}

class FlashSaleRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _nowUtc => DateTime.now().toUtc().toIso8601String();

  Future<List<FlashSaleEligibility>> myEligibility() async {
    final raw = await _guard(() => _client.rpc('my_flash_sale_eligibility'));
    return ((raw as List?) ?? const [])
        .whereType<Map>()
        .map((item) => FlashSaleEligibility.fromMap(Map.from(item)))
        .toList();
  }

  Future<int> create({
    required int productId,
    required int discountPercent,
    required int promoStock,
    required int perCustomerLimit,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final result = await _guard(
      () => _client.rpc(
        'create_flash_sale',
        params: {
          'config': {
            'product_id': productId,
            'discount_percent': discountPercent,
            'promo_stock': promoStock,
            'per_customer_limit': perCustomerLimit,
            'starts_at': startsAt.toUtc().toIso8601String(),
            'ends_at': endsAt.toUtc().toIso8601String(),
          },
        },
      ),
    );
    final id = result is num ? result.toInt() : int.tryParse('$result');
    if (id == null) throw StateError('The server returned an invalid sale.');
    return id;
  }

  Future<void> cancel(int flashSaleId) async {
    await _guard(
      () =>
          _client.rpc('cancel_flash_sale', params: {'target_id': flashSaleId}),
    );
  }

  /// The seller's own flash sales, newest first, with their products.
  Future<List<FlashSaleListing>> mySales(int sellerId) async {
    final rows = await _guard(
      () => _client
          .from('flash_sales')
          .select('*, products(*)')
          .eq('seller_id', sellerId)
          .order('starts_at', ascending: false)
          .limit(100),
    );
    return rows.map(_listing).toList();
  }

  /// Live flash sales keyed by product id. Sold-out sales are left out.
  Future<Map<int, FlashSaleModel>> liveByProductIds(Iterable<int> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    var query = _client.from('flash_sales').select();
    // Live sales are few; for long lists fetch them all rather than send a
    // very long id filter.
    if (unique.length <= 150) query = query.inFilter('product_id', unique);
    final wanted = unique.toSet();
    final rows = await query
        .isFilter('cancelled_at', null)
        .lte('starts_at', _nowUtc)
        .gt('ends_at', _nowUtc);
    final now = DateTime.now();
    return {
      for (final sale in rows.map(FlashSaleModel.fromSupabaseMap))
        if (wanted.contains(sale.productId) && sale.isLiveAt(now))
          sale.productId: sale,
    };
  }

  /// Products with a live flash sale in one shop, soonest-ending first.
  Future<List<ProductModel>> liveProductsForShop(int sellerId) async {
    final rows = await _client
        .from('flash_sales')
        .select('*, products(*)')
        .eq('seller_id', sellerId)
        .isFilter('cancelled_at', null)
        .lte('starts_at', _nowUtc)
        .gt('ends_at', _nowUtc)
        .order('ends_at');
    final now = DateTime.now();
    return [
      for (final listing in rows.map(_listing))
        if (listing.product != null && listing.sale.isLiveAt(now))
          listing.product!.withFlashSale(listing.sale),
    ];
  }

  FlashSaleListing _listing(Map<String, dynamic> row) {
    final product = row['products'];
    return FlashSaleListing(
      sale: FlashSaleModel.fromSupabaseMap(row),
      product: product is Map
          ? ProductModel.fromSupabaseMap(Map<String, dynamic>.from(product))
          : null,
    );
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }
}
