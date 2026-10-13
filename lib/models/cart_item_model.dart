import '../database/tables.dart';

class CartItemModel {
  final int? id;
  final int userId;
  final int productId;
  final int quantity;
  final String? optionId;
  final String? optionName;
  final String? optionImage;
  final double? unitPrice;

  const CartItemModel({
    this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    this.optionId,
    this.optionName,
    this.optionImage,
    this.unitPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.cartUserId: userId,
      DBTables.cartProductId: productId,
      DBTables.cartQuantity: quantity,
      DBTables.cartOptionId: optionId ?? '',
      DBTables.cartOptionName: optionName,
      DBTables.cartOptionImage: optionImage,
      DBTables.cartUnitPrice: unitPrice,
    };
  }

  factory CartItemModel.fromMap(Map<String, dynamic> map) {
    return CartItemModel(
      id: map[DBTables.id],
      userId: map[DBTables.cartUserId],
      productId: map[DBTables.cartProductId],
      quantity: map[DBTables.cartQuantity],
      optionId: (map[DBTables.cartOptionId] as String?)?.isEmpty == true
          ? null
          : map[DBTables.cartOptionId] as String?,
      optionName: map[DBTables.cartOptionName] as String?,
      optionImage: map[DBTables.cartOptionImage] as String?,
      unitPrice: (map[DBTables.cartUnitPrice] as num?)?.toDouble(),
    );
  }

  CartItemModel copyWith({
    int? id,
    int? userId,
    int? productId,
    int? quantity,
    String? optionId,
    String? optionName,
    String? optionImage,
    double? unitPrice,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      optionId: optionId ?? this.optionId,
      optionName: optionName ?? this.optionName,
      optionImage: optionImage ?? this.optionImage,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}
