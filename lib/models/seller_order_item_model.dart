class SellerOrderItemModel {
  final int itemId;
  final int orderId;
  final int productId;
  final int quantity;
  final double itemPrice;
  final String status;
  final String orderDate;
  final int customerId;
  final String productName;
  final String productImage;
  final String customerFirstName;
  final String customerLastName;
  final String? optionId;
  final String? optionName;
  final String? optionImage;

  SellerOrderItemModel({
    required this.itemId,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.itemPrice,
    required this.status,
    required this.orderDate,
    required this.customerId,
    required this.productName,
    required this.productImage,
    required this.customerFirstName,
    required this.customerLastName,
    this.optionId,
    this.optionName,
    this.optionImage,
  });

  String get customerName {
    final full = "$customerFirstName $customerLastName".trim();
    return full.isEmpty ? "Unknown customer" : full;
  }

  double get lineTotal => itemPrice * quantity;

  factory SellerOrderItemModel.fromMap(Map<String, dynamic> map) {
    return SellerOrderItemModel(
      itemId: map['item_id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      quantity: map['quantity'],
      itemPrice: (map['item_price'] as num).toDouble(),
      status: map['status'] ?? 'Pending',
      orderDate: map['order_date'] ?? '',
      customerId: map['customer_id'],
      productName: map['product_name'] ?? '',
      productImage: map['product_image'] ?? '',
      customerFirstName: map['customer_first_name'] ?? '',
      customerLastName: map['customer_last_name'] ?? '',
      optionId: map['option_id'] as String?,
      optionName: map['option_name'] as String?,
      optionImage: map['option_image'] as String?,
    );
  }
}
