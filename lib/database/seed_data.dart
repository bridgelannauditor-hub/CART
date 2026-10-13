import 'database_helper.dart';
import '../models/category_model.dart';
import '../data/product_taxonomy.dart';

class SeedData {
  /// Seeds only the category list. No demo sellers or demo products
  /// are created — every product shown anywhere in the app comes
  /// from a real seller who actually uploaded it.
  static Future<void> insertInitialData() async {
    final db = DatabaseHelper.instance;

    // Prevent duplicate seed data
    final categories = await db.getCategories();

    if (categories.isNotEmpty) {
      return;
    }

    // =========================
    // CATEGORIES
    // Flattened from mainCategories (see data/product_taxonomy.dart):
    // each subcategory becomes one row, grouped under its main
    // category name.
    // =========================

    for (final main in mainCategories) {
      for (final sub in main.subcategories) {
        await db.insertCategory(
          CategoryModel(
            categoryName: sub,
            categoryImage: "",
            categoryGroup: main.name,
          ).toMap(),
        );
      }
    }
  }
}
