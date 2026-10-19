import 'package:craft_of_love/models/flash_sale_model.dart';
import 'package:craft_of_love/models/product_model.dart';
import 'package:craft_of_love/models/product_option_model.dart';
import 'package:flutter_test/flutter_test.dart';

FlashSaleModel sale({
  required DateTime startsAt,
  required DateTime endsAt,
  int discountPercent = 20,
  int promoStock = 5,
  int sold = 0,
  DateTime? cancelledAt,
}) => FlashSaleModel(
  id: 1,
  sellerId: 1,
  productId: 1,
  discountPercent: discountPercent,
  promoStock: promoStock,
  sold: sold,
  perCustomerLimit: 2,
  startsAt: startsAt,
  endsAt: endsAt,
  cancelledAt: cancelledAt,
);

ProductModel product({int discountPercent = 0, FlashSaleModel? flashSale}) =>
    ProductModel(
      id: 1,
      sellerId: 1,
      categoryId: 1,
      productName: 'Test craft',
      description: '',
      price: 1000,
      stock: 10,
      image: '',
      discountPercent: discountPercent,
      flashSale: flashSale,
    );

void main() {
  final now = DateTime.now();
  final live = sale(
    startsAt: now.subtract(const Duration(minutes: 5)),
    endsAt: now.add(const Duration(hours: 1)),
  );

  test('status follows the schedule, promo stock and cancellation', () {
    final at = DateTime(2026, 10, 18, 12);
    FlashSaleModel make({int sold = 0, DateTime? cancelledAt}) => sale(
      startsAt: DateTime(2026, 10, 18, 10),
      endsAt: DateTime(2026, 10, 18, 13),
      sold: sold,
      cancelledAt: cancelledAt,
    );

    expect(
      make().statusAt(DateTime(2026, 10, 18, 9)),
      FlashSaleStatus.scheduled,
    );
    expect(make().statusAt(at), FlashSaleStatus.live);
    expect(make(sold: 5).statusAt(at), FlashSaleStatus.soldOut);
    expect(
      make().statusAt(DateTime(2026, 10, 18, 13)),
      FlashSaleStatus.ended,
    );
    expect(make(cancelledAt: at).statusAt(at), FlashSaleStatus.cancelled);
  });

  test('a live flash sale replaces the regular discount', () {
    final item = product(discountPercent: 10, flashSale: live);

    expect(item.liveFlashSale, isNotNull);
    expect(item.hasDiscount, isTrue);
    expect(item.effectivePrice, 800);
    expect(item.regularPriceFor(1000), 900);
    expect(item.activeDiscountPercent, 20);
  });

  test('an ended flash sale falls back to the regular price', () {
    final ended = sale(
      startsAt: now.subtract(const Duration(hours: 3)),
      endsAt: now.subtract(const Duration(minutes: 1)),
    );
    final item = product(discountPercent: 10, flashSale: ended);

    expect(item.liveFlashSale, isNull);
    expect(item.effectivePrice, 900);
    expect(item.activeDiscountPercent, 10);
  });

  test('a sold-out flash sale no longer applies', () {
    final soldOut = sale(
      startsAt: now.subtract(const Duration(minutes: 5)),
      endsAt: now.add(const Duration(hours: 1)),
      sold: 5,
    );

    expect(product(flashSale: soldOut).effectivePrice, 1000);
  });

  test('flash prices apply to each picture price and round to centavos', () {
    final item = ProductModel(
      sellerId: 1,
      categoryId: 1,
      productName: 'Picture tote',
      description: '',
      price: 500,
      stock: 20,
      image: '',
      pricingMode: 'per_image',
      options: const [
        ProductOptionModel(
          id: 'blue',
          name: 'Blue',
          image: '',
          price: 333.33,
          stock: 10,
          isDefault: true,
        ),
      ],
      flashSale: sale(
        startsAt: now.subtract(const Duration(minutes: 5)),
        endsAt: now.add(const Duration(hours: 1)),
        discountPercent: 30,
      ),
    );

    expect(item.discountedPriceFor(item.options.first.price), 233.33);
  });

  test('withFlashSale keeps every other product field', () {
    final base = product(discountPercent: 15);
    final copy = base.withFlashSale(live);

    expect(copy.productName, base.productName);
    expect(copy.discountPercent, 15);
    expect(copy.flashSale, same(live));
  });
}
