import '../data/product_taxonomy.dart';
import '../models/category_model.dart';

class CategoryService {
  /// Categories are static, fixed data (see data/product_taxonomy.dart) —
  /// not something users create or edit — so there's no need to store or
  /// fetch them from any database. This flattens the same
  /// main-category -> subcategory structure that used to be copied into
  /// sqflite on first launch, using the same deterministic ordering so
  /// existing category IDs referenced anywhere (e.g. in Firestore
  /// products) keep pointing at the same category.
  static final List<CategoryModel> _categories = _buildCategories();

  static List<CategoryModel> _buildCategories() {
    final list = <CategoryModel>[];
    var nextId = 1;

    for (final main in mainCategories) {
      for (final sub in main.subcategories) {
        list.add(
          CategoryModel(
            id: nextId++,
            categoryName: sub,
            categoryImage: "",
            categoryGroup: main.name,
          ),
        );
      }
    }

    return list;
  }

  Future<List<CategoryModel>> getCategories() async {
    return _categories;
  }

  CategoryModel? getCategoryById(int id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}
