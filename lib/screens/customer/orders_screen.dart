import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/customer_order_item_model.dart';
import '../../models/cart_item_model.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/product_repository.dart';
import '../../services/order_functions_service.dart';
import '../../services/session_service.dart';
import '../../utils/date_formatter.dart';
import '../../utils/orders_live_refresh.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/product_image.dart';
import '../../widgets/rate_product_dialog.dart';
import 'chat_screen.dart';
import 'checkout_screen.dart';
import 'order_tracking_screen.dart';

const List<String> _kStatuses = [
  "Pending",
  "Preparing",
  "Shipped",
  "Out for Delivery",
  "Delivered",
  "Cancelled",
];

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  final ProductRepository _productRepository = ProductRepository();
  final OrderFunctionsService _orderFunctions = OrderFunctionsService();

  late Future<List<CustomerOrderItemModel>> _ordersFuture;
  String? _orderCursor;
  bool _hasMoreOrders = false;
  bool _isLoadingMore = false;
  String _filter = "All";

  late final OrdersLiveRefresh _live = OrdersLiveRefresh(
    name: 'customer-orders',
    onChange: _refreshQuietly,
  );

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _live.start();
  }

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  /// Re-reads the newest orders when one changes (for example a seller marks
  /// it Delivered) without a loading spinner, keeping any older pages loaded.
  Future<void> _refreshQuietly() async {
    final userId = SessionService.userId;
    if (!mounted || userId == null) return;
    try {
      final current = await _ordersFuture;
      final page = await _orderRepository.getCustomerOrderPage(userId);
      if (!mounted) return;
      final freshIds = {for (final item in page.items) item.itemId};
      final oldest = page.items.isEmpty ? null : page.items.last.orderDate;
      final older = [
        for (final item in current)
          if (!freshIds.contains(item.itemId) &&
              oldest != null &&
              item.orderDate.compareTo(oldest) < 0)
            item,
      ];
      setState(() {
        _ordersFuture = Future.value([...page.items, ...older]);
        if (older.isEmpty) {
          _orderCursor = page.cursor;
          _hasMoreOrders = page.hasMore;
        }
      });
    } catch (_) {
      // A failed background refresh keeps what is already on screen.
    }
  }

  void _loadOrders() {
    final userId = SessionService.userId;
    _orderCursor = null;
    _hasMoreOrders = false;
    _ordersFuture = userId == null
        ? Future.value(<CustomerOrderItemModel>[])
        : _orderRepository.getCustomerOrderPage(userId).then((page) {
            _orderCursor = page.cursor;
            _hasMoreOrders = page.hasMore;
            return page.items;
          });
  }

  Future<void> _refresh() async {
    setState(_loadOrders);
    await _ordersFuture;
  }

  Future<void> _loadMoreOrders() async {
    final userId = SessionService.userId;
    if (userId == null || !_hasMoreOrders || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final current = await _ordersFuture;
      final page = await _orderRepository.getCustomerOrderPage(
        userId,
        after: _orderCursor,
      );
      if (!mounted) return;
      setState(() {
        _orderCursor = page.cursor ?? _orderCursor;
        _hasMoreOrders = page.hasMore;
        _ordersFuture = Future.value([...current, ...page.items]);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more orders.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _messageSeller(CustomerOrderItemModel item) {
    if (item.sellerId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: item.sellerId!,
          otherUserName: item.sellerName,
          contextType: 'product',
          contextId: item.productId,
          contextName: item.productName,
          contextImage: item.productImage,
          contextPrice: item.itemPrice,
        ),
      ),
    );
  }

  Future<void> _rateProduct(CustomerOrderItemModel item) async {
    final userId = SessionService.userId;
    if (userId == null) return;

    final submitted = await showRateProductDialog(
      context,
      productId: item.productId,
      customerId: userId,
      productName: item.productName,
    );

    if (submitted && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Thanks for your rating!")));
    }
  }

  Future<void> _buyAgain(CustomerOrderItemModel item) async {
    final userId = SessionService.userId;
    if (userId == null) return;

    try {
      final product = await _productRepository.getProductById(item.productId);
      if (!mounted) return;

      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This product is no longer available.')),
        );
        return;
      }
      if (product.stock <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This product is currently out of stock.'),
          ),
        );
        return;
      }

      final quantity = item.quantity > product.stock
          ? product.stock
          : item.quantity;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckoutScreen(
            selectedItems: [
              CartItemModel(
                userId: userId,
                productId: item.productId,
                quantity: quantity,
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      setState(_loadOrders);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare this product.')),
      );
    }
  }

  Future<void> _cancelOrder(CustomerOrderItemModel item) async {
    if (item.status != 'Pending') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text(
          'Cancel "${item.productName}"? Only this product will be cancelled and returned to stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _orderFunctions.cancelOrderItem(
        orderId: item.orderId,
        itemId: item.itemId,
      );
      if (!mounted) return;
      setState(() {
        _filter = 'All';
        _loadOrders();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.productName}" was cancelled.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The order could not be cancelled.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNavbar(currentIndex: 3),
      appBar: AppBar(
        title: const Text(
          "My Orders",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: "All",
                    selected: _filter == "All",
                    onTap: () => setState(() => _filter = "All"),
                  ),
                  for (final status in _kStatuses) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: status,
                      selected: _filter == status,
                      onTap: () => setState(() => _filter = status),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _refresh,
              child: FutureBuilder<List<CustomerOrderItemModel>>(
                future: _ordersFuture,
                builder: (context, snapshot) {
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final allOrders =
                      snapshot.data ?? const <CustomerOrderItemModel>[];
                  final filtered = _filter == "All"
                      ? allOrders
                      : allOrders.where((o) => o.status == _filter).toList();

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 80),
                          child: Column(
                            children: [
                              const Text('Your orders could not be loaded.'),
                              TextButton(
                                onPressed: _refresh,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        if (filtered.isEmpty)
                          _EmptyOrdersState(hasAnyOrders: allOrders.isNotEmpty)
                        else
                          ...filtered.map(
                            (item) => OrderTile(
                              key: ValueKey(item.itemId),
                              item: item,
                              onMessageSeller: () => _messageSeller(item),
                              onRateProduct: () => _rateProduct(item),
                              onBuyAgain: () => _buyAgain(item),
                              onCancelOrder: () => _cancelOrder(item),
                              onTrackOrder: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OrderTrackingScreen(
                                      orderId: item.orderId,
                                      sellerId: item.sellerId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        if (_hasMoreOrders)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              onPressed: _isLoadingMore
                                  ? null
                                  : _loadMoreOrders,
                              child: _isLoadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load more orders'),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case "Preparing":
      return Colors.orange;
    case "Shipped":
      return AppColors.primary;
    case "Out for Delivery":
      return Colors.blue;
    case "Delivered":
      return AppColors.success;
    case "Cancelled":
      return AppColors.error;
    case "Pending":
    default:
      return AppColors.secondary;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.lightGrey,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One product line of a customer's order, with the actions for its status.
class OrderTile extends StatelessWidget {
  final CustomerOrderItemModel item;
  final VoidCallback onMessageSeller;
  final VoidCallback onRateProduct;
  final VoidCallback onBuyAgain;
  final VoidCallback onTrackOrder;
  final VoidCallback onCancelOrder;

  const OrderTile({
    super.key,
    required this.item,
    required this.onMessageSeller,
    required this.onRateProduct,
    required this.onBuyAgain,
    required this.onTrackOrder,
    required this.onCancelOrder,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);

    return InkWell(
      onTap: onTrackOrder,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Order #${item.orderId}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatOrderDate(item.orderDate),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (item.sellerId != null)
                      IconButton(
                        tooltip: 'Message seller',
                        onPressed: onMessageSeller,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 30,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: ProductImage(
                      path: item.productImage,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if ((item.optionName ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.optionName!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        "Sold by ${item.sellerName} · Qty ${item.quantity}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "₱${item.lineTotal.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                if (item.status == 'Pending')
                  OutlinedButton(
                    onPressed: onCancelOrder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: const Text(
                      'Cancel Order',
                      style: TextStyle(fontSize: 10.5),
                    ),
                  )
                else if (item.status == "Delivered")
                  // A stretched Column needs a bounded width. Inside this Row
                  // it had none, so Flutter could not lay the tile out and
                  // every Delivered order silently disappeared from the list.
                  SizedBox(
                    width: 94,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 94,
                          height: 32,
                          child: OutlinedButton.icon(
                            onPressed: onRateProduct,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondary,
                              side: const BorderSide(
                                color: AppColors.secondary,
                              ),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            icon: const Icon(
                              Icons.star_outline_rounded,
                              size: 14,
                            ),
                            label: const Text(
                              'Rate Product',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 94,
                          height: 32,
                          child: ElevatedButton(
                            onPressed: onBuyAgain,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            child: const Text(
                              'Buy Again',
                              style: TextStyle(
                                fontSize: 10.5,
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
          ],
        ),
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  final bool hasAnyOrders;
  const _EmptyOrdersState({required this.hasAnyOrders});

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
              Icons.receipt_long_outlined,
              size: 34,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasAnyOrders ? "No orders with this status" : "No orders yet",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasAnyOrders
                ? "Try a different filter above."
                : "Orders you place will show up here.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
