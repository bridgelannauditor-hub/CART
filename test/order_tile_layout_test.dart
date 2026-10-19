import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:craft_of_love/models/customer_order_item_model.dart';
import 'package:craft_of_love/screens/customer/orders_screen.dart';

CustomerOrderItemModel _item(String status) => CustomerOrderItemModel(
  itemId: 1,
  orderId: 7,
  productId: 3,
  quantity: 2,
  itemPrice: 99,
  status: status,
  orderDate: '2026-10-18T13:59:13.753886+00:00',
  productName: 'crochet bouquet',
  productImage: '',
  sellerId: 19,
  sellerFirstName: 'Bridgels',
  sellerLastName: '',
);

Future<void> _pumpTile(WidgetTester tester, String status) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            OrderTile(
              item: _item(status),
              onMessageSeller: () {},
              onRateProduct: () {},
              onBuyAgain: () {},
              onTrackOrder: () {},
              onCancelOrder: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final status in const [
    'Pending',
    'Preparing',
    'Shipped',
    'Out for Delivery',
    'Delivered',
    'Cancelled',
  ]) {
    testWidgets('a $status order tile is laid out and visible', (tester) async {
      await _pumpTile(tester, status);
      expect(tester.takeException(), isNull);
      expect(find.text('crochet bouquet'), findsOneWidget);
      final size = tester.getSize(find.byType(OrderTile));
      expect(size.width.isFinite && size.height.isFinite, isTrue);
      expect(size.height, greaterThan(100));
    });
  }

  testWidgets('a Delivered tile offers Rate Product and Buy Again', (
    tester,
  ) async {
    await _pumpTile(tester, 'Delivered');
    expect(find.text('Rate Product'), findsOneWidget);
    expect(find.text('Buy Again'), findsOneWidget);
  });
}
