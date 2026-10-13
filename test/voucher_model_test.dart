import 'package:flutter_test/flutter_test.dart';
import 'package:craft_of_love/models/voucher_model.dart';

void main() {
  final now = DateTime(2026, 10, 6);
  Map<String, dynamic> config() => {
    'sellerId': 1,
    'sellerName': 'Craft Haven',
    'type': 'percentage',
    'value': 10,
    'minimum': 500,
    'maximum': 100,
    'orderId': null,
    'status': 'active',
    'claimed': 0,
    'quantity': 2,
    'startsAt': now,
    'expiresAt': now.add(const Duration(days: 7)),
  };
  test('minimum and percentage cap apply to the seller subtotal', () {
    final v = VoucherModel('a', config());
    expect(v.discount(499.99, now), 0);
    expect(v.discount(500, now), 50);
    expect(v.discount(2000, now), 100);
  });
  test('fixed discounts never exceed seller subtotal', () {
    final v = VoucherModel('a', {...config(), 'type': 'fixed', 'value': 800});
    expect(v.discount(500, now), 500);
  });
  test('used and expired vouchers cannot be redeemed', () {
    final v = VoucherModel('a', config());
    expect(v.discount(1000, v.expiresAt), 0);
    expect(v.statusAt(v.expiresAt), 'Expired');
    final used = VoucherModel('b', {...config(), 'orderId': 3});
    expect(used.discount(1000, now), 0);
    expect(used.statusAt(v.expiresAt), 'Used');
  });
  test('campaign dates, pause, end and capacity block issuance', () {
    expect(campaignCanClaim(config(), now), isTrue);
    expect(
      campaignCanClaim(config(), now.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      campaignCanClaim(config(), now.add(const Duration(days: 7))),
      isFalse,
    );
    for (final status in ['paused', 'ended']) {
      expect(campaignCanClaim({...config(), 'status': status}, now), isFalse);
    }
    expect(campaignCanClaim({...config(), 'claimed': 2}, now), isFalse);
  });
  test('discount rounds to centavos', () {
    expect(VoucherModel('a', config()).discount(555.55, now), 55.56);
  });
}
