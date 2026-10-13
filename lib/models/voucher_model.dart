import 'dart:math' as math;

class VoucherModel {
  final String id;
  final Map<String, dynamic> data;
  VoucherModel(this.id, this.data);
  int get sellerId => (data['sellerId'] as num).toInt();
  String get sellerName => data['sellerName'] as String? ?? 'Shop';
  String get label => data['type'] == 'percentage'
      ? '${data['value']}% off'
      : '₱${data['value']} off';
  double get minimum => (data['minimum'] as num).toDouble();
  DateTime get expiresAt => data['expiresAt'] as DateTime;
  String statusAt(DateTime now) => data['orderId'] != null
      ? 'Used'
      : !now.isBefore(expiresAt)
      ? 'Expired'
      : 'Available';
  double discount(double subtotal, DateTime now) {
    if (statusAt(now) != 'Available' || subtotal < minimum || subtotal <= 0) {
      return 0;
    }
    var amount = (data['value'] as num).toDouble();
    if (data['type'] == 'percentage') {
      amount = subtotal * amount / 100;
      final maximum = (data['maximum'] as num?)?.toDouble();
      if (maximum != null) amount = math.min(amount, maximum);
    }
    return (math.min(amount, subtotal) * 100).round() / 100;
  }
}

bool campaignCanClaim(Map<String, dynamic> data, DateTime now) =>
    data['status'] == 'active' &&
    !now.isBefore(data['startsAt'] as DateTime) &&
    now.isBefore(data['expiresAt'] as DateTime) &&
    (data['claimed'] as num) < (data['quantity'] as num);
