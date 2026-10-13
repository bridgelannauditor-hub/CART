import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../models/seller_order_item_model.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/product_repository.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import 'edit_product_screen.dart';
import 'seller_shop_management_screen.dart';
import '../customer/notifications_screen.dart';
import '../customer/settings_screen.dart';
import '../../widgets/product_image.dart';
import '../../widgets/seller_bottom_navbar.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final ProductRepository _productRepository = ProductRepository();
  final OrderRepository _orderRepository = OrderRepository();
  final NotificationRepository _notificationRepository =
      NotificationRepository();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _productsSectionKey = GlobalKey();

  late Future<_DashboardData> _productsFuture;
  _DashboardData? _currentData;
  bool _isLoadingMoreProducts = false;
  int _unreadNotifications = 0;
  String _query = '';
  int _stockFilter = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadUnreadNotifications();
  }

  void _loadProducts() {
    final sellerId = SessionService.userId;
    _productsFuture = sellerId == null
        ? Future.value(const _DashboardData())
        : _loadProductsAndSales(sellerId).then((data) {
            _currentData = data;
            return data;
          });
  }

  Future<_DashboardData> _loadProductsAndSales(int sellerId) async {
    final pageFuture = _productRepository.getSellerProductsPage(sellerId);
    final metricsFuture = _productRepository.getSellerProductMetrics(sellerId);
    final revenueFuture = _orderRepository.getSellerRevenueSummary(sellerId);
    final page = await pageFuture;
    final metrics = await metricsFuture;
    SellerRevenueSummary revenue;
    try {
      revenue = await revenueFuture;
    } catch (_) {
      revenue = const SellerRevenueSummary(
        currentMonth: 0,
        previousMonthToDate: 0,
      );
    }

    return _DashboardData(
      products: page.items,
      revenue: revenue,
      productCount: metrics.productCount,
      unitsSold: metrics.unitsSold,
      lowStockCount: metrics.lowStockCount,
      bestSeller: metrics.bestSeller,
      nextProductId: page.nextProductId,
      hasMoreProducts: page.hasMore,
    );
  }

  Future<void> _loadMoreProducts() async {
    final sellerId = SessionService.userId;
    final current = _currentData;
    if (sellerId == null ||
        current == null ||
        !current.hasMoreProducts ||
        _isLoadingMoreProducts) {
      return;
    }
    setState(() => _isLoadingMoreProducts = true);
    try {
      final page = await _productRepository.getSellerProductsPage(
        sellerId,
        afterProductId: current.nextProductId,
      );
      if (!mounted) return;
      final existingIds = current.products.map((product) => product.id).toSet();
      final updated = current.copyWith(
        products: [
          ...current.products,
          ...page.items.where((product) => !existingIds.contains(product.id)),
        ],
        nextProductId: page.nextProductId,
        hasMoreProducts: page.hasMore,
      );
      setState(() {
        _currentData = updated;
        _productsFuture = Future.value(updated);
        _isLoadingMoreProducts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMoreProducts = false);
    }
  }

  Future<void> _loadUnreadNotifications() async {
    final sellerId = SessionService.userId;
    if (sellerId == null) return;

    final count = await _notificationRepository.getUnreadCount(sellerId);
    if (!mounted) return;
    setState(() => _unreadNotifications = count);
  }

  Future<void> _refresh() async {
    setState(_loadProducts);
    await Future.wait([_productsFuture, _loadUnreadNotifications()]);
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete product?"),
        content: Text(
          "\"${product.productName}\" will be removed permanently.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (product.id == null) return;

    await _productRepository.deleteProduct(product.id!);
    if (!mounted) return;

    setState(_loadProducts);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text("\"${product.productName}\" deleted."),
      ),
    );
  }

  Future<void> _goToAddProduct() async {
    final added = await Navigator.pushNamed(context, AppRoutes.addProduct);
    if (added == true && mounted) {
      setState(_loadProducts);
    }
  }

  Future<void> _goToEditProduct(ProductModel product) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProductScreen(product: product)),
    );
    if (updated == true && mounted) {
      setState(_loadProducts);
    }
  }

  void _showProducts({bool lowStockOnly = false}) {
    setState(() {
      _query = '';
      _stockFilter = lowStockOnly ? 1 : 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = _productsSectionKey.currentContext;
      if (sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: .05,
      );
    });
  }

  void _showSalesAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SellerShopManagementScreen()),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F5),
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: "Notifications",
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  _loadUnreadNotifications();
                },
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _unreadNotifications > 99
                          ? '99+'
                          : '$_unreadNotifications',
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
          IconButton(
            tooltip: "Settings",
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const SellerBottomNavbar(currentIndex: 0),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToAddProduct,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: FutureBuilder<_DashboardData>(
          future: _productsFuture,
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final data = snapshot.data ?? const _DashboardData();
            final products = snapshot.data?.products ?? const <ProductModel>[];
            final lowStockCount = data.lowStockCount;
            final visibleProducts = products.where((product) {
              final matchesQuery = product.productName.toLowerCase().contains(
                _query.toLowerCase(),
              );
              final matchesStock =
                  _stockFilter == 0 ||
                  (_stockFilter == 1 &&
                      product.stock > 0 &&
                      product.stock <= 5) ||
                  (_stockFilter == 2 && product.stock <= 0);
              return matchesQuery && matchesStock;
            }).toList();

            final bestSeller = data.bestSeller;
            final bestSellerCount = bestSeller?.totalSold ?? 0;

            return ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Material(
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: AppColors.lightGrey.withValues(alpha: .7),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HeroMetric(
                            label: 'Products',
                            value: isLoading || snapshot.hasError
                                ? '—'
                                : '${data.productCount}',
                            onTap: _showProducts,
                          ),
                        ),
                        const _HeroDivider(),
                        Expanded(
                          child: _HeroMetric(
                            label: 'Units sold',
                            value: isLoading || snapshot.hasError
                                ? '—'
                                : '${data.unitsSold}',
                            onTap: _showSalesAnalytics,
                          ),
                        ),
                        const _HeroDivider(),
                        Expanded(
                          child: _HeroMetric(
                            label: 'Low stock',
                            value: isLoading || snapshot.hasError
                                ? '—'
                                : '$lowStockCount',
                            alert: lowStockCount > 0,
                            onTap: () => _showProducts(lowStockOnly: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _RevenueSummaryCard(
                    summary: data.revenue,
                    onView: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SellerShopManagementScreen(),
                      ),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: _SectionHeading(
                    title: 'Performance highlight',
                    subtitle: 'Your strongest product at a glance',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: snapshot.hasError
                      ? const SizedBox.shrink()
                      : isLoading
                      ? const _BestSellerCard.loading()
                      : bestSeller == null
                      ? const _BestSellerCard.empty()
                      : _BestSellerCard(
                          product: bestSeller,
                          unitsSold: bestSellerCount,
                        ),
                ),

                Padding(
                  key: _productsSectionKey,
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeading(
                        title: 'Products',
                        subtitle: 'Manage your shop collection',
                      ),
                      const SizedBox(height: 16),
                      if (products.isNotEmpty &&
                          !isLoading &&
                          !snapshot.hasError) ...[
                        TextField(
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: 'Search your products',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.lightGrey,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.lightGrey,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in [
                              'All products',
                              'Low stock',
                              'Out of stock',
                            ].asMap().entries)
                              ChoiceChip(
                                label: Text(entry.value),
                                selected: _stockFilter == entry.key,
                                selectedColor: AppColors.primary,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _stockFilter == entry.key
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) =>
                                    setState(() => _stockFilter = entry.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${visibleProducts.length} shown of ${data.productCount} ${data.productCount == 1 ? 'product' : 'products'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (snapshot.hasError)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                color: AppColors.textSecondary,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Unable to load your shop',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please try again to see your products and sales.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _refresh,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      else if (products.isEmpty)
                        const _EmptyState()
                      else if (visibleProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No products match your search or filter.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else ...[
                        ...visibleProducts.map(
                          (product) => _SellerProductTile(
                            product: product,
                            isBestSeller:
                                bestSeller != null &&
                                product.id == bestSeller.id,
                            onEdit: () => _goToEditProduct(product),
                            onDelete: () => _deleteProduct(product),
                          ),
                        ),
                        if (data.hasMoreProducts)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Center(
                              child: _isLoadingMoreProducts
                                  ? const CircularProgressIndicator(
                                      color: AppColors.primary,
                                    )
                                  : OutlinedButton.icon(
                                      onPressed: _loadMoreProducts,
                                      icon: const Icon(
                                        Icons.expand_more_rounded,
                                      ),
                                      label: const Text('Load more products'),
                                    ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BestSellerCard extends StatelessWidget {
  final ProductModel? product;
  final int unitsSold;
  final bool _isLoading;

  const _BestSellerCard({
    required ProductModel this.product,
    required this.unitsSold,
  }) : _isLoading = false;

  const _BestSellerCard.loading()
    : product = null,
      unitsSold = 0,
      _isLoading = true;

  const _BestSellerCard.empty()
    : product = null,
      unitsSold = 0,
      _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _isLoading
          ? const SizedBox(
              height: 80,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          : product == null
          ? Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    "No sales yet — once an order comes in, your best seller will show up here.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: ProductImage(
                      path: product!.image,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: AppColors.lightGrey,
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: AppColors.secondary,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            "BEST SELLER",
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product!.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "$unitsSold ${unitsSold == 1 ? 'unit' : 'units'} sold",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SellerProductTile extends StatelessWidget {
  final ProductModel product;
  final bool isBestSeller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SellerProductTile({
    required this.product,
    this.isBestSeller = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lowStock = product.stock <= 5;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isBestSeller
            ? Border.all(
                color: AppColors.secondary.withValues(alpha: 0.5),
                width: 1.4,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 80,
              height: 80,
              child: ProductImage(
                path: product.image,
                fit: BoxFit.cover,
                placeholder: Container(
                  color: AppColors.lightGrey,
                  child: const Icon(
                    Icons.image_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBestSeller) ...[
                  const Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        color: AppColors.secondary,
                        size: 13,
                      ),
                      SizedBox(width: 3),
                      Text(
                        "BEST SELLER",
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  product.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "₱${product.price.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: lowStock
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    product.stock <= 0
                        ? "Out of stock"
                        : lowStock
                        ? "Low stock · ${product.stock} left"
                        : "${product.stock} in stock",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: lowStock ? AppColors.error : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Product actions',
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.textSecondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (action) {
              if (action == 'edit') onEdit();
              if (action == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 19),
                    SizedBox(width: 12),
                    Text('Edit product'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: AppColors.error,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Delete product',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_outlined,
              size: 34,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "No products yet",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Add your first handmade item to start selling.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DashboardData {
  final List<ProductModel> products;
  final SellerRevenueSummary revenue;
  final int productCount;
  final int unitsSold;
  final int lowStockCount;
  final ProductModel? bestSeller;
  final int? nextProductId;
  final bool hasMoreProducts;

  const _DashboardData({
    this.products = const [],
    this.revenue = const SellerRevenueSummary(
      currentMonth: 0,
      previousMonthToDate: 0,
    ),
    this.productCount = 0,
    this.unitsSold = 0,
    this.lowStockCount = 0,
    this.bestSeller,
    this.nextProductId,
    this.hasMoreProducts = false,
  });

  _DashboardData copyWith({
    List<ProductModel>? products,
    int? nextProductId,
    bool? hasMoreProducts,
  }) {
    return _DashboardData(
      products: products ?? this.products,
      revenue: revenue,
      productCount: productCount,
      unitsSold: unitsSold,
      lowStockCount: lowStockCount,
      bestSeller: bestSeller,
      nextProductId: nextProductId ?? this.nextProductId,
      hasMoreProducts: hasMoreProducts ?? this.hasMoreProducts,
    );
  }
}

const _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _RevenueSummaryCard extends StatelessWidget {
  final SellerRevenueSummary summary;
  final VoidCallback onView;

  const _RevenueSummaryCard({required this.summary, required this.onView});

  @override
  Widget build(BuildContext context) {
    final currentRevenue = summary.currentMonth;
    final previousRevenue = summary.previousMonthToDate;

    final change = previousRevenue == 0
        ? null
        : (currentRevenue - previousRevenue) / previousRevenue * 100;
    final positive = change != null && change >= 0;
    final trendColor = change == null
        ? AppColors.textSecondary
        : positive
        ? AppColors.success
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGrey.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.query_stats_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenue this month',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Confirmed delivered orders',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onView,
                child: const Text('View analytics'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _formatPeso(currentRevenue),
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                change == null
                    ? Icons.remove_rounded
                    : positive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: trendColor,
                size: 17,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  change == null
                      ? 'No prior-month revenue for comparison'
                      : '${change.abs().toStringAsFixed(1)}% ${positive ? 'increase' : 'decrease'} from the same period last month',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: trendColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Kept as the detailed embedded chart implementation for future tablet layouts.
// ignore: unused_element
class _MonthlyRevenueCard extends StatelessWidget {
  final List<SellerOrderItemModel> orders;
  final int selectedYear;
  final int selectedMonth;
  final int chartMode;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthSelected;
  final ValueChanged<int> onChartModeChanged;

  const _MonthlyRevenueCard({
    required this.orders,
    required this.selectedYear,
    required this.selectedMonth,
    required this.chartMode,
    required this.onYearChanged,
    required this.onMonthSelected,
    required this.onChartModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final revenueByMonth = <int, double>{};
    final years = <int>{DateTime.now().year};

    for (final order in orders) {
      final date = DateTime.tryParse(order.orderDate);
      if (date == null) continue;
      years.add(date.year);
      if (order.status.toLowerCase() != 'delivered') continue;
      final key = date.year * 100 + date.month;
      revenueByMonth[key] = (revenueByMonth[key] ?? 0) + order.lineTotal;
    }

    final availableYears = years.toList()..sort((a, b) => b.compareTo(a));
    final values = List<double>.generate(
      12,
      (index) => revenueByMonth[selectedYear * 100 + index + 1] ?? 0,
    );
    final selectedRevenue = values[selectedMonth - 1];
    final yearlyRevenue = values.fold<double>(0, (sum, value) => sum + value);
    final previousMonth = selectedMonth == 1 ? 12 : selectedMonth - 1;
    final previousYear = selectedMonth == 1 ? selectedYear - 1 : selectedYear;
    var previousRevenue =
        revenueByMonth[previousYear * 100 + previousMonth] ?? 0;
    final now = DateTime.now();
    final isCurrentMonth =
        selectedYear == now.year && selectedMonth == now.month;
    if (isCurrentMonth) {
      previousRevenue = 0;
      final previousMonthDays = DateTime(
        previousYear,
        previousMonth + 1,
        0,
      ).day;
      final comparisonDay = now.day < previousMonthDays
          ? now.day
          : previousMonthDays;
      for (final order in orders) {
        final date = DateTime.tryParse(order.orderDate);
        if (date != null &&
            order.status.toLowerCase() == 'delivered' &&
            date.year == previousYear &&
            date.month == previousMonth &&
            date.day <= comparisonDay) {
          previousRevenue += order.lineTotal;
        }
      }
    }
    final change = previousRevenue == 0
        ? null
        : ((selectedRevenue - previousRevenue) / previousRevenue) * 100;
    final maximum = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    final dailyValues = List<double>.filled(daysInMonth, 0);
    for (final order in orders) {
      final date = DateTime.tryParse(order.orderDate);
      if (date == null ||
          order.status.toLowerCase() != 'delivered' ||
          date.year != selectedYear ||
          date.month != selectedMonth) {
        continue;
      }
      dailyValues[date.day - 1] += order.lineTotal;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGrey.withValues(alpha: .75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales revenue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Confirmed delivered orders',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedYear,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    items: [
                      for (final year in availableYears)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) {
                      if (year != null) onYearChanged(year);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _RevenueModeSelector(
                  selectedMode: chartMode,
                  onChanged: onChartModeChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: selectedMonth,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: [
                        for (var index = 0; index < 12; index++)
                          DropdownMenuItem(
                            value: index + 1,
                            child: Text(_monthLabels[index]),
                          ),
                      ],
                      onChanged: (month) {
                        if (month != null) onMonthSelected(month);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_monthLabels[selectedMonth - 1]} revenue',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatPeso(selectedRevenue),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Year total',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatPeso(yearlyRevenue),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (chartMode == 0)
            SizedBox(
              height: 126,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < 12; index++)
                    Expanded(
                      child: _RevenueBar(
                        label: _monthLabels[index][0],
                        value: values[index],
                        maximum: maximum,
                        selected: selectedMonth == index + 1,
                        onTap: () => onMonthSelected(index + 1),
                      ),
                    ),
                ],
              ),
            )
          else
            _DailyRevenueChart(values: dailyValues),
          const SizedBox(height: 16),
          _RevenueAnalysis(
            change: change,
            currentRevenue: selectedRevenue,
            previousRevenue: previousRevenue,
            previousMonthLabel:
                '${_monthLabels[previousMonth - 1]}${isCurrentMonth ? ' for the same period' : ''}',
          ),
        ],
      ),
    );
  }
}

class _RevenueModeSelector extends StatelessWidget {
  final int selectedMode;
  final ValueChanged<int> onChanged;

  const _RevenueModeSelector({
    required this.selectedMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.lightGrey.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final entry in ['Monthly', 'Daily'].asMap().entries)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(entry.key),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selectedMode == entry.key
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: selectedMode == entry.key
                        ? [
                            BoxShadow(
                              color: AppColors.dark.withValues(alpha: .07),
                              blurRadius: 7,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: selectedMode == entry.key
                          ? AppColors.primary
                          : AppColors.textSecondary,
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

class _DailyRevenueChart extends StatelessWidget {
  final List<double> values;

  const _DailyRevenueChart({required this.values});

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    return SizedBox(
      height: 126,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final requiredWidth = values.length * 24.0;
          final chartWidth = requiredWidth > constraints.maxWidth
              ? requiredWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < values.length; index++)
                    Expanded(
                      child: _RevenueBar(
                        label: '${index + 1}',
                        value: values[index],
                        maximum: maximum,
                        selected: values[index] > 0,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RevenueBar extends StatelessWidget {
  final String label;
  final double value;
  final double maximum;
  final bool selected;
  final VoidCallback? onTap;

  const _RevenueBar({
    required this.label,
    required this.value,
    required this.maximum,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final barHeight = value == 0 ? 3.0 : 6 + (value / maximum * 88);
    return Semantics(
      button: onTap != null,
      label: '$label, ${_formatPeso(value)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : value == 0
                          ? AppColors.lightGrey
                          : AppColors.secondary.withValues(alpha: .5),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueAnalysis extends StatelessWidget {
  final double? change;
  final double currentRevenue;
  final double previousRevenue;
  final String previousMonthLabel;

  const _RevenueAnalysis({
    required this.change,
    required this.currentRevenue,
    required this.previousRevenue,
    required this.previousMonthLabel,
  });

  @override
  Widget build(BuildContext context) {
    final positive = change != null && change! >= 0;
    final unchanged = currentRevenue == previousRevenue;
    final color = unchanged
        ? AppColors.textSecondary
        : positive
        ? AppColors.success
        : AppColors.error;
    final icon = unchanged
        ? Icons.remove_rounded
        : positive
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;
    final difference = (currentRevenue - previousRevenue).abs();
    final message = change == null
        ? currentRevenue > 0
              ? 'Revenue started at ${_formatPeso(currentRevenue)}; $previousMonthLabel had no delivered sales.'
              : 'No delivered revenue in this month or $previousMonthLabel.'
        : unchanged
        ? 'Revenue is unchanged from $previousMonthLabel.'
        : 'Revenue ${positive ? 'increased' : 'decreased'} by ${_formatPeso(difference)} (${change!.abs().toStringAsFixed(1)}%) compared with $previousMonthLabel.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPeso(double value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < rounded.length; index++) {
    if (index > 0 && (rounded.length - index) % 3 == 0) buffer.write(',');
    buffer.write(rounded[index]);
  }
  return '₱$buffer';
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  final VoidCallback onTap;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: alert ? AppColors.error : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: AppColors.lightGrey);
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
