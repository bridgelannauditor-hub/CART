import 'package:flutter/material.dart';

import '../../utils/routes.dart';
import '../../services/session_service.dart';

import '../../database/database_helper.dart';
import '../../repositories/product_repository.dart';
import '../../models/cart_item_model.dart';
import '../../models/product_model.dart';
import '../../constants/app_colors.dart';
import '../../widgets/bottom_navbar.dart';

import '../../widgets/product_card.dart';
import '../../widgets/product_image.dart';
import '../../widgets/search_bar_widget.dart';
import '../../widgets/craft_video_carousel.dart';
import '../../data/craft_categories.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/search_history_repository.dart';
import 'notifications_screen.dart';
import 'checkout_screen.dart';
import 'craft_subcategory_screen.dart';
import 'product_details_screen.dart';
import '../ai/ai_assistant_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProductRepository _productRepository = ProductRepository();
  final NotificationRepository _notificationRepository =
      NotificationRepository();
  final OrderRepository _orderRepository = OrderRepository();
  final SearchHistoryRepository _searchHistoryRepository =
      SearchHistoryRepository();
  final TextEditingController _searchController = TextEditingController();

  int cartCount = 0;
  int unreadNotifications = 0;

  List<ProductModel> _allProducts = [];
  List<(ProductModel, int)> _bestSellers = [];
  bool _isLoadingBestSellers = true;

  bool _isLoadingProducts = true;
  bool _isLoadingMoreProducts = false;
  bool _hasMoreProducts = true;
  int? _productCursor;
  String _searchQuery = '';
  List<String> _recentSearches = [];
  bool _showRecentSearches = false;

  String _selectedCraftFilter = "All";

  final List<String> _craftFilters = const [
    "All",
    "Bouquet",
    "Crochet",
    "Origami",
    "Bracelet",
    "Earring",
    "Bags",
    "Gifts",
    "Knitted",
    "Beaded",
    "Sculpting",
    "Pottery",
    "Wood",
    "Decoration",
    "Embroidery",
  ];

  @override
  void initState() {
    super.initState();

    loadCartCount();
    loadUnreadNotifications();
    _loadProducts();
    _loadBestSellers();
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // REFRESH EVERYTHING
  // =========================================================

  Future<void> _refreshAll() async {
    await Future.wait([
      loadCartCount(),
      loadUnreadNotifications(),
      _loadProducts(),
      _loadBestSellers(),
    ]);
  }

  // =========================================================
  // LOAD BEST SELLERS
  // =========================================================

  Future<void> _loadBestSellers() async {
    if (!mounted) return;

    setState(() => _isLoadingBestSellers = true);

    final result = await _orderRepository.getBestSellingProducts(limit: 10);

    if (!mounted) return;

    setState(() {
      _bestSellers = result;
      _isLoadingBestSellers = false;
    });
  }

  // =========================================================
  // LOAD PRODUCTS
  // =========================================================

  Future<void> _loadProducts({bool reset = true}) async {
    if (!mounted) return;
    if (!reset && (_isLoadingMoreProducts || !_hasMoreProducts)) return;

    setState(() {
      if (reset) {
        _isLoadingProducts = true;
        _productCursor = null;
        _hasMoreProducts = true;
      } else {
        _isLoadingMoreProducts = true;
      }
    });

    try {
      final page = await _productRepository.getProductsPage(
        afterProductId: reset ? null : _productCursor,
      );
      final result = [...page.items]..shuffle();

      if (!mounted) return;

      setState(() {
        if (reset) {
          _allProducts = result;
        } else {
          final existingIds = _allProducts.map((product) => product.id).toSet();
          _allProducts.addAll(
            result.where((product) => !existingIds.contains(product.id)),
          );
        }
        _productCursor = page.nextProductId;
        _hasMoreProducts = page.hasMore;
        _isLoadingProducts = false;
        _isLoadingMoreProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingProducts = false;
        _isLoadingMoreProducts = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Products could not be loaded.')),
      );
    }
  }

  // =========================================================
  // SEARCH
  // =========================================================

  Future<void> _loadRecentSearches() async {
    try {
      final searches = await _searchHistoryRepository.getRecentSearches();
      if (!mounted) return;
      setState(() => _recentSearches = searches);
    } catch (_) {
      // Search remains fully usable if history cannot be loaded.
    }
  }

  Future<void> _storeSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    final updated = [
      query,
      ..._recentSearches.where(
        (item) => item.toLowerCase() != query.toLowerCase(),
      ),
    ].take(10).toList();
    if (mounted) {
      setState(() {
        _recentSearches = updated;
        _showRecentSearches = false;
      });
    }
    try {
      await _searchHistoryRepository.saveRecentSearches(updated);
    } catch (_) {
      // Keep the optimistic in-memory history when Firestore is offline.
    }
  }

  Future<void> _removeRecentSearch(String value) async {
    final updated = _recentSearches.where((item) => item != value).toList();
    setState(() => _recentSearches = updated);
    try {
      await _searchHistoryRepository.saveRecentSearches(updated);
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    setState(() => _recentSearches = []);
    try {
      await _searchHistoryRepository.saveRecentSearches([]);
    } catch (_) {}
  }

  void _useRecentSearch(String value) {
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
    setState(() {
      _searchQuery = value;
      _showRecentSearches = false;
    });
    FocusScope.of(context).unfocus();
    _storeSearch(value);
  }

  List<ProductModel> get _displayedProducts {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _allProducts;
    }

    return _allProducts.where((product) {
      return product.productName.toLowerCase().contains(query);
    }).toList();
  }

  // =========================================================
  // CRAFT FILTER
  // =========================================================

  List<ProductModel> get _craftFilteredProducts {
    if (_selectedCraftFilter == "All") {
      return _allProducts;
    }

    final filter = _selectedCraftFilter.toLowerCase();

    return _allProducts.where((product) {
      return product.productName.toLowerCase().contains(filter);
    }).toList();
  }

  // =========================================================
  // LOAD UNREAD NOTIFICATIONS
  // =========================================================

  Future<void> loadUnreadNotifications() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;

      setState(() {
        unreadNotifications = 0;
      });

      return;
    }

    final count = await _notificationRepository.getUnreadCount(userId);

    if (!mounted) return;

    setState(() {
      unreadNotifications = count;
    });
  }

  // =========================================================
  // LOAD CART COUNT
  // =========================================================

  Future<void> loadCartCount() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;

      setState(() {
        cartCount = 0;
      });

      return;
    }

    final count = await DatabaseHelper.instance.getCartItemCount(userId);

    if (!mounted) return;

    setState(() {
      cartCount = count;
    });
  }

  // =========================================================
  // PRODUCT CARD
  // =========================================================

  Widget _buildProductCard(ProductModel product) {
    return ProductCard(
      name: product.productName,
      price: "₱${product.price.toStringAsFixed(0)}",
      image: product.image,
      rating: product.rating,
      soldCount: product.totalSold,
      discountPercent: product.discountPercent,
      freeShipping: product.freeShipping,
      codAvailable: product.codAvailable,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(product: product),
          ),
        );
      },
    );
  }

  void _viewAllBestSellers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BestSellersScreen(products: _bestSellers),
      ),
    );
  }

  Future<void> _addBestSellerToCart(ProductModel product) async {
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    if (product.id == null || product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is out of stock.')),
      );
      return;
    }

    await DatabaseHelper.instance.addToCart(userId, product.id!, 1);
    if (!mounted) return;
    await loadCartCount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.productName} added to cart!')),
    );
  }

  Future<void> _buyBestSeller(ProductModel product) async {
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    if (product.id == null || product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is out of stock.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          selectedItems: [
            CartItemModel(userId: userId, productId: product.id!, quantity: 1),
          ],
        ),
      ),
    );
    if (mounted) await loadCartCount();
  }

  // =========================================================
  // EMPTY PRODUCT MESSAGE
  // =========================================================

  Widget _buildEmptyProducts({required String message}) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  // =========================================================
  // PRODUCT GRID
  // =========================================================

  Widget _buildProductGrid(List<ProductModel> products) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.70,
      ),
      itemBuilder: (context, index) {
        final product = products[index];

        return _buildProductCard(product);
      },
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.trim().isNotEmpty;
    final displayedProducts = _displayedProducts;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'craft-assistant',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
          );
        },
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Ask AI'),
      ),

      // =====================================================
      // BOTTOM NAVIGATION
      // =====================================================
      bottomNavigationBar: const BottomNavbar(currentIndex: 0),

      // =====================================================
      // BODY
      // =====================================================
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refreshAll,

          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),

            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                // =================================================
                // HEADER
                // SEARCH + NOTIFICATIONS + CART
                // =================================================

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,

                  children: [
                    // =================================================
                    // SEARCH BAR
                    // =================================================

                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),

                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),

                        child: SearchBarWidget(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                              _showRecentSearches = value.trim().isEmpty;
                            });
                          },
                          onSubmitted: (value) {
                            _storeSearch(value);
                            FocusScope.of(context).unfocus();
                          },
                          onFocusChanged: (hasFocus) {
                            if (!hasFocus) {
                              _storeSearch(_searchController.text);
                            }
                            if (mounted) {
                              setState(() {
                                _showRecentSearches =
                                    hasFocus &&
                                    _searchController.text.trim().isEmpty;
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // =================================================
                    // NOTIFICATIONS
                    // =================================================
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );

                        if (!mounted) return;

                        await loadUnreadNotifications();
                      },

                      child: Stack(
                        clipBehavior: Clip.none,

                        children: [
                          Container(
                            width: 46,
                            height: 46,

                            alignment: Alignment.center,

                            decoration: BoxDecoration(
                              shape: BoxShape.circle,

                              color: Colors.white,

                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),

                            child: const Icon(
                              Icons.notifications_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),

                          // Notification badge
                          if (unreadNotifications > 0)
                            Positioned(
                              top: -4,
                              right: -4,

                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),

                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),

                                decoration: const BoxDecoration(
                                  color: AppColors.secondary,
                                  shape: BoxShape.circle,
                                ),

                                child: Text(
                                  unreadNotifications > 99
                                      ? '99+'
                                      : '$unreadNotifications',

                                  textAlign: TextAlign.center,

                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // =================================================
                    // CART
                    // =================================================
                    GestureDetector(
                      onTap: () async {
                        await Navigator.pushNamed(context, AppRoutes.cart);

                        if (!mounted) return;

                        await loadCartCount();
                      },

                      child: Stack(
                        clipBehavior: Clip.none,

                        children: [
                          Container(
                            width: 46,
                            height: 46,

                            alignment: Alignment.center,

                            decoration: BoxDecoration(
                              shape: BoxShape.circle,

                              color: Colors.white,

                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),

                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),

                          // Cart badge
                          if (cartCount > 0)
                            Positioned(
                              top: -4,
                              right: -4,

                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),

                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),

                                decoration: const BoxDecoration(
                                  color: AppColors.secondary,
                                  shape: BoxShape.circle,
                                ),

                                child: Text(
                                  cartCount > 99 ? '99+' : '$cartCount',

                                  textAlign: TextAlign.center,

                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (_showRecentSearches && _recentSearches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.lightGrey),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Recent searches',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _clearRecentSearches,
                              child: const Text(
                                'Clear all',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: _recentSearches
                              .map(
                                (search) => InputChip(
                                  avatar: const Icon(
                                    Icons.search_rounded,
                                    size: 15,
                                  ),
                                  label: Text(search),
                                  labelStyle: const TextStyle(fontSize: 11),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _useRecentSearch(search),
                                  onDeleted: () => _removeRecentSearch(search),
                                  deleteIcon: const Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // =================================================
                // EXPLORE CRAFTS
                // =================================================
                const Text(
                  "Explore Crafts",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  "Tap a category to see its techniques.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 14),

                // =================================================
                // CRAFT VIDEO CAROUSEL
                // =================================================
                CraftVideoCarousel(
                  onTapGroup: (CraftCategoryGroup group) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CraftSubcategoryScreen(group: group),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // =================================================
                // PRODUCTS
                // =================================================
                if (isSearching) ...[
                  // =================================================
                  // SEARCH RESULTS
                  // =================================================

                  Text(
                    'Results for "${_searchQuery.trim()}"',

                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =================================================
                  // SEARCH LOADING
                  // =================================================
                  if (_isLoadingProducts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),

                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  // =================================================
                  // NO SEARCH RESULTS
                  // =================================================
                  else if (displayedProducts.isEmpty)
                    _buildEmptyProducts(
                      message: 'No products match "${_searchQuery.trim()}".',
                    )
                  // =================================================
                  // SEARCH RESULT GRID
                  // =================================================
                  else
                    _buildProductGrid(displayedProducts),
                ]
                // =====================================================
                // ALL PRODUCTS
                // =====================================================
                else ...[
                  // =================================================
                  // BEST SELLERS THIS MONTH
                  // =================================================

                  if (_isLoadingBestSellers) ...[
                    const _BestSellerSectionHeader(),
                    const SizedBox(height: 12),
                    const SizedBox(
                      height: 222,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (_bestSellers.isNotEmpty) ...[
                    _BestSellerSectionHeader(onViewMore: _viewAllBestSellers),
                    const SizedBox(height: 12),
                    Column(
                      children: List.generate(
                        _bestSellers.length > 3 ? 3 : _bestSellers.length,
                        (index) {
                          final entry = _bestSellers[index];
                          final bestSellerProduct = entry.$1;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index < 2 ? 12 : 0,
                            ),
                            child: _BestSellerCard(
                              rank: index + 1,
                              name: bestSellerProduct.productName,
                              price:
                                  "₱${bestSellerProduct.price.toStringAsFixed(0)}",
                              image: bestSellerProduct.image,
                              rating: bestSellerProduct.rating,
                              soldCount: entry.$2,
                              discountPercent:
                                  bestSellerProduct.discountPercent,
                              freeShipping: bestSellerProduct.freeShipping,
                              codAvailable: bestSellerProduct.codAvailable,
                              isAvailable: bestSellerProduct.stock > 0,
                              onAddToCart: () =>
                                  _addBestSellerToCart(bestSellerProduct),
                              onBuy: () => _buyBestSeller(bestSellerProduct),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProductDetailsScreen(
                                      product: bestSellerProduct,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // =================================================
                  // CRAFT FILTER (slides to the right)
                  // =================================================
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _craftFilters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _craftFilters[index];
                        final isSelected = filter == _selectedCraftFilter;

                        return ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedCraftFilter = filter;
                            });
                          },
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
                            ),
                          ),
                          showCheckmark: false,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // =================================================
                  // PRODUCTS LOADING
                  // =================================================
                  if (_isLoadingProducts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),

                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  // =================================================
                  // NO PRODUCTS
                  // =================================================
                  else if (_allProducts.isEmpty)
                    _buildEmptyProducts(message: "No products yet.")
                  // =================================================
                  // NO CRAFT-FILTER MATCHES
                  // =================================================
                  else if (_craftFilteredProducts.isEmpty)
                    _buildEmptyProducts(
                      message: 'No "$_selectedCraftFilter" products found.',
                    )
                  // =================================================
                  // ALL PRODUCTS GRID
                  // =================================================
                  else
                    _buildProductGrid(_craftFilteredProducts),
                  if (!_isLoadingProducts && _hasMoreProducts)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Center(
                        child: _isLoadingMoreProducts
                            ? const CircularProgressIndicator(
                                color: AppColors.primary,
                              )
                            : OutlinedButton.icon(
                                onPressed: () => _loadProducts(reset: false),
                                icon: const Icon(Icons.expand_more_rounded),
                                label: const Text('Load more products'),
                              ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BestSellerSectionHeader extends StatelessWidget {
  final VoidCallback? onViewMore;

  const _BestSellerSectionHeader({this.onViewMore});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Best Sellers',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (onViewMore != null)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onViewMore,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View more',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 17),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BestSellerCard extends StatelessWidget {
  final int rank;
  final String name;
  final String price;
  final String image;
  final double? rating;
  final int soldCount;
  final int discountPercent;
  final bool freeShipping;
  final bool codAvailable;
  final bool isAvailable;
  final VoidCallback onAddToCart;
  final VoidCallback onBuy;
  final VoidCallback onTap;

  const _BestSellerCard({
    required this.rank,
    required this.name,
    required this.price,
    required this.image,
    this.rating,
    required this.soldCount,
    required this.discountPercent,
    required this.freeShipping,
    required this.codAvailable,
    required this.isAvailable,
    required this.onAddToCart,
    required this.onBuy,
    required this.onTap,
  });

  String? get _originalPrice {
    if (discountPercent <= 0 || discountPercent >= 100) return null;
    final numericPrice = double.tryParse(
      price.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    if (numericPrice == null) return null;
    final original = numericPrice / (1 - discountPercent / 100);
    return '₱${original.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: 88,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: ProductImage(
                  path: image,
                  fit: BoxFit.cover,
                  placeholder: Container(
                    color: AppColors.lightGrey,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: AppColors.textSecondary,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '$soldCount sold',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (freeShipping)
                        const _BestSellerTag(
                          label: 'Free shipping',
                          icon: Icons.local_shipping_outlined,
                          color: Color(0xFF10BFA3),
                        ),
                      if (freeShipping && discountPercent > 0)
                        const SizedBox(width: 5),
                      if (discountPercent > 0)
                        _BestSellerTag(
                          label: '$discountPercent% off',
                          color: Color(0xFFFF6078),
                        )
                      else if (codAvailable)
                        const _BestSellerTag(
                          label: 'COD',
                          color: AppColors.secondary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      if (_originalPrice != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          _originalPrice!,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 105,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        (rating ?? 0).toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      ...List.generate(5, (index) {
                        final ratingValue = rating ?? 0;
                        final IconData icon;
                        if (ratingValue >= index + 1) {
                          icon = Icons.star_rounded;
                        } else if (ratingValue >= index + 0.5) {
                          icon = Icons.star_half_rounded;
                        } else {
                          icon = Icons.star_border_rounded;
                        }
                        return Icon(icon, size: 13, color: Colors.amber);
                      }),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Material(
                              color: isAvailable
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.grey.shade200,
                              child: InkWell(
                                onTap: isAvailable ? onAddToCart : null,
                                child: Center(
                                  child: Icon(
                                    Icons.add_shopping_cart_rounded,
                                    size: 18,
                                    color: isAvailable
                                        ? AppColors.primary
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Material(
                              color: isAvailable
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
                              child: InkWell(
                                onTap: isAvailable ? onBuy : null,
                                child: const Center(
                                  child: Text(
                                    'Buy',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestSellerTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _BestSellerTag({required this.label, this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestSellersScreen extends StatelessWidget {
  final List<(ProductModel, int)> products;

  const _BestSellersScreen({required this.products});

  Future<void> _addToCart(BuildContext context, ProductModel product) async {
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    if (product.id == null || product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is out of stock.')),
      );
      return;
    }

    await DatabaseHelper.instance.addToCart(userId, product.id!, 1);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.productName} added to cart!')),
    );
  }

  Future<void> _buyNow(BuildContext context, ProductModel product) async {
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    if (product.id == null || product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is out of stock.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          selectedItems: [
            CartItemModel(userId: userId, productId: product.id!, quantity: 1),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Best Sellers')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = products[index];
          final product = entry.$1;
          return _BestSellerCard(
            rank: index + 1,
            name: product.productName,
            price: '₱${product.price.toStringAsFixed(0)}',
            image: product.image,
            rating: product.rating,
            soldCount: entry.$2,
            discountPercent: product.discountPercent,
            freeShipping: product.freeShipping,
            codAvailable: product.codAvailable,
            isAvailable: product.stock > 0,
            onAddToCart: () => _addToCart(context, product),
            onBuy: () => _buyNow(context, product),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetailsScreen(product: product),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
