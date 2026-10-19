import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/cart_item_model.dart';
import '../../models/flash_sale_model.dart';
import '../../models/product_model.dart';
import '../../models/product_option_model.dart';
import '../../models/user_model.dart';
import '../../database/database_helper.dart';
import '../../repositories/flash_sale_repository.dart';
import '../../repositories/shop_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/moderation_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';
import '../../widgets/rating_stars.dart';
import 'cart_screen.dart';
import '../../widgets/quantity_input.dart';
import 'chat_screen.dart';
import 'checkout_screen.dart';
import 'notifications_screen.dart';
import 'shop_screen.dart';
import 'how_its_made_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final ProductModel product;

  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final ShopRepository _shopRepository = ShopRepository();
  final ModerationRepository _moderationRepository = ModerationRepository();

  int quantity = 1;
  int cartCount = 0;
  int unreadNotifications = 0;

  // Re-checked on open: the product may come from a list that did not
  // attach its flash sale, or the sale may have started since.
  FlashSaleModel? _flashSale;
  bool _flashSaleChecked = false;

  ProductModel get _product => _flashSaleChecked
      ? widget.product.withFlashSale(_flashSale)
      : widget.product;

  UserModel? _shop;
  double _shopRating = 0;
  int _shopReviewCount = 0;
  int _shopTotalSold = 0;
  bool _isLoadingShop = true;
  bool _isFollowingShop = false;
  bool _isTogglingShopFollow = false;
  bool _isReporting = false;

  bool _isFavorite = false;
  ProductOptionModel? _selectedOption;

  Future<void> _reportNotHandmade() async {
    final userId = SessionService.userId;
    final productId = widget.product.id;
    if (userId == null || productId == null || _isReporting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report as not handmade?'),
        content: const Text(
          'Send this listing to moderation if it appears mass-produced or dropshipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send report'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isReporting = true);
    try {
      await _moderationRepository.reportListingAsNotHandmade(
        productId: productId,
        reporterId: userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report sent to moderation. Thank you.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This listing was already reported or could not be reported.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.product.defaultOption;
    _loadCartCount();
    _loadUnreadNotifications();
    _loadShopInfo();
    _loadFavoriteStatus();
    _loadFlashSale();
  }

  // =========================================================
  // FAVORITES
  // =========================================================

  Future<void> _loadFavoriteStatus() async {
    final userId = SessionService.userId;
    final productId = widget.product.id;
    if (userId == null || productId == null) return;

    final isFav = await DatabaseHelper.instance.isFavorite(userId, productId);

    if (!mounted) return;
    setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    final userId = SessionService.userId;
    final productId = widget.product.id;
    if (userId == null || productId == null) return;

    // Optimistic UI update.
    setState(() => _isFavorite = !_isFavorite);

    final result = await DatabaseHelper.instance.toggleFavorite(
      userId,
      productId,
    );

    if (!mounted) return;
    setState(() => _isFavorite = result);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result ? "Added to favorites" : "Removed from favorites"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // =========================================================
  // LOAD SHOP INFO (for the shop summary row)
  // =========================================================

  Future<void> _loadShopInfo() async {
    final sellerId = widget.product.sellerId;
    final viewerId = SessionService.userId;

    final results = await Future.wait([
      _shopRepository.getShop(sellerId),
      _shopRepository.getProductMetrics(sellerId),
      if (viewerId != null && viewerId != sellerId)
        _shopRepository.isFollowing(viewerId, sellerId)
      else
        Future<bool>.value(false),
    ]);

    if (!mounted) return;

    final metrics = results[1] as SellerProductMetrics;

    setState(() {
      _shop = results[0] as UserModel?;
      _shopRating = metrics.averageRating;
      _shopReviewCount = metrics.reviewCount;
      _shopTotalSold = metrics.unitsSold;
      _isFollowingShop = results[2] as bool;
      _isLoadingShop = false;
    });
  }

  Future<void> _toggleShopFollow() async {
    final viewerId = SessionService.userId;
    final sellerId = widget.product.sellerId;

    if (viewerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    if (viewerId == sellerId || _isTogglingShopFollow) return;

    final previousState = _isFollowingShop;
    setState(() {
      _isFollowingShop = !previousState;
      _isTogglingShopFollow = true;
    });

    try {
      final savedState = await _shopRepository.toggleFollow(viewerId, sellerId);
      if (!mounted) return;
      setState(() {
        _isFollowingShop = savedState;
        _isTogglingShopFollow = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFollowingShop = previousState;
        _isTogglingShopFollow = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update follow. Try again.')),
      );
    }
  }

  void _visitShop() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopScreen(sellerId: widget.product.sellerId),
      ),
    );
  }

  // =========================================================
  // LOAD CART COUNT
  // =========================================================

  Future<void> _loadCartCount() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;
      setState(() => cartCount = 0);
      return;
    }

    final count = await DatabaseHelper.instance.getCartItemCount(userId);

    if (!mounted) return;

    setState(() {
      cartCount = count;
    });
  }

  Future<void> _loadUnreadNotifications() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;
      setState(() => unreadNotifications = 0);
      return;
    }

    final count = await DatabaseHelper.instance.getUnreadNotificationCount(
      userId,
    );

    if (!mounted) return;

    setState(() {
      unreadNotifications = count;
    });
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    ).then((_) => _loadUnreadNotifications());
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartScreen()),
    ).then((_) => _loadCartCount());
  }

  void _openFullScreenImage(BuildContext context, String imagePath) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => _FullScreenImageViewer(
          heroTag: 'product-image-${widget.product.id}',
          imagePath: imagePath,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _messageSeller(
    BuildContext context,
    ProductModel product,
  ) async {
    final userId = SessionService.userId;

    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    if (userId == product.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This is your own product.")),
      );
      return;
    }

    final seller = await _shopRepository.getShop(product.sellerId);
    final sellerName = seller == null
        ? "Seller"
        : "${seller.firstName} ${seller.lastName}";

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: product.sellerId,
          otherUserName: sellerName,
          contextType: 'product',
          contextId: product.id,
          contextName: product.productName,
          contextImage: product.image,
          contextPrice: product.price,
        ),
      ),
    );
  }

  Future<void> _loadFlashSale() async {
    final productId = widget.product.id;
    if (productId == null) return;
    try {
      final live = await FlashSaleRepository().liveByProductIds([productId]);
      if (!mounted) return;
      setState(() {
        _flashSale = live[productId];
        _flashSaleChecked = true;
      });
    } catch (_) {
      // Keep whatever the listing attached.
    }
  }

  Future<void> _addSelectedProductToCart(double unitPrice) async {
    final product = widget.product;
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await DatabaseHelper.instance.addToCart(
      userId,
      product.id!,
      quantity,
      optionId: _selectedOption?.id,
      optionName: _selectedOption?.name,
      optionImage: _selectedOption?.image,
      unitPrice: unitPrice,
    );
    if (!mounted) return;
    await _loadCartCount();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('${product.productName} added to cart!')),
    );
  }

  void _buySelectedProduct(double unitPrice) {
    final product = widget.product;
    final userId = SessionService.userId;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          selectedItems: [
            CartItemModel(
              userId: userId,
              productId: product.id!,
              quantity: quantity,
              optionId: _selectedOption?.id,
              optionName: _selectedOption?.name,
              optionImage: _selectedOption?.image,
              unitPrice: unitPrice,
            ),
          ],
        ),
      ),
    ).then((_) => _loadCartCount());
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final baseUnitPrice = _selectedOption?.price ?? product.price;
    final unitPrice = product.discountedPriceFor(baseUnitPrice);
    final availableStock = _selectedOption?.stock ?? product.stock;
    final displayImage = _selectedOption?.image ?? product.image;
    final isOwnProduct =
        SessionService.userId != null &&
        SessionService.userId == product.sellerId;
    final bool isAvailable = availableStock > 0 && !isOwnProduct;

    return Scaffold(
      backgroundColor: AppColors.background,

      bottomNavigationBar: _PurchasePanel(
        quantity: quantity,
        total: unitPrice * quantity,
        isAvailable: isAvailable,
        isOwnProduct: isOwnProduct,
        maxQuantity: availableStock > 99 ? 99 : availableStock,
        canDecrease: quantity > 1,
        canIncrease: isAvailable && quantity < availableStock,
        onDecrease: () => setState(() => quantity--),
        onIncrease: () => setState(() => quantity++),
        onQuantityChanged: (value) => setState(() => quantity = value),
        onMessage: () => _messageSeller(context, product),
        onAddToCart: () => _addSelectedProductToCart(unitPrice),
        onBuyNow: () => _buySelectedProduct(unitPrice),
      ),

      // ==========================================
      // BODY
      // ==========================================
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ======================================
            // PRODUCT IMAGE + FLOATING HEADER
            // ======================================

            SizedBox(
              width: double.infinity,
              height: 320,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => _openFullScreenImage(context, displayImage),
                    child: Hero(
                      tag: 'product-image-${product.id}',
                      child: Container(
                        color: Colors.white,
                        child: ProductImage(
                          path: displayImage,
                          fit: BoxFit.cover,
                          placeholder: const Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 90,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Dark gradient so the floating icons stay readable
                  // over light product photos.
                  // IgnorePointer so it doesn't swallow taps meant for the image.
                  IgnorePointer(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Colors.transparent],
                          stops: [0.0, 0.3],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Row(
                          children: [
                            _GlassIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.pop(context),
                            ),

                            const Spacer(),

                            _GlassIconButton(
                              icon: _isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              iconColor: _isFavorite
                                  ? AppColors.error
                                  : Colors.white,
                              onTap: _toggleFavorite,
                            ),

                            const SizedBox(width: 8),

                            _GlassIconButton(
                              icon: Icons.notifications_outlined,
                              badgeCount: unreadNotifications,
                              onTap: _openNotifications,
                            ),

                            const SizedBox(width: 8),

                            _GlassIconButton(
                              icon: Icons.shopping_bag_outlined,
                              badgeCount: cartCount,
                              onTap: _openCart,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ======================================
            // PRODUCT INFORMATION
            // ======================================
            Padding(
              padding: const EdgeInsets.all(20),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  // ==================================
                  // PRODUCT NAME
                  // ==================================

                  Text(
                    product.productName,

                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (product.liveFlashSale != null) ...[
                    _FlashSaleBanner(
                      sale: product.liveFlashSale!,
                      regularPrice: product.regularPriceFor(baseUnitPrice),
                      onEnded: () {
                        if (mounted) setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ==================================
                  // PRICE
                  // ==================================
                  Text(
                    '₱${unitPrice.toStringAsFixed(2)}',

                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ==================================
                  // RATING + STOCK
                  // ==================================
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 22),

                      const SizedBox(width: 5),

                      Text(
                        product.rating.toStringAsFixed(1),

                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),

                      const SizedBox(width: 15),

                      Icon(
                        isAvailable
                            ? Icons.inventory_2_outlined
                            : Icons.remove_shopping_cart,
                        size: 20,
                        color: isAvailable ? Colors.green : Colors.red,
                      ),

                      const SizedBox(width: 5),

                      Text(
                        isAvailable
                            ? '$availableStock available'
                            : 'Out of stock',

                        style: TextStyle(
                          color: isAvailable ? Colors.green : Colors.red,

                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  if (product.hasImageOptions) ...[
                    const Text(
                      'Choose an option',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: product.options.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final option = product.options[index];
                          final selected = option.id == _selectedOption?.id;
                          return InkWell(
                            onTap: () => setState(() {
                              _selectedOption = option;
                              quantity = 1;
                            }),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 92,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.lightGrey,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: ProductImage(
                                        path: option.image,
                                        fit: BoxFit.cover,
                                        placeholder: const Icon(
                                          Icons.image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    option.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '₱${option.price.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // ==================================
                  // DESCRIPTION
                  // ==================================
                  const Text(
                    'Description',

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    product.description.isEmpty
                        ? 'No description available.'
                        : product.description,

                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),

                  if (SessionService.userId != product.sellerId)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isReporting ? null : _reportNotHandmade,
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: Text(
                          _isReporting
                              ? 'Sending report…'
                              : 'Report: Not handmade',
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HowItsMadeScreen(product: product),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        product.makingProcess?.hasSellerProcess == true
                            ? "See How It's Made"
                            : "Ask AI How It's Made",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // ==================================
                  // VIEW SHOP
                  // ==================================
                  if (!_isLoadingShop && _shop != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _visitShop,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.lightGrey),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ClipOval(
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child:
                                        (_shop!.profileImage ?? '').isNotEmpty
                                        ? ProductImage(
                                            path: _shop!.profileImage!,
                                            fit: BoxFit.cover,
                                            placeholder: _ShopAvatarFallback(
                                              shop: _shop!,
                                            ),
                                          )
                                        : _ShopAvatarFallback(shop: _shop!),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (_shop!.shopName?.trim().isNotEmpty ==
                                                true)
                                            ? _shop!.shopName!.trim()
                                            : "${_shop!.firstName} ${_shop!.lastName}",
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          RatingStars(
                                            rating: _shopRating,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              _shopReviewCount > 0
                                                  ? '${_shopRating.toStringAsFixed(1)} · $_shopTotalSold sold'
                                                  : 'No ratings · $_shopTotalSold sold',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  children: [
                                    if (SessionService.userId !=
                                        widget.product.sellerId) ...[
                                      SizedBox(
                                        width: 104,
                                        height: 36,
                                        child: _isFollowingShop
                                            ? OutlinedButton(
                                                onPressed: _isTogglingShopFollow
                                                    ? null
                                                    : _toggleShopFollow,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.primary,
                                                  padding: EdgeInsets.zero,
                                                  side: const BorderSide(
                                                    color: AppColors.primary,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text('Following'),
                                              )
                                            : ElevatedButton(
                                                onPressed: _isTogglingShopFollow
                                                    ? null
                                                    : _toggleShopFollow,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text('Follow'),
                                              ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    SizedBox(
                                      width: 104,
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: _visitShop,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                          padding: EdgeInsets.zero,
                                          side: const BorderSide(
                                            color: AppColors.primary,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Visit Shop',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchasePanel extends StatelessWidget {
  final int quantity;
  final double total;
  final bool isAvailable;
  final bool isOwnProduct;
  final int maxQuantity;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onMessage;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;

  const _PurchasePanel({
    required this.quantity,
    required this.total,
    required this.isAvailable,
    required this.isOwnProduct,
    required this.maxQuantity,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
    required this.onQuantityChanged,
    required this.onMessage,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Quantity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canDecrease ? onDecrease : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Decrease quantity',
                  ),
                  QuantityInput(
                    value: quantity,
                    max: maxQuantity,
                    onChanged: onQuantityChanged,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canIncrease ? onIncrease : null,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Increase quantity',
                  ),
                ],
              ),
              if (isOwnProduct)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'This is your own product, so you can’t order it.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: onMessage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isAvailable ? onAddToCart : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Add to Cart',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isAvailable ? onBuyNow : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Buy Now',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopAvatarFallback extends StatelessWidget {
  final UserModel shop;

  const _ShopAvatarFallback({required this.shop});

  @override
  Widget build(BuildContext context) {
    final shopName = shop.shopName?.trim() ?? '';
    final ownerName = '${shop.firstName} ${shop.lastName}'.trim();
    final displayName = shopName.isNotEmpty ? shopName : ownerName;

    return Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

// =========================================================
// FLOATING GLASS ICON BUTTON (over the product photo)
// =========================================================
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final int badgeCount;
  final Color iconColor;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    this.badgeCount = 0,
    this.iconColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.38),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: iconColor, size: 18),
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

// =========================================================
// FULL SCREEN IMAGE VIEWER (pinch to zoom, tap the image or X to close)
// =========================================================
class _FullScreenImageViewer extends StatelessWidget {
  final String heroTag;
  final String imagePath;

  const _FullScreenImageViewer({
    required this.heroTag,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: ProductImage(
                      path: imagePath,
                      fit: BoxFit.contain,
                      maxDecodeWidth: 2400, // stays sharp when zoomed in
                      placeholder: const Icon(
                        Icons.image_outlined,
                        size: 90,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlashSaleBanner extends StatefulWidget {
  final FlashSaleModel sale;
  final double regularPrice;
  final VoidCallback onEnded;

  const _FlashSaleBanner({
    required this.sale,
    required this.regularPrice,
    required this.onEnded,
  });

  @override
  State<_FlashSaleBanner> createState() => _FlashSaleBannerState();
}

class _FlashSaleBannerState extends State<_FlashSaleBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!DateTime.now().isBefore(widget.sale.endsAt)) {
        _timer?.cancel();
        widget.onEnded();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdown() {
    var left = widget.sale.endsAt.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int value) => value.toString().padLeft(2, '0');
    final hours = left.inHours;
    return '${two(hours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 4),
                const Text(
                  'Flash Sale',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  'Ends in ${_countdown()}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '-${sale.discountPercent}% · regular '),
                  TextSpan(
                    text: '₱${widget.regularPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${sale.remaining} left at this price · '
              'limit ${sale.perCustomerLimit} per customer',
            ),
          ],
        ),
      ),
    );
  }
}
