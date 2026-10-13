class CustomerOrderItemModel {
  final int itemId;
  final int orderId;
  final int productId;
  final int quantity;
  final double itemPrice;
  final String status;
  final String orderDate;
  final String productName;
  final String productImage;
  final int? sellerId;
  final String sellerFirstName;
  final String sellerLastName;
  final String? optionId;
  final String? optionName;
  final String? optionImage;

  CustomerOrderItemModel({
    required this.itemId,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.itemPrice,
    required this.status,
    required this.orderDate,
    required this.productName,
    required this.productImage,
    required this.sellerId,
    required this.sellerFirstName,
    required this.sellerLastName,
    this.optionId,
    this.optionName,
    this.optionImage,
  });

  String get sellerName {
    final full = "$sellerFirstName $sellerLastName".trim();
    return full.isEmpty ? "Unknown seller" : full;
  }

  double get lineTotal => itemPrice * quantity;

  factory CustomerOrderItemModel.fromMap(Map<String, dynamic> map) {
    return CustomerOrderItemModel(
      itemId: map['item_id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      quantity: map['quantity'],
      itemPrice: (map['item_price'] as num).toDouble(),
      status: map['status'] ?? 'Pending',
      orderDate: map['order_date'] ?? '',
      productName: map['product_name'] ?? 'Product no longer available',
      productImage: map['product_image'] ?? '',
      sellerId: map['seller_id'],
      sellerFirstName: map['seller_first_name'] ?? '',
      sellerLastName: map['seller_last_name'] ?? '',
      optionId: map['option_id'] as String?,
      optionName: map['option_name'] as String?,
      optionImage: map['option_image'] as String?,
    );
  }
}
