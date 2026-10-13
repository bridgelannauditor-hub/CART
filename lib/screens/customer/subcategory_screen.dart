import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/product_taxonomy.dart';
import 'category_products_screen.dart';

/// Second step of the browse flow: shows "All" plus each subcategory
/// under the chosen [category]. Tapping either opens
/// [CategoryProductsScreen] filtered accordingly.
class SubcategoryScreen extends StatelessWidget {
  final MainCategory category;

  const SubcategoryScreen({super.key, required this.category});

  void _openProducts(BuildContext context, {String? subcategory}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(
          title: subcategory ?? category.name,
          mainCategory: category.name,
          subcategory: subcategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SubcategoryTile(
              icon: category.icon,
              name: "All ${category.name}",
              onTap: () => _openProducts(context),
            ),
            const SizedBox(height: 10),
            for (final sub in category.subcategories) ...[
              _SubcategoryTile(
                icon: Icons.chevron_right_rounded,
                name: sub,
                onTap: () => _openProducts(context, subcategory: sub),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubcategoryTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final VoidCallback onTap;

  const _SubcategoryTile({
    required this.icon,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
