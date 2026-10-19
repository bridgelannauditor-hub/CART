import 'dart:math';

enum FlashSaleStatus { scheduled, live, soldOut, ended, cancelled }

/// A Marketing Centre flash sale: a scheduled percent-off promotion for one
/// product with its own promo stock and per-customer purchase limit. The
/// server owns the rules; this model only mirrors them for display.
class FlashSaleModel {
  final int id;
  final int sellerId;
  final int productId;
  final int discountPercent;
  final int promoStock;
  final int sold;
  final int perCustomerLimit;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? cancelledAt;

  const FlashSaleModel({
    required this.id,
    required this.sellerId,
    required this.productId,
    required this.discountPercent,
    required this.promoStock,
    required this.sold,
    required this.perCustomerLimit,
    required this.startsAt,
    required this.endsAt,
    this.cancelledAt,
  });

  int get remaining => max(promoStock - sold, 0);

  FlashSaleStatus statusAt(DateTime now) {
    if (cancelledAt != null) return FlashSaleStatus.cancelled;
    if (now.isBefore(startsAt)) return FlashSaleStatus.scheduled;
    if (!now.isBefore(endsAt)) return FlashSaleStatus.ended;
    if (remaining == 0) return FlashSaleStatus.soldOut;
    return FlashSaleStatus.live;
  }

  bool isLiveAt(DateTime now) => statusAt(now) == FlashSaleStatus.live;

  /// Flash prices replace the regular discount; rounded to centavos like
  /// the server.
  double priceFor(double basePrice) {
    final discounted = basePrice * (100 - discountPercent) / 100;
    return (discounted * 100).roundToDouble() / 100;
  }

  factory FlashSaleModel.fromSupabaseMap(Map<String, dynamic> map) {
    DateTime parse(String key) => DateTime.parse(map[key] as String).toLocal();
    return FlashSaleModel(
      id: (map['id'] as num).toInt(),
      sellerId: (map['seller_id'] as num).toInt(),
      productId: (map['product_id'] as num).toInt(),
      discountPercent: (map['discount_percent'] as num).toInt(),
      promoStock: (map['promo_stock'] as num).toInt(),
      sold: (map['sold'] as num).toInt(),
      perCustomerLimit: (map['per_customer_limit'] as num).toInt(),
      startsAt: parse('starts_at'),
      endsAt: parse('ends_at'),
      cancelledAt: map['cancelled_at'] == null ? null : parse('cancelled_at'),
    );
  }
}

/// Whether one of the seller's products can run a flash sale, as decided by
/// the server (listing age, delivered sales, recent price changes).
class FlashSaleEligibility {
  final int productId;
  final bool eligible;
  final List<String> reasons;
  final int minDiscountPercent;
  final int maxPromoStock;

  const FlashSaleEligibility({
    required this.productId,
    required this.eligible,
    required this.reasons,
    required this.minDiscountPercent,
    required this.maxPromoStock,
  });

  factory FlashSaleEligibility.fromMap(Map<String, dynamic> map) {
    return FlashSaleEligibility(
      productId: (map['product_id'] as num).toInt(),
      eligible: map['eligible'] as bool? ?? false,
      reasons: ((map['reasons'] as List?) ?? const [])
          .map((reason) => reason.toString())
          .toList(),
      minDiscountPercent: (map['min_discount_percent'] as num?)?.toInt() ?? 1,
      maxPromoStock: (map['max_promo_stock'] as num?)?.toInt() ?? 0,
    );
  }
}
