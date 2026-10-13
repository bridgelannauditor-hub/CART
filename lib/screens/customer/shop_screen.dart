import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/craft_categories.dart';
import '../../database/database_helper.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../repositories/shop_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/voucher_repository.dart';
import '../../models/voucher_model.dart';
import 'package:intl/intl.dart';
import '../../services/category_service.dart';
import '../../services/session_service.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_image.dart';
import '../../widgets/rating_stars.dart';
import 'cart_screen.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'product_details_screen.dart';

/// How the "Products" tab list is currently ordered.
enum _ProductSort { recommended, bestseller, newRelease, price }

/// The customer-facing storefront for a single seller — reached by
/// tapping "Visit Shop" from a product's details page.
class ShopScreen extends StatefulWidget {
  final int sellerId;

  const ShopScreen({super.key, required this.sellerId});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  final ShopRepository _shopRepository = ShopRepository();
  final CategoryService _categoryService = CategoryService();

  late final TabController _tabController;

  bool _isLoading = true;
  Map<String, dynamic>? _campaign;

  UserModel? _shop;
  List<ProductModel> _products = [];
  List<ProductModel> _flashSaleProducts = [];
  List<ProductModel> _topProducts = [];
  Map<int, int> _salesByProductId = {};
  Map<int, String> _categoryNamesById = {};

  double _averageRating = 0;
  int _reviewCount = 0;
  int _totalSold = 0;
  int _productCount = 0;
  int _followerCount = 0;
  int? _nextProductId;
  bool _hasMoreProducts = false;
  bool _isLoadingMoreProducts = false;
  bool _isFollowing = false;
  bool _isTogglingFollow = false;

  int cartCount = 0;
  int unreadNotifications = 0;

  _ProductSort _sort = _ProductSort.recommended;
  String? _categoryFilter;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  int? get _viewerId => SessionService.userId;
  bool get _isOwnShop => _viewerId != null && _viewerId == widget.sellerId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // LOAD EVERYTHING
  // =========================================================

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _shopRepository.getShop(widget.sellerId),
      _shopRepository.getShopProductsPage(widget.sellerId),
      _shopRepository.getProductMetrics(widget.sellerId),
      _shopRepository.getFlashSaleProducts(widget.sellerId),
      _shopRepository.getTopProducts(widget.sellerId),
      _shopRepository.getFollowerCount(widget.sellerId),
      _categoryService.getCategories(),
      _loadCartCount(),
      _loadUnreadNotifications(),
    ]);

    _campaign = await VoucherRepository().getCampaign(widget.sellerId);
    bool followingResult = false;
    if (_viewerId != null && !_isOwnShop) {
      followingResult = await _shopRepository.isFollowing(
        _viewerId!,
        widget.sellerId,
      );

      // Log this visit for the seller's "visitors" count. Fire and
      // forget — shouldn't hold up the shop page from loading.
      unawaited(
        _shopRepository
            .recordVisit(_viewerId!, widget.sellerId)
            .catchError((_) {}),
      );
    }

    if (!mounted) return;

    final productPage = results[1] as ProductPage;
    final metrics = results[2] as SellerProductMetrics;
    final products = productPage.items;

    setState(() {
      _shop = results[0] as UserModel?;
      _products = products;
      _flashSaleProducts = results[3] as List<ProductModel>;
      _topProducts = results[4] as List<ProductModel>;
      _salesByProductId = {
        for (final product in products)
          if (product.id != null) product.id!: product.totalSold,
      };
      _averageRating = metrics.averageRating;
      _reviewCount = metrics.reviewCount;
      _totalSold = metrics.unitsSold;
      _productCount = metrics.productCount;
      _nextProductId = productPage.nextProductId;
      _hasMoreProducts = productPage.hasMore;
      _isLoadingMoreProducts = false;
      _followerCount = results[5] as int;
      _categoryNamesById = {
        for (final c in (results[6] as List<CategoryModel>))
          if (c.id != null) c.id!: c.categoryName,
      };
      _isFollowing = followingResult;
      _isLoading = false;
    });
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMoreProducts || !_hasMoreProducts) return;
    setState(() => _isLoadingMoreProducts = true);
    try {
      final page = await _shopRepository.getShopProductsPage(
        widget.sellerId,
        afterProductId: _nextProductId,
      );
      if (!mounted) return;
      setState(() {
        final knownIds = _products.map((product) => product.id).toSet();
        final newProducts = page.items
            .where((product) => !knownIds.contains(product.id))
            .toList();
        _products = [..._products, ...newProducts];
        for (final product in newProducts) {
          if (product.id != null) {
            _salesByProductId[product.id!] = product.totalSold;
          }
        }
        _nextProductId = page.nextProductId;
        _hasMoreProducts = page.hasMore;
        _isLoadingMoreProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMoreProducts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load more products.')),
      );
    }
  }

  Future<void> _loadCartCount() async {
    final userId = SessionService.userId;
    if (userId == null) {
      cartCount = 0;
      return;
    }
    cartCount = await DatabaseHelper.instance.getCartItemCount(userId);
  }

  Future<void> _loadUnreadNotifications() async {
    final userId = SessionService.userId;
    if (userId == null) {
      unreadNotifications = 0;
      return;
    }
    unreadNotifications = await DatabaseHelper.instance
        .getUnreadNotificationCount(userId);
  }

  Future<void> _refreshCartBadge() async {
    await _loadCartCount();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshNotificationBadge() async {
    await _loadUnreadNotifications();
    if (!mounted) return;
    setState(() {});
  }

  // =========================================================
  // FOLLOW
  // =========================================================

  Future<void> _toggleFollow() async {
    final userId = _viewerId;

    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    if (_isOwnShop) return;

    final previousState = _isFollowing;
    final previousCount = _followerCount;
    final optimisticState = !previousState;
    final optimisticCount = previousCount + (optimisticState ? 1 : -1);

    setState(() {
      _isFollowing = optimisticState;
      _followerCount = optimisticCount < 0 ? 0 : optimisticCount;
      _isTogglingFollow = true;
    });

    try {
      final followResult = await VoucherRepository().toggleFollow(
        userId,
        widget.sellerId,
      );
      final savedState = followResult.following;
      if (!mounted) return;
      if (savedState) {
        final voucher = followResult.voucher;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You’re now following ${_shop?.shopName ?? 'this shop'}${voucher == null ? '' : '\nYou received ${voucher.label}, valid until ${DateFormat('MMMM d').format(voucher.expiresAt)}.'}',
            ),
          ),
        );
      }
      setState(() {
        _isFollowing = savedState;
        _followerCount = savedState == optimisticState
            ? _followerCount
            : previousCount +
                  (savedState == previousState ? 0 : (savedState ? 1 : -1));
        _isTogglingFollow = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFollowing = previousState;
        _followerCount = previousCount;
        _isTogglingFollow = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update follow. Try again.')),
      );
    }
  }

  // =========================================================
  // MESSAGE SELLER
  // =========================================================

  void _messageShop() {
    final userId = _viewerId;

    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    if (_isOwnShop) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("This is your own shop.")));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: widget.sellerId,
          otherUserName: _shopDisplayName,
          contextType: 'shop',
          contextId: widget.sellerId,
          contextName: _shopDisplayName,
          contextImage: _profileImagePath,
        ),
      ),
    );
  }

  String get _shopDisplayName {
    final shop = _shop;
    if (shop == null) return "Shop";
    if (shop.shopName != null && shop.shopName!.trim().isNotEmpty) {
      return shop.shopName!.trim();
    }
    return "${shop.firstName} ${shop.lastName}".trim();
  }

  String get _shopInitial =>
      _shopDisplayName.isNotEmpty ? _shopDisplayName[0].toUpperCase() : "S";

  /// Cover photo the seller has set for their shop. Falls back to the
  /// decorative gradient when they haven't uploaded one yet — never a
  /// product photo, since that's the seller's own listing artwork,
  /// not shop branding.
  String get _coverImagePath => _shop?.coverImage ?? '';

  /// Profile photo the seller has set. Falls back to the initials
  /// avatar when they haven't uploaded one.
  String get _profileImagePath => _shop?.profileImage ?? '';

  // =========================================================
  // PRODUCTS TAB: sorting + filtering
  // =========================================================

  List<ProductModel> get _sortedProducts {
    var list = List<ProductModel>.of(_products);

    if (_categoryFilter != null) {
      list = list
          .where((p) => _categoryNamesById[p.categoryId] == _categoryFilter)
          .toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((p) => p.productName.toLowerCase().contains(query))
          .toList();
    }

    switch (_sort) {
      case _ProductSort.recommended:
        list.sort((a, b) {
          final ratingCompare = b.rating.compareTo(a.rating);
          if (ratingCompare != 0) return ratingCompare;
          return (b.id ?? 0).compareTo(a.id ?? 0);
        });
        break;
      case _ProductSort.bestseller:
        list.sort((a, b) {
          final aSold = _salesByProductId[a.id] ?? 0;
          final bSold = _salesByProductId[b.id] ?? 0;
          return bSold.compareTo(aSold);
        });
        break;
      case _ProductSort.newRelease:
        list.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
        break;
      case _ProductSort.price:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
    }

    return list;
  }

  /// Distinct category names among this shop's products, with a
  /// product count each — powers the Categories tab.
  List<MapEntry<String, int>> get _shopCategories {
    final counts = <String, int>{};
    for (final p in _products) {
      final name = _categoryNamesById[p.categoryId];
      if (name == null) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  IconData _iconForCategory(String name) {
    for (final group in craftCategoryGroups) {
      for (final item in group.items) {
        if (item.name == name) return item.icon;
      }
    }
    return Icons.category_rounded;
  }

  // =========================================================
  // NAVIGATION HELPERS
  // =========================================================

  void _openProduct(ProductModel product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)),
    );
  }

  void _goToProductsTab({String? category}) {
    setState(() {
      _categoryFilter = category;
    });
    _tabController.animateTo(1);
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _shop == null
          ? const Center(child: Text("Shop not found."))
          : Column(
              children: [
                _buildShopProfile(),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildHomeTab(),
                      _buildProductsTab(),
                      _buildCategoriesTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // =========================================================
  // SHOP PROFILE HERO — responsive 16:9 cover + aligned profile
  // =========================================================

  // The cover is always calculated from the available width using 16:9.
  static const double _coverAspectRatio = 16 / 9;
  static const double _avatarDiameter = 84;

  Widget _buildShopProfile() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the shop hero responsive while preserving a 16:9 landscape ratio.
        final heroHeight = constraints.maxWidth / _coverAspectRatio;

        return SizedBox(
          width: double.infinity,
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Immersive 16:9 cover background.
              _buildCover(),

              // Shop identity and actions are layered directly over the cover.
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildAvatar(),
                    const SizedBox(width: 12),

                    // Shop name, rating, and statistics.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _shopDisplayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_shop!.hasCurrentSellerVerification) ...[
                                  const SizedBox(width: 5),
                                  Tooltip(
                                    message: _shop!.sellerTier == 1
                                        ? 'Verified Student Crafter'
                                        : 'Verified Seller · Trust ${_shop!.trustScore.toStringAsFixed(0)}/100',
                                    child: const Icon(
                                      Icons.verified_rounded,
                                      size: 19,
                                      color: Color(0xFF7DD3FC),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                RatingStars(rating: _averageRating, size: 14),
                                const SizedBox(width: 5),
                                Text(
                                  _reviewCount > 0
                                      ? _averageRating.toStringAsFixed(1)
                                      : 'No ratings',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$_totalSold sold  •  $_followerCount ${_followerCount == 1 ? 'follower' : 'followers'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!_isOwnShop &&
                        !_isFollowing &&
                        _campaign != null &&
                        campaignCanClaim(_campaign!, DateTime.now()))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Follow this shop and receive ${VoucherModel('', _campaign!).label}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (!_isOwnShop) ...[
                      const SizedBox(width: 10),
                      _buildHeroActions(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Follow and Message buttons stacked vertically on the right side
  /// of the immersive shop header.
  Widget _buildHeroActions() {
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 36,
            child: _isFollowing
                ? OutlinedButton.icon(
                    onPressed: _isTogglingFollow ? null : _toggleFollow,
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Following'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      backgroundColor: Colors.black.withValues(alpha: 0.22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _isTogglingFollow ? null : _toggleFollow,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Follow'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              onPressed: _messageShop,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              label: const Text('Message'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.22),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.80)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // COVER — responsive 16:9 image with top navigation
  // ---------------------------------------------------------

  Widget _buildCover() {
    final coverPath = _coverImagePath;

    return Stack(
      fit: StackFit.expand,
      children: [
        coverPath.isNotEmpty
            ? ProductImage(
                path: coverPath,
                fit: BoxFit.cover,
                placeholder: _buildCoverFallback(),
              )
            : _buildCoverFallback(),

        // Dark gradient overlay: subtle at the top and stronger at the
        // bottom so the layered shop information remains readable.
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x55000000),
                Colors.transparent,
                Color(0x33000000),
                Color(0xD9000000),
              ],
              stops: [0.0, 0.32, 0.55, 1.0],
            ),
          ),
        ),

        // Navigation controls are explicitly pinned to the top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(bottom: false, child: _buildHeroTopBar()),
        ),
      ],
    );
  }

  /// Decorative stand-in for shops that haven't uploaded a cover photo
  /// yet — a graphite-to-teal gradient with a faint watermark of the logo.
  Widget _buildCoverFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.dark, AppColors.darkGrey, AppColors.primary],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.18,
          child: Image.asset(
            'assets/logos/2.png',
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // TOP BAR — frosted glass icons floating over the cover photo
  // ---------------------------------------------------------

  Widget _buildHeroTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),

          // =============================================
          // SEARCH
          // =============================================
          Expanded(
            child: _isSearching
                ? Container(
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: "Search this shop...",
                              border: InputBorder.none,
                              isDense: true,
                              hintStyle: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                              if (_tabController.index != 1) {
                                _tabController.animateTo(1);
                              }
                            },
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSearching = false;
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(),
          ),

          if (!_isSearching)
            _GlassIconButton(
              icon: Icons.search,
              onTap: () => setState(() => _isSearching = true),
            ),

          const SizedBox(width: 8),

          // =============================================
          // NOTIFICATIONS
          // =============================================
          _GlassIconButton(
            icon: Icons.notifications_outlined,
            badgeCount: unreadNotifications,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              await _refreshNotificationBadge();
            },
          ),

          const SizedBox(width: 8),

          // =============================================
          // CART
          // =============================================
          _GlassIconButton(
            icon: Icons.shopping_bag_outlined,
            badgeCount: cartCount,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
              await _refreshCartBadge();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // AVATAR — overlaps the cover/white seam
  // ---------------------------------------------------------

  Widget _buildAvatar() {
    final profilePath = _profileImagePath;

    return Container(
      width: _avatarDiameter + 8,
      height: _avatarDiameter + 8,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: profilePath.isNotEmpty
            ? ProductImage(
                path: profilePath,
                fit: BoxFit.cover,
                placeholder: _buildAvatarInitial(),
              )
            : _buildAvatarInitial(),
      ),
    );
  }

  Widget _buildAvatarInitial() {
    return Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(
        _shopInitial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // WHITE INFO CARD — rate, sold, followers, follow + message
  // ---------------------------------------------------------

  // Kept as an alternate compact layout for smaller shop headers.
  // ignore: unused_element
  Widget _buildShopInfoCard({required double topPadding}) {
    return Padding(
      // Leaves space for the avatar/name row that overlaps the cover seam.
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RatingStars(rating: _averageRating, size: 15),
              const SizedBox(width: 6),
              Text(
                _reviewCount > 0
                    ? "${_averageRating.toStringAsFixed(1)} ($_reviewCount)"
                    : "No ratings yet",
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(
                label: "$_totalSold sold",
                icon: Icons.local_shipping_outlined,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label:
                    "$_followerCount ${_followerCount == 1 ? 'follower' : 'followers'}",
                icon: Icons.people_alt_outlined,
              ),
            ],
          ),

          if (!_isOwnShop &&
              !_isFollowing &&
              _campaign != null &&
              campaignCanClaim(_campaign!, DateTime.now()))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Follow this shop and receive ${VoucherModel('', _campaign!).label}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!_isOwnShop) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: _isFollowing
                        ? OutlinedButton.icon(
                            onPressed: _isTogglingFollow ? null : _toggleFollow,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text("Following"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _isTogglingFollow ? null : _toggleFollow,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text("Follow"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 46,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _messageShop,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // TAB BAR: Home / Products / Categories
  // =========================================================

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: "Home"),
          Tab(text: "Products"),
          Tab(text: "Categories"),
        ],
      ),
    );
  }

  // =========================================================
  // HOME TAB
  // =========================================================

  Widget _buildHomeTab() {
    if (_productCount == 0) {
      return _buildEmpty("This shop has no products yet.");
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_flashSaleProducts.isNotEmpty) ...[
              Row(
                children: const [
                  Icon(
                    Icons.bolt_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Flash Sale",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildHorizontalProductList(_flashSaleProducts),
              const SizedBox(height: 22),
            ],
            const Text(
              "Top Products",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _buildHorizontalProductList(
              _topProducts.isEmpty ? _products.take(10).toList() : _topProducts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalProductList(List<ProductModel> products) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final product = products[index];
          return SizedBox(
            width: 140,
            child: ProductCard(
              name: product.productName,
              price: "₱${product.price.toStringAsFixed(0)}",
              image: product.image,
              rating: product.rating,
              onTap: () => _openProduct(product),
            ),
          );
        },
      ),
    );
  }

  // =========================================================
  // PRODUCTS TAB
  // =========================================================

  Widget _buildProductsTab() {
    final products = _sortedProducts;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _SortChip(
                  label: "Recommended",
                  selected: _sort == _ProductSort.recommended,
                  onTap: () => setState(() => _sort = _ProductSort.recommended),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  label: "Bestseller",
                  selected: _sort == _ProductSort.bestseller,
                  onTap: () => setState(() => _sort = _ProductSort.bestseller),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  label: "New Release",
                  selected: _sort == _ProductSort.newRelease,
                  onTap: () => setState(() => _sort = _ProductSort.newRelease),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  label: "Price",
                  selected: _sort == _ProductSort.price,
                  onTap: () => setState(() => _sort = _ProductSort.price),
                ),
              ],
            ),
          ),
        ),

        if (_categoryFilter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(_categoryFilter!),
                onDeleted: () => setState(() => _categoryFilter = null),
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                labelStyle: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_products.length} shown of $_productCount products',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: products.isEmpty
              ? _buildEmpty("No products found.")
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadAll,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.70,
                        ),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ProductCard(
                        name: product.productName,
                        price: "₱${product.price.toStringAsFixed(0)}",
                        image: product.image,
                        rating: product.rating,
                        onTap: () => _openProduct(product),
                      );
                    },
                  ),
                ),
        ),
        if (_hasMoreProducts)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoadingMoreProducts ? null : _loadMoreProducts,
                icon: _isLoadingMoreProducts
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _isLoadingMoreProducts ? 'Loading...' : 'Load more products',
                ),
              ),
            ),
          ),
      ],
    );
  }

  // =========================================================
  // CATEGORIES TAB
  // =========================================================

  Widget _buildCategoriesTab() {
    final categories = _shopCategories;

    if (categories.isEmpty) {
      return _buildEmpty("No categories yet.");
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final entry = categories[index];

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _goToProductsTab(category: entry.key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.secondary,
                  child: Icon(
                    _iconForCategory(entry.key),
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.key,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${entry.value} items",
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// =========================================================
// SMALL HELPER WIDGETS
// =========================================================

/// Frosted, semi-transparent icon button used to float controls directly
/// on top of the immersive cover photo (back, search, notifications, cart).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Plain translucent circle — no BackdropFilter/blur here.
          // Blur-based frosted glass crashes on many Android emulators
          // (software/SwiftShader rendering can't handle it), so this
          // keeps the same "glass over photo" look without the risk.
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.38),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _StatChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
