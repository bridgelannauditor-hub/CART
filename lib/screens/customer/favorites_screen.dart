import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';
import 'product_details_screen.dart';

/// Grid of every product the customer has favorited (heart icon on
/// the product details screen), with a quick way to unfavorite
/// straight from the card.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ProductRepository _productRepository = ProductRepository();
  List<ProductModel> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SessionService.userId;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final favoriteIds = await DatabaseHelper.instance.getFavoriteProductIds(
      userId,
    );
    final fetched = await _productRepository.getProductsByIds(favoriteIds);

    // getProductsByIds doesn't preserve input order, so re-sort to match
    // favoriteIds (newest-favorited first).
    final byId = {for (final p in fetched) p.id: p};
    final ordered = favoriteIds
        .map((id) => byId[id])
        .whereType<ProductModel>()
        .toList();

    if (!mounted) return;

    setState(() {
      _products = ordered;
      _isLoading = false;
    });
  }

  Future<void> _removeFavorite(ProductModel product) async {
    final userId = SessionService.userId;
    if (userId == null || product.id == null) return;

    // Optimistically remove from the grid, then persist.
    setState(() => _products.removeWhere((p) => p.id == product.id));

    await DatabaseHelper.instance.removeFavorite(userId, product.id!);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Removed \"${product.productName}\" from favorites"),
        action: SnackBarAction(
          label: "UNDO",
          onPressed: () async {
            await DatabaseHelper.instance.toggleFavorite(userId, product.id!);
            _load();
          },
        ),
      ),
    );
  }

  void _openProduct(ProductModel product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Favorites",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _products.isEmpty
            ? const _EmptyFavorites()
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.70,
                  ),
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return _FavoriteCard(
                      product: product,
                      onTap: () => _openProduct(product),
                      onRemove: () => _removeFavorite(product),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FavoriteCard({
    required this.product,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProductImage(
              path: product.image,
              fit: BoxFit.cover,
              placeholder: Container(
                color: AppColors.lightGrey,
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),

            // Remove-from-favorites heart button.
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.92),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.error,
                    size: 17,
                  ),
                ),
              ),
            ),

            // Bottom info gradient.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 35, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "₱${product.price.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "No favorites yet",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Tap the heart icon on any product to save it here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
