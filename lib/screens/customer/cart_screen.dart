import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/cart_item_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/product_image.dart';
import '../../widgets/quantity_input.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final ProductRepository _productRepository = ProductRepository();
  List<CartItemModel> cartItems = [];
  List<ProductModel> products = [];
  Map<int, UserModel> sellersById = {};

  // Cart item ids currently checked for purchase. Newly-seen items
  // default to selected (standard cart UX); items removed from the
  // cart are dropped from here automatically on the next load.
  Set<int> selectedItemIds = {};
  Set<int> _knownIds = {};

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadCart();
  }

  // ==========================
  // LOAD CART
  // ==========================

  Future<void> loadCart() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      return;
    }

    try {
      final items = await DatabaseHelper.instance.getCartItems(userId);

      // Fetch the shop/seller for each distinct product so items
      // can be grouped by shop in the UI.
      final relevantProductIds = items.map((e) => e.productId).toSet();

      final productList = await _productRepository.getProductsByIds(
        relevantProductIds.toList(),
      );

      final sellerIds = productList
          .where((p) => p.id != null && relevantProductIds.contains(p.id))
          .map((p) => p.sellerId)
          .toSet();

      final sellerMap = <int, UserModel>{};
      for (final sellerId in sellerIds) {
        final seller = await DatabaseHelper.instance.getUserById(sellerId);
        if (seller != null) {
          sellerMap[sellerId] = seller;
        }
      }

      if (!mounted) return;

      setState(() {
        cartItems = items;
        products = productList;
        sellersById = sellerMap;
        isLoading = false;

        // Keep existing selections for items already known, default
        // newly-seen items to selected, drop ids no longer present.
        final currentIds = items.map((e) => e.id).whereType<int>().toSet();
        final newSelected = <int>{};
        for (final id in currentIds) {
          if (_knownIds.contains(id)) {
            if (selectedItemIds.contains(id)) newSelected.add(id);
          } else {
            newSelected.add(id);
          }
        }
        selectedItemIds = newSelected;
        _knownIds = currentIds;
      });
    } catch (e) {
      debugPrint("Cart Error: $e");

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  // ==========================
  // FIND PRODUCT
  // ==========================

  ProductModel? getProduct(int productId) {
    try {
      return products.firstWhere((product) => product.id == productId);
    } catch (_) {
      return null;
    }
  }

  double itemPrice(CartItemModel item, ProductModel product) {
    final basePrice = product.optionById(item.optionId)?.price ?? product.price;
    return product.discountedPriceFor(basePrice);
  }

  int itemStock(CartItemModel item, ProductModel product) {
    return product.optionById(item.optionId)?.stock ?? product.stock;
  }

  // ==========================
  // SHOP NAME
  // ==========================

  String shopNameFor(int sellerId) {
    final seller = sellersById[sellerId];

    if (seller == null) return "Shop";

    if (seller.shopName != null && seller.shopName!.trim().isNotEmpty) {
      return seller.shopName!;
    }

    return "${seller.firstName} ${seller.lastName}";
  }

  // ==========================
  // GROUP CART ITEMS BY SHOP
  // ==========================

  List<MapEntry<int, List<CartItemModel>>> get itemsGroupedByShop {
    final Map<int, List<CartItemModel>> groups = {};

    for (final item in cartItems) {
      final product = getProduct(item.productId);
      if (product == null) continue;

      groups.putIfAbsent(product.sellerId, () => []).add(item);
    }

    final entries = groups.entries.toList();
    entries.sort(
      (a, b) => shopNameFor(
        a.key,
      ).toLowerCase().compareTo(shopNameFor(b.key).toLowerCase()),
    );

    return entries;
  }

  // ==========================
  // UPDATE QUANTITY
  // ==========================

  Future<void> updateQuantity(CartItemModel item, int quantity) async {
    if (item.id == null) return;

    if (quantity <= 0) {
      await DatabaseHelper.instance.removeFromCart(item.id!);
    } else {
      await DatabaseHelper.instance.updateCartQuantity(item.id!, quantity);
    }

    await loadCart();
  }

  // ==========================
  // REMOVE ITEM
  // ==========================

  Future<void> removeItem(CartItemModel item) async {
    if (item.id == null) return;

    await DatabaseHelper.instance.removeFromCart(item.id!);

    await loadCart();
  }

  // ==========================
  // SELECTION
  // ==========================

  void toggleSelected(int cartItemId) {
    setState(() {
      if (selectedItemIds.contains(cartItemId)) {
        selectedItemIds.remove(cartItemId);
      } else {
        selectedItemIds.add(cartItemId);
      }
    });
  }

  bool get allSelected =>
      cartItems.isNotEmpty && selectedItemIds.length == cartItems.length;

  void toggleSelectAll() {
    setState(() {
      if (allSelected) {
        selectedItemIds.clear();
      } else {
        selectedItemIds = cartItems.map((e) => e.id).whereType<int>().toSet();
      }
    });
  }

  List<CartItemModel> get selectedCartItems =>
      cartItems.where((item) => selectedItemIds.contains(item.id)).toList();

  // ==========================
  // TOTAL (selected items only)
  // ==========================

  double get total {
    double result = 0;

    for (final item in selectedCartItems) {
      final product = getProduct(item.productId);

      if (product != null) {
        result += itemPrice(item, product) * item.quantity;
      }
    }

    return result;
  }

  // ==========================
  // SHOP HEADER
  // ==========================

  Widget _buildShopHeader(int sellerId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            shopNameFor(sellerId),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  // CART ITEM CARD
  // ==========================

  Widget _buildCartItemCard(CartItemModel item) {
    final product = getProduct(item.productId);

    if (product == null) {
      return const SizedBox.shrink();
    }

    final isSelected = item.id != null && selectedItemIds.contains(item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // ==========================
            // SELECT CHECKBOX
            // ==========================

            Checkbox(
              value: isSelected,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: item.id == null
                  ? null
                  : (_) => toggleSelected(item.id!),
            ),

            // ==========================
            // PRODUCT IMAGE
            // ==========================
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: (item.optionImage ?? product.image).isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ProductImage(
                        path: item.optionImage ?? product.image,
                        fit: BoxFit.cover,
                        placeholder: const Icon(
                          Icons.image_outlined,
                          size: 35,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.image_outlined,
                      size: 35,
                      color: Colors.grey,
                    ),
            ),

            const SizedBox(width: 12),

            // ==========================
            // PRODUCT INFORMATION
            // ==========================
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  if ((item.optionName ?? '').isNotEmpty) ...[
                    Text(
                      item.optionName!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  Text(
                    "₱${itemPrice(item, product).toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ==========================
                  // QUANTITY
                  // ==========================
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          updateQuantity(item, item.quantity - 1);
                        },
                        icon: const Icon(Icons.remove),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),

                      QuantityInput(
                        value: item.quantity,
                        max: itemStock(item, product) > 99
                            ? 99
                            : itemStock(item, product),
                        width: 46,
                        fontSize: 15,
                        onChanged: (value) => updateQuantity(item, value),
                      ),

                      IconButton(
                        onPressed: item.quantity < itemStock(item, product)
                            ? () {
                                updateQuantity(item, item.quantity + 1);
                              }
                            : null,
                        icon: const Icon(Icons.add),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ==========================
            // DELETE
            // ==========================
            IconButton(
              onPressed: () {
                removeItem(item);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================
  // BUILD
  // ==========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          "My Cart",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : cartItems.isEmpty
          ? const Center(
              child: Text(
                "Your cart is empty.",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            )
          : Column(
              children: [
                // ==========================
                // SELECT ALL
                // ==========================

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: allSelected,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (_) => toggleSelectAll(),
                      ),
                      const Text(
                        "Select All",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${selectedItemIds.length} of ${cartItems.length} selected",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // ==========================
                // CART ITEMS
                // ==========================
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final group in itemsGroupedByShop) ...[
                        _buildShopHeader(group.key),
                        const SizedBox(height: 8),
                        for (final item in group.value)
                          _buildCartItemCard(item),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),

                // ==========================
                // TOTAL + CHECKOUT
                // ==========================
                Container(
                  padding: const EdgeInsets.all(20),

                  decoration: const BoxDecoration(
                    color: Colors.white,

                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),

                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,

                        children: [
                          const Text(
                            "Total",

                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          Text(
                            "₱${total.toStringAsFixed(2)}",

                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 15),

                      SizedBox(
                        width: double.infinity,
                        height: 52,

                        child: ElevatedButton(
                          onPressed: selectedCartItems.isEmpty
                              ? null
                              : () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CheckoutScreen(
                                        selectedItems: selectedCartItems,
                                      ),
                                    ),
                                  );
                                  loadCart();
                                },

                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          child: Text(
                            selectedCartItems.isEmpty
                                ? "CHECKOUT"
                                : "CHECKOUT (${selectedCartItems.length})",

                            style: const TextStyle(
                              fontSize: 16,
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

      // Cart is no longer in the bottom navigation.
      bottomNavigationBar: const BottomNavbar(currentIndex: 0),
    );
  }
}
