import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/category_model.dart';

/// A tappable field that opens a bottom sheet listing categories
/// grouped under their parent group (e.g. "Fiber and Textile Crafts"
/// -> Knitting, Crochet, ...). Used by the Add/Edit Product screens
/// so sellers pick a Category / Subcategory instead of one flat list.
class CategoryPickerField extends StatelessWidget {
  final Future<List<CategoryModel>> categoriesFuture;
  final int? selectedCategoryId;
  final ValueChanged<int?> onChanged;

  const CategoryPickerField({
    super.key,
    required this.categoriesFuture,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  Map<String, List<CategoryModel>> _grouped(List<CategoryModel> categories) {
    final Map<String, List<CategoryModel>> grouped = {};

    for (final category in categories) {
      final group =
          (category.categoryGroup == null ||
              category.categoryGroup!.trim().isEmpty)
          ? "Other"
          : category.categoryGroup!;

      grouped.putIfAbsent(group, () => []).add(category);
    }

    return grouped;
  }

  Future<void> _openPicker(
    BuildContext context,
    List<CategoryModel> categories,
  ) async {
    final grouped = _grouped(categories);

    final selected = await showModalBottomSheet<CategoryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Select a Category",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        for (final category in entry.value)
                          ListTile(
                            dense: true,
                            title: Text(
                              category.categoryName,
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            trailing: category.id == selectedCategoryId
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                    size: 20,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, category),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      onChanged(selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CategoryModel>>(
      future: categoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 55,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          );
        }

        final categories = snapshot.data ?? const <CategoryModel>[];

        if (categories.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              "No categories available yet.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        CategoryModel? selectedCategory;
        for (final category in categories) {
          if (category.id == selectedCategoryId) {
            selectedCategory = category;
            break;
          }
        }

        return InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _openPicker(context, categories),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: selectedCategory == null
                      ? const Text(
                          "Select a category",
                          style: TextStyle(color: AppColors.textSecondary),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (selectedCategory.categoryGroup != null &&
                                selectedCategory.categoryGroup!
                                    .trim()
                                    .isNotEmpty)
                              Text(
                                selectedCategory.categoryGroup!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            Text(
                              selectedCategory.categoryName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
