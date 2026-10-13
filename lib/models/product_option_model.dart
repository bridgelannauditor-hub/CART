class ProductOptionModel {
  final String id;
  final String name;
  final String image;
  final double price;
  final int stock;
  final bool isDefault;

  const ProductOptionModel({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.stock,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'image': image,
    'price': price,
    'stock': stock,
    'isDefault': isDefault,
  };

  factory ProductOptionModel.fromMap(Map<String, dynamic> map) {
    return ProductOptionModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      image: map['image'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      isDefault: map['isDefault'] as bool? ?? false,
    );
  }
}
