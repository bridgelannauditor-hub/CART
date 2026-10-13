import '../database/tables.dart';

class CategoryModel {
  final int? id;
  final String categoryName;
  final String categoryImage;
  final String? categoryGroup;

  CategoryModel({
    this.id,
    required this.categoryName,
    required this.categoryImage,
    this.categoryGroup,
  });

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.categoryName: categoryName,
      DBTables.categoryImage: categoryImage,
      DBTables.categoryGroup: categoryGroup,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map[DBTables.id],
      categoryName: map[DBTables.categoryName],
      categoryImage: map[DBTables.categoryImage] ?? '',
      categoryGroup: map[DBTables.categoryGroup],
    );
  }
}
