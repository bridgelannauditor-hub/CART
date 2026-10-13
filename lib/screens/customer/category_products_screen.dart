import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/product_taxonomy.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../widgets/product_card.dart';
import '../../widgets/simple_option_picker_field.dart';
import 'product_details_screen.dart';

/// Product grid for the browse/filter flow. Pass whichever
/// taxonomy filters apply — all are optional so this same screen
/// covers "everything under a main category", "one subcategory",
/// or "every Crochet item regardless of category" (from the craft
/// type carousel on the home screen).
class CategoryProductsScreen extends StatefulWidget {
  final String title;
  final String? mainCategory;
  final String? subcategory;
  final String? craftType;

  const CategoryProductsScreen({
    super.key,
    required this.title,
    this.mainCategory,
    this.subcategory,
    this.craftType,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final ProductRepository _productRepository = ProductRepository();

  List<ProductModel> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int? _productCursor;

  // Additional filters the customer can apply on top of the
  // category/craft-type they arrived with.
  String? _craftType;
  String? _material;
  String? _occasion;

  @override
  void initState() {
    super.initState();
    _craftType = widget.craftType;
    _loadProducts();
  }

  // =========================================================
  // LOAD PRODUCTS
  // =========================================================

  Future<void> _loadProducts({bool reset = true}) async {
    if (!reset && (_isLoadingMore || !_hasMore)) return;
    setState(() {
      if (reset) {
        _isLoading = true;
        _productCursor = null;
        _hasMore = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await _productRepository.getFilteredProductsPage(
        mainCategory: widget.mainCategory,
        subcategory: widget.subcategory,
        craftType: _craftType,
        material: _material,
        occasion: _occasion,
        afterProductId: reset ? null : _productCursor,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _products = page.items;
        } else {
          final ids = _products.map((product) => product.id).toSet();
          _products.addAll(
            page.items.where((product) => !ids.contains(product.id)),
          );
        }
        _productCursor = page.nextProductId;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Products could not be loaded.')),
      );
    }
  }

  bool get _hasActiveFilters =>
      _craftType != null || _material != null || _occasion != null;

  // =========================================================
  // FILTER SHEET
  // =========================================================

  Future<void> _openFilters() async {
    String? craftType = _craftType;
    String? material = _material;
    String? occasion = _occasion;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Filters",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Craft Type",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SimpleOptionPickerField(
                    label: "Craft Type",
                    options: craftTypes,
                    selected: craftType,
                    onChanged: (v) => setSheetState(() => craftType = v),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Material",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SimpleOptionPickerField(
                    label: "Material",
                    options: materials,
                    selected: material,
                    onChanged: (v) => setSheetState(() => material = v),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Occasion",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SimpleOptionPickerField(
                    label: "Occasion",
                    options: occasions,
                    selected: occasion,
                    onChanged: (v) => setSheetState(() => occasion = v),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              craftType = null;
                              material = null;
                              occasion = null;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text("Clear"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _craftType = craftType;
                            _material = material;
                            _occasion = occasion;
                            Navigator.pop(context, true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text("Apply"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied == true) {
      _loadProducts(reset: true);
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _hasActiveFilters
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
            ),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _products.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "No ${widget.title} products yet.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadProducts,
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _products.length + (_hasMore ? 1 : 0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.70,
                  ),
                  itemBuilder: (context, index) {
                    if (index == _products.length) {
                      return Center(
                        child: _isLoadingMore
                            ? const CircularProgressIndicator(
                                color: AppColors.primary,
                              )
                            : OutlinedButton(
                                onPressed: () => _loadProducts(reset: false),
                                child: const Text('Load more'),
                              ),
                      );
                    }
                    final product = _products[index];
                    return ProductCard(
                      name: product.productName,
                      price: "₱${product.price.toStringAsFixed(0)}",
                      image: product.image,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductDetailsScreen(product: product),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}
