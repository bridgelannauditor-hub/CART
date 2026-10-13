import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/seller_order_item_model.dart';
import '../../repositories/order_repository.dart';
import '../../services/order_functions_service.dart';
import '../../services/session_service.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/product_image.dart';
import '../../widgets/seller_bottom_navbar.dart';
import 'seller_tracking_screen.dart';

const List<String> _kStatuses = [
  "Pending",
  "Preparing",
  "Shipped",
  "Out for Delivery",
  "Delivered",
  "Cancelled",
];

List<String> _nextSellerStatuses(String current) => switch (current) {
  'Pending' => const ['Preparing', 'Cancelled'],
  'Preparing' => const ['Shipped', 'Cancelled'],
  'Shipped' => const ['Out for Delivery'],
  'Out for Delivery' => const ['Delivered'],
  _ => const [],
};

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  final OrderFunctionsService _orderFunctions = OrderFunctionsService();

  late Future<List<SellerOrderItemModel>> _ordersFuture;
  String? _orderCursor;
  bool _hasMoreOrders = false;
  bool _isLoadingMore = false;
  String _filter = "All";

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  void _loadOrders() {
    final sellerId = SessionService.userId;
    _orderCursor = null;
    _hasMoreOrders = false;
    _ordersFuture = sellerId == null
        ? Future.value(<SellerOrderItemModel>[])
        : _orderRepository.getSellerOrderPage(sellerId).then((page) {
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
    final sellerId = SessionService.userId;
    if (sellerId == null || !_hasMoreOrders || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final current = await _ordersFuture;
      final page = await _orderRepository.getSellerOrderPage(
        sellerId,
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

  Future<void> _changeStatus(SellerOrderItemModel item, String status) async {
    if (status == item.status) return;
    try {
      await _orderFunctions.updateSellerOrder(
        orderId: item.orderId,
        status: status,
      );
      if (!mounted) return;
      setState(_loadOrders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.darkGrey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text("Order #${item.orderId} marked as $status."),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  Future<void> _manageTracking(SellerOrderItemModel item) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SellerTrackingScreen(order: item)),
    );
    if (updated == true && mounted) setState(_loadOrders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Orders",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      bottomNavigationBar: const SellerBottomNavbar(currentIndex: 3),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: FutureBuilder<List<SellerOrderItemModel>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final allOrders = snapshot.data ?? const <SellerOrderItemModel>[];

            final filtered = _filter == "All"
                ? allOrders
                : allOrders.where((o) => o.status == _filter).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                SizedBox(
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

                const SizedBox(height: 18),

                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else ...[
                  if (filtered.isEmpty)
                    _EmptyOrdersState(hasAnyOrders: allOrders.isNotEmpty)
                  else
                    ...filtered.map(
                      (item) => _OrderTile(
                        key: ValueKey(item.itemId),
                        item: item,
                        onStatusChanged: (status) =>
                            _changeStatus(item, status),
                        onManageTracking: () => _manageTracking(item),
                      ),
                    ),
                  if (_hasMoreOrders)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton(
                        onPressed: _isLoadingMore ? null : _loadMoreOrders,
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

class _OrderTile extends StatelessWidget {
  final SellerOrderItemModel item;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onManageTracking;

  const _OrderTile({
    super.key,
    required this.item,
    required this.onStatusChanged,
    required this.onManageTracking,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    final nextStatuses = _nextSellerStatuses(item.status);

    return Container(
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
              Text(
                formatOrderDate(item.orderDate),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
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
                      "${item.customerName} · Qty ${item.quantity}",
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              if (nextStatuses.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: onStatusChanged,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  itemBuilder: (context) => nextStatuses
                      .map(
                        (status) => PopupMenuItem<String>(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Update status",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: onManageTracking,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: const Icon(Icons.map_outlined, size: 17),
              label: const Text(
                'Update Tracking',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
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
                : "Orders placed for your products will show up here.",
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
