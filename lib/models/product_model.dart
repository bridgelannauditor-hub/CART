import '../database/tables.dart';
import 'flash_sale_model.dart';
import 'product_media_model.dart';
import 'making_process_model.dart';
import 'product_option_model.dart';

class ProductModel {
  final int? id;
  final int sellerId;
  final int categoryId;

  // Denormalized from CategoryService at save time so Firestore can
  // filter products by category without needing a join.
  final String? categoryGroup;
  final String? categoryName;

  final String productName;
  final String description;
  final double price;
  final int stock;
  final String image;
  final double rating;
  final int reviewCount;
  final int totalSold;
  final String? craftType;
  final String? material;
  final String? occasion;
  final int discountPercent;
  final bool freeShipping;
  final bool codAvailable;
  final MakingProcessModel? makingProcess;

  // Embedded instead of separate join tables (product_media,
  // product_tags) — a more natural fit for Firestore, and always
  // fetched/saved together with the product anyway.
  final List<ProductMediaModel> media;
  final List<String> tags;
  final String pricingMode;
  final List<ProductOptionModel> options;

  // Attached by the repositories when the product has a live Marketing Centre
  // flash sale; never saved with the product.
  final FlashSaleModel? flashSale;

  ProductModel({
    this.id,
    required this.sellerId,
    required this.categoryId,
    this.categoryGroup,
    this.categoryName,
    required this.productName,
    required this.description,
    required this.price,
    required this.stock,
    required this.image,
    this.rating = 0,
    this.reviewCount = 0,
    this.totalSold = 0,
    this.craftType,
    this.material,
    this.occasion,
    this.discountPercent = 0,
    this.freeShipping = false,
    this.codAvailable = false,
    this.makingProcess,
    this.media = const [],
    this.tags = const [],
    this.pricingMode = 'single',
    this.options = const [],
    this.flashSale,
  });

  bool get hasImageOptions => pricingMode == 'per_image' && options.isNotEmpty;

  /// The attached flash sale while it is live; it stops applying the moment
  /// it ends or sells out.
  FlashSaleModel? get liveFlashSale {
    final sale = flashSale;
    return sale != null && sale.isLiveAt(DateTime.now()) ? sale : null;
  }

  bool get hasDiscount =>
      liveFlashSale != null || (discountPercent > 0 && discountPercent <= 100);

  /// A live flash sale replaces the regular discount, matching checkout.
  double discountedPriceFor(double originalPrice) {
    final sale = liveFlashSale;
    if (sale != null) return sale.priceFor(originalPrice);
    return regularPriceFor(originalPrice);
  }

  /// The price with only the regular discount, ignoring any flash sale.
  double regularPriceFor(double originalPrice) {
    if (discountPercent <= 0 || discountPercent > 100) return originalPrice;
    final discounted = originalPrice * (1 - discountPercent / 100);
    return (discounted * 100).roundToDouble() / 100;
  }

  double get effectivePrice => discountedPriceFor(price);

  /// The discount badge to show: the flash percent while a sale is live.
  int get activeDiscountPercent =>
      liveFlashSale?.discountPercent ?? discountPercent;

  ProductOptionModel? get defaultOption {
    if (!hasImageOptions) return null;
    for (final option in options) {
      if (option.isDefault) return option;
    }
    return options.first;
  }

  ProductOptionModel? optionById(String? id) {
    if (id == null) return null;
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  ProductModel withFlashSale(FlashSaleModel? sale) {
    return ProductModel(
      id: id,
      sellerId: sellerId,
      categoryId: categoryId,
      categoryGroup: categoryGroup,
      categoryName: categoryName,
      productName: productName,
      description: description,
      price: price,
      stock: stock,
      image: image,
      rating: rating,
      reviewCount: reviewCount,
      totalSold: totalSold,
      craftType: craftType,
      material: material,
      occasion: occasion,
      discountPercent: discountPercent,
      freeShipping: freeShipping,
      codAvailable: codAvailable,
      makingProcess: makingProcess,
      media: media,
      tags: tags,
      pricingMode: pricingMode,
      options: options,
      flashSale: sale,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.sellerId: sellerId,
      DBTables.categoryId: categoryId,
      DBTables.productName: productName,
      DBTables.description: description,
      DBTables.price: price,
      DBTables.stock: stock,
      DBTables.image: image,
      DBTables.rating: rating,
      DBTables.craftType: craftType,
      DBTables.material: material,
      DBTables.occasion: occasion,
      DBTables.discountPercent: discountPercent,
      DBTables.freeShipping: freeShipping ? 1 : 0,
      DBTables.codAvailable: codAvailable ? 1 : 0,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map[DBTables.id],
      sellerId: map[DBTables.sellerId],
      categoryId: map[DBTables.categoryId],
      productName: map[DBTables.productName],
      description: map[DBTables.description],
      price: (map[DBTables.price] as num).toDouble(),
      stock: map[DBTables.stock],
      image: map[DBTables.image] ?? '',
      rating: (map[DBTables.rating] as num?)?.toDouble() ?? 0,
      craftType: map[DBTables.craftType],
      material: map[DBTables.material],
      occasion: map[DBTables.occasion],
      discountPercent: (map[DBTables.discountPercent] as num?)?.toInt() ?? 0,
      freeShipping: ((map[DBTables.freeShipping] as num?) ?? 0) != 0,
      codAvailable: ((map[DBTables.codAvailable] as num?) ?? 0) != 0,
    );
  }

  // ==========================
  // FIRESTORE MAP (source of truth going forward)
  // ==========================

  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'categoryId': categoryId,
      'categoryGroup': categoryGroup,
      'categoryName': categoryName,
      'productName': productName,
      'description': description,
      'price': price,
      'stock': stock,
      'image': image,
      'rating': rating,
      'reviewCount': reviewCount,
      'totalSold': totalSold,
      'craftType': craftType,
      'material': material,
      'occasion': occasion,
      'discountPercent': discountPercent,
      'freeShipping': freeShipping,
      'codAvailable': codAvailable,
      'makingProcess': makingProcess?.toMap(),
      'media': media.map((m) => m.toMap()).toList(),
      'tags': tags,
      'pricingMode': pricingMode,
      'options': options.map((option) => option.toMap()).toList(),
    };
  }

  factory ProductModel.fromFirestoreMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as int?,
      sellerId: map['sellerId'] as int,
      categoryId: map['categoryId'] as int,
      categoryGroup: map['categoryGroup'] as String?,
      categoryName: map['categoryName'] as String?,
      productName: map['productName'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] as num).toDouble(),
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      image: map['image'] ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['reviewCount'] as num?)?.toInt() ?? 0,
      totalSold: (map['totalSold'] as num?)?.toInt() ?? 0,
      craftType: map['craftType'] as String?,
      material: map['material'] as String?,
      occasion: map['occasion'] as String?,
      discountPercent: (map['discountPercent'] as num?)?.toInt() ?? 0,
      freeShipping: (map['freeShipping'] as bool?) ?? false,
      codAvailable: (map['codAvailable'] as bool?) ?? false,
      makingProcess: map['makingProcess'] is Map
          ? MakingProcessModel.fromMap(
              Map<String, dynamic>.from(map['makingProcess'] as Map),
            )
          : null,
      media: ((map['media'] as List?) ?? [])
          .map(
            (m) =>
                ProductMediaModel.fromMap(Map<String, dynamic>.from(m as Map)),
          )
          .toList(),
      tags: ((map['tags'] as List?) ?? []).map((t) => t.toString()).toList(),
      pricingMode: map['pricingMode'] as String? ?? 'single',
      options: ((map['options'] as List?) ?? const [])
          .map(
            (option) => ProductOptionModel.fromMap(
              Map<String, dynamic>.from(option as Map),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toSupabaseMap({bool includeId = true}) {
    return {
      if (includeId && id != null) 'id': id,
      'seller_id': sellerId,
      'category_id': categoryId,
      'category_group': categoryGroup,
      'category_name': categoryName,
      'product_name': productName,
      'description': description,
      'price': price,
      'stock': stock,
      'image': image,
      'craft_type': craftType,
      'material': material,
      'occasion': occasion,
      'discount_percent': discountPercent,
      'free_shipping': freeShipping,
      'cod_available': codAvailable,
      'making_process': makingProcess?.toMap(),
      'media': media.map((item) => item.toMap()).toList(),
      'tags': tags,
      'pricing_mode': pricingMode,
      'options': options.map((option) => option.toMap()).toList(),
    };
  }

  factory ProductModel.fromSupabaseMap(Map<String, dynamic> map) {
    return ProductModel(
      id: (map['id'] as num?)?.toInt(),
      sellerId: (map['seller_id'] as num).toInt(),
      categoryId: (map['category_id'] as num).toInt(),
      categoryGroup: map['category_group'] as String?,
      categoryName: map['category_name'] as String?,
      productName: map['product_name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num).toDouble(),
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      image: map['image'] as String? ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      totalSold: (map['total_sold'] as num?)?.toInt() ?? 0,
      craftType: map['craft_type'] as String?,
      material: map['material'] as String?,
      occasion: map['occasion'] as String?,
      discountPercent: (map['discount_percent'] as num?)?.toInt() ?? 0,
      freeShipping: map['free_shipping'] as bool? ?? false,
      codAvailable: map['cod_available'] as bool? ?? false,
      makingProcess: map['making_process'] is Map
          ? MakingProcessModel.fromMap(
              Map<String, dynamic>.from(map['making_process'] as Map),
            )
          : null,
      media: ((map['media'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ProductMediaModel.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      tags: ((map['tags'] as List?) ?? const [])
          .map((tag) => tag.toString())
          .toList(),
      pricingMode: map['pricing_mode'] as String? ?? 'single',
      options: ((map['options'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ProductOptionModel.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}
