import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_media_model.dart';
import '../models/product_model.dart';
import '../services/category_service.dart';

class ProductPage {
  final List<ProductModel> items;
  final int? nextProductId;
  final bool hasMore;

  const ProductPage({
    required this.items,
    required this.nextProductId,
    required this.hasMore,
  });
}

class SellerProductMetrics {
  final int productCount;
  final int unitsSold;
  final int lowStockCount;
  final ProductModel? bestSeller;
  final double averageRating;
  final int reviewCount;

  const SellerProductMetrics({
    required this.productCount,
    required this.unitsSold,
    required this.lowStockCount,
    required this.bestSeller,
    this.averageRating = 0,
    this.reviewCount = 0,
  });
}

class ProductRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final CategoryService _categoryService = CategoryService();

  List<ProductModel> _models(List<Map<String, dynamic>> rows) =>
      rows.map(ProductModel.fromSupabaseMap).toList();

  Future<List<ProductModel>> getProductsBySeller(int sellerId) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('seller_id', sellerId)
        .order('id', ascending: false);
    return _models(rows);
  }

  Future<ProductPage> getSellerProductsPage(
    int sellerId, {
    int? afterProductId,
    int pageSize = 20,
  }) async {
    _checkPageSize(pageSize);
    var query = _client.from('products').select().eq('seller_id', sellerId);
    if (afterProductId != null) query = query.lt('id', afterProductId);
    final rows = await query.order('id', ascending: false).limit(pageSize + 1);
    return _toPage(rows, afterProductId, pageSize);
  }

  Future<SellerProductMetrics> getSellerProductMetrics(int sellerId) async {
    final products = await getProductsBySeller(sellerId);
    final reviewCount = products.fold<int>(
      0,
      (total, product) => total + product.reviewCount,
    );
    final ratingTotal = products.fold<double>(
      0,
      (total, product) => total + product.rating * product.reviewCount,
    );
    final ranked = [...products]
      ..sort((a, b) => b.totalSold.compareTo(a.totalSold));
    return SellerProductMetrics(
      productCount: products.length,
      unitsSold: products.fold<int>(
        0,
        (total, product) => total + product.totalSold,
      ),
      lowStockCount: products
          .where((product) => product.stock > 0 && product.stock <= 5)
          .length,
      bestSeller: ranked.isEmpty || ranked.first.totalSold == 0
          ? null
          : ranked.first,
      averageRating: reviewCount == 0 ? 0 : ratingTotal / reviewCount,
      reviewCount: reviewCount,
    );
  }

  Future<List<ProductModel>> getSellerTopProducts(
    int sellerId, {
    int limit = 10,
  }) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('seller_id', sellerId)
        .gt('total_sold', 0)
        .order('total_sold', ascending: false)
        .limit(limit);
    return _models(rows);
  }

  Future<List<ProductModel>> getSellerFlashSaleProducts(
    int sellerId, {
    int limit = 10,
  }) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('seller_id', sellerId)
        .eq('is_flash_sale', true)
        .order('id', ascending: false)
        .limit(limit);
    return _models(rows);
  }

  Future<List<ProductModel>> getTopSellingProducts({int limit = 10}) async {
    final rows = await _client
        .from('products')
        .select()
        .gt('total_sold', 0)
        .order('total_sold', ascending: false)
        .limit(limit);
    return _models(rows);
  }

  Future<List<ProductModel>> getAllProducts() async {
    final rows = await _client
        .from('products')
        .select()
        .order('id', ascending: false);
    return _models(rows);
  }

  Future<ProductPage> getProductsPage({
    int? afterProductId,
    int pageSize = 20,
  }) async {
    _checkPageSize(pageSize);
    var query = _client.from('products').select();
    if (afterProductId != null) query = query.lt('id', afterProductId);
    final rows = await query.order('id', ascending: false).limit(pageSize + 1);
    return _toPage(rows, afterProductId, pageSize);
  }

  Future<List<ProductModel>> getFlashSaleProductsForSeller(int sellerId) {
    return getSellerFlashSaleProducts(sellerId, limit: 1000);
  }

  Future<ProductModel?> getProductById(int id) async {
    final row = await _client
        .from('products')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : ProductModel.fromSupabaseMap(row);
  }

  Future<List<ProductModel>> getProductsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('products')
        .select()
        .inFilter('id', ids.toSet().toList())
        .order('id', ascending: false);
    return _models(rows);
  }

  Future<int> insertProduct(ProductModel product) async {
    final category = _categoryService.getCategoryById(product.categoryId);
    final toSave = _withCategory(
      product,
      category?.categoryGroup,
      category?.categoryName,
      id: null,
    );
    try {
      final result = await _client.rpc(
        'create_product',
        params: {'payload': toSave.toFirestoreMap()},
      );
      final id = result is num ? result.toInt() : int.tryParse('$result');
      if (id == null) {
        throw StateError('The server returned an invalid product.');
      }
      return id;
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  Future<int> updateProduct(int id, ProductModel product) async {
    final category = _categoryService.getCategoryById(product.categoryId);
    final toSave = _withCategory(
      product,
      category?.categoryGroup,
      category?.categoryName,
      id: id,
    );
    await _client
        .from('products')
        .update(toSave.toSupabaseMap(includeId: false))
        .eq('id', id);
    return id;
  }

  Future<int> deleteProduct(int id) async {
    await _client.from('products').delete().eq('id', id);
    return id;
  }

  Future<void> saveTagsForProduct(int productId, List<String> tags) async {
    await _client.from('products').update({'tags': tags}).eq('id', productId);
  }

  Future<List<String>> getTagsForProduct(int productId) async {
    final row = await _client
        .from('products')
        .select('tags')
        .eq('id', productId)
        .maybeSingle();
    return ((row?['tags'] as List?) ?? const [])
        .map((tag) => tag.toString())
        .toList();
  }

  Future<List<ProductModel>> getFilteredProducts({
    String? mainCategory,
    String? subcategory,
    String? craftType,
    String? material,
    String? occasion,
    String? tag,
  }) async {
    final rows = await _filteredQuery(
      mainCategory: mainCategory,
      subcategory: subcategory,
      craftType: craftType,
      material: material,
      occasion: occasion,
      tag: tag,
    ).order('id', ascending: false);
    return _models(rows);
  }

  Future<ProductPage> getFilteredProductsPage({
    String? mainCategory,
    String? subcategory,
    String? craftType,
    String? material,
    String? occasion,
    String? tag,
    int? afterProductId,
    int pageSize = 20,
  }) async {
    _checkPageSize(pageSize);
    var query = _filteredQuery(
      mainCategory: mainCategory,
      subcategory: subcategory,
      craftType: craftType,
      material: material,
      occasion: occasion,
      tag: tag,
    );
    if (afterProductId != null) query = query.lt('id', afterProductId);
    final rows = await query.order('id', ascending: false).limit(pageSize + 1);
    return _toPage(rows, afterProductId, pageSize);
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _filteredQuery({
    String? mainCategory,
    String? subcategory,
    String? craftType,
    String? material,
    String? occasion,
    String? tag,
  }) {
    var query = _client.from('products').select();
    if (mainCategory != null) {
      query = query.eq('category_group', mainCategory);
    }
    if (subcategory != null) query = query.eq('category_name', subcategory);
    if (craftType != null) query = query.eq('craft_type', craftType);
    if (material != null) query = query.eq('material', material);
    if (occasion != null) query = query.eq('occasion', occasion);
    if (tag != null) query = query.contains('tags', [tag]);
    return query;
  }

  Future<List<ProductMediaModel>> getMediaForProduct(int productId) async {
    final row = await _client
        .from('products')
        .select('media')
        .eq('id', productId)
        .maybeSingle();
    return ((row?['media'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => ProductMediaModel.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> saveMediaForProduct(
    int productId,
    List<ProductMediaModel> media,
  ) async {
    await _client
        .from('products')
        .update({'media': media.map((item) => item.toMap()).toList()})
        .eq('id', productId);
  }

  ProductPage _toPage(
    List<Map<String, dynamic>> rows,
    int? previousCursor,
    int pageSize,
  ) {
    final hasMore = rows.length > pageSize;
    final items = _models(rows.take(pageSize).toList());
    return ProductPage(
      items: items,
      nextProductId: items.isEmpty ? previousCursor : items.last.id,
      hasMore: hasMore,
    );
  }

  ProductModel _withCategory(
    ProductModel product,
    String? categoryGroup,
    String? categoryName, {
    required int? id,
  }) {
    return ProductModel(
      id: id,
      sellerId: product.sellerId,
      categoryId: product.categoryId,
      categoryGroup: categoryGroup,
      categoryName: categoryName,
      productName: product.productName,
      description: product.description,
      price: product.price,
      stock: product.stock,
      image: product.image,
      rating: product.rating,
      reviewCount: product.reviewCount,
      totalSold: product.totalSold,
      craftType: product.craftType,
      material: product.material,
      occasion: product.occasion,
      isFlashSale: product.isFlashSale,
      discountPercent: product.discountPercent,
      freeShipping: product.freeShipping,
      codAvailable: product.codAvailable,
      makingProcess: product.makingProcess,
      media: product.media,
      tags: product.tags,
      pricingMode: product.pricingMode,
      options: product.options,
    );
  }

  void _checkPageSize(int pageSize) {
    if (pageSize <= 0 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Use 1 to 50 items.');
    }
  }
}
