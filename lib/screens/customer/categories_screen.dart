import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/product_taxonomy.dart';
import '../../widgets/bottom_navbar.dart';
import 'subcategory_screen.dart';

/// Top of the browse flow: shows the 8 customer-facing main
/// categories (see data/product_taxonomy.dart). Tapping one opens
/// [SubcategoryScreen] to narrow down further, or browse "All".
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Explore Crafts",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: mainCategories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final category = mainCategories[index];

            return _CategoryTile(
              name: category.name,
              icon: category.icon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubcategoryScreen(category: category),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: const BottomNavbar(currentIndex: 1),
    );
  }
}

// =========================================================
// CATEGORY TILE
// =========================================================

class _CategoryTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.name,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
