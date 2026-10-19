import 'package:flutter_test/flutter_test.dart';
import 'package:craft_of_love/models/product_model.dart';

ProductModel productWithDiscount(int discountPercent) => ProductModel(
  sellerId: 1,
  categoryId: 1,
  productName: 'Test craft',
  description: '',
  price: 500,
  stock: 1,
  image: '',
  discountPercent: discountPercent,
);

void main() {
  test('effectivePrice applies the seller discount to the base price', () {
    final product = productWithDiscount(20);

    expect(product.hasDiscount, isTrue);
    expect(product.effectivePrice, 400);
  });

  test('an absent discount keeps the base price', () {
    expect(productWithDiscount(0).effectivePrice, 500);
  });

  test('a 100 percent discount produces a zero price', () {
    final product = productWithDiscount(100);

    expect(product.hasDiscount, isTrue);
    expect(product.effectivePrice, 0);
  });
}
