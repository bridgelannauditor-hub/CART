import '../database/tables.dart';

enum ProductMediaType { image, video }

class ProductMediaModel {
  final int? id;
  final int productId;
  final ProductMediaType type;
  final String path;
  final int position;

  ProductMediaModel({
    this.id,
    required this.productId,
    required this.type,
    required this.path,
    required this.position,
  });

  Map<String, dynamic> toMap() {
    return {
      DBTables.mediaProductId: productId,
      DBTables.mediaType: type == ProductMediaType.video ? "video" : "image",
      DBTables.mediaPath: path,
      DBTables.mediaPosition: position,
    };
  }

  factory ProductMediaModel.fromMap(Map<String, dynamic> map) {
    return ProductMediaModel(
      id: map[DBTables.id],
      productId: map[DBTables.mediaProductId],
      type: map[DBTables.mediaType] == "video"
          ? ProductMediaType.video
          : ProductMediaType.image,
      path: map[DBTables.mediaPath] ?? '',
      position: map[DBTables.mediaPosition] ?? 0,
    );
  }
}
