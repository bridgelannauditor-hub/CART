import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_order_item_model.dart';
import '../models/order_tracking_model.dart';
import '../models/product_model.dart';
import '../models/seller_order_item_model.dart';
import 'product_repository.dart';
import 'user_repository.dart';

class OrderPage<T> {
  final List<T> items;
  final String? cursor;
  final bool hasMore;

  const OrderPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class SellerRevenueSummary {
  final double currentMonth;
  final double previousMonthToDate;

  const SellerRevenueSummary({
    required this.currentMonth,
    required this.previousMonthToDate,
  });
}

class OrderRepository {
  SupabaseClient get _supabase => Supabase.instance.client;
  final ProductRepository _productRepository = ProductRepository();
  final UserRepository _userRepository = UserRepository();

  Future<List<CustomerOrderItemModel>> getOrderItemsForCustomer(
    int customerId,
  ) async {
    final orders = await _supabase
        .from('orders')
        .select()
        .eq('customer_id', customerId)
        .order('order_date', ascending: false);
    return _customerItems(orders);
  }

  Future<OrderPage<CustomerOrderItemModel>> getCustomerOrderPage(
    int customerId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase.from('orders').select().eq('customer_id', customerId);
    if (after != null) query = query.lt('order_date', after);
    final rows = await query
        .order('order_date', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();
    return OrderPage(
      items: await _customerItems(pageRows),
      cursor: pageRows.isEmpty ? after : pageRows.last['order_date'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<List<SellerOrderItemModel>> getSellerOrderItemsForPeriod(
    int sellerId, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!start.isBefore(end)) {
      throw ArgumentError('The analytics start must be before its end.');
    }
    final orders = await _supabase
        .from('orders')
        .select()
        .contains('seller_ids', [sellerId])
        .gte('order_date', start.toUtc().toIso8601String())
        .lt('order_date', end.toUtc().toIso8601String())
        .order('order_date', ascending: false);
    return _sellerItems(orders, sellerId);
  }

  Future<SellerRevenueSummary> getSellerRevenueSummary(
    int sellerId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final nextMonthStart = DateTime(current.year, current.month + 1);
    final previousMonthStart = DateTime(current.year, current.month - 1);
    final items = await getSellerOrderItemsForPeriod(
      sellerId,
      start: previousMonthStart,
      end: nextMonthStart,
    );
    final previousMonthDays = DateTime(
      previousMonthStart.year,
      previousMonthStart.month + 1,
      0,
    ).day;
    final comparisonDay = current.day < previousMonthDays
        ? current.day
        : previousMonthDays;
    var currentRevenue = 0.0;
    var previousRevenue = 0.0;
    for (final item in items) {
      if (item.status.toLowerCase() != 'delivered') continue;
      final date = DateTime.tryParse(item.orderDate)?.toLocal();
      if (date == null) continue;
      if (date.year == current.year && date.month == current.month) {
        currentRevenue += item.lineTotal;
      } else if (date.year == previousMonthStart.year &&
          date.month == previousMonthStart.month &&
          date.day <= comparisonDay) {
        previousRevenue += item.lineTotal;
      }
    }
    return SellerRevenueSummary(
      currentMonth: currentRevenue,
      previousMonthToDate: previousRevenue,
    );
  }

  /// Orders (not items) with products still Pending for this seller.
  Future<int> getSellerPendingOrderCount(int sellerId) async {
    final rows = await _supabase
        .from('order_items')
        .select('order_id')
        .eq('seller_id', sellerId)
        .eq('status', 'Pending');
    return {for (final row in rows) (row['order_id'] as num).toInt()}.length;
  }

  Future<OrderPage<SellerOrderItemModel>> getSellerOrderPage(
    int sellerId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase.from('orders').select().contains('seller_ids', [
      sellerId,
    ]);
    if (after != null) query = query.lt('order_date', after);
    final rows = await query
        .order('order_date', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();
    return OrderPage(
      items: await _sellerItems(pageRows, sellerId),
      cursor: pageRows.isEmpty ? after : pageRows.last['order_date'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<List<CustomerOrderItemModel>> _customerItems(
    List<Map<String, dynamic>> orders,
  ) async {
    if (orders.isEmpty) return [];
    final orderIds = orders.map((row) => (row['id'] as num).toInt()).toList();
    final items = await _supabase
        .from('order_items')
        .select()
        .inFilter('order_id', orderIds);
    final sellerIds = items
        .map((row) => (row['seller_id'] as num).toInt())
        .toSet();
    final sellers = await _userRepository.getUsersByIds(sellerIds);
    final sellerById = {for (final seller in sellers) seller.id: seller};
    final orderById = {
      for (final order in orders) (order['id'] as num).toInt(): order,
    };
    final result = <CustomerOrderItemModel>[];
    for (final item in items) {
      final orderId = (item['order_id'] as num).toInt();
      final order = orderById[orderId];
      if (order == null) continue;
      final sellerId = (item['seller_id'] as num).toInt();
      final seller = sellerById[sellerId];
      result.add(
        CustomerOrderItemModel(
          itemId: (item['id'] as num).toInt(),
          orderId: orderId,
          productId: (item['product_id'] as num).toInt(),
          quantity: (item['quantity'] as num).toInt(),
          itemPrice: (item['item_price'] as num).toDouble(),
          status: item['status'] as String? ?? 'Pending',
          orderDate: order['order_date'] as String? ?? '',
          productName: item['product_name'] as String? ?? '',
          productImage: item['product_image'] as String? ?? '',
          sellerId: sellerId,
          sellerFirstName: seller?.firstName ?? '',
          sellerLastName: seller?.lastName ?? '',
          optionId: item['option_id'] as String?,
          optionName: item['option_name'] as String?,
          optionImage: item['option_image'] as String?,
        ),
      );
    }
    result.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return result;
  }

  Future<List<SellerOrderItemModel>> _sellerItems(
    List<Map<String, dynamic>> orders,
    int sellerId,
  ) async {
    if (orders.isEmpty) return [];
    final orderIds = orders.map((row) => (row['id'] as num).toInt()).toList();
    final items = await _supabase
        .from('order_items')
        .select()
        .inFilter('order_id', orderIds)
        .eq('seller_id', sellerId);
    final customerIds = orders
        .map((row) => (row['customer_id'] as num).toInt())
        .toSet();
    final customers = await _userRepository.getUsersByIds(customerIds);
    final customerById = {for (final user in customers) user.id: user};
    final orderById = {
      for (final order in orders) (order['id'] as num).toInt(): order,
    };
    final result = <SellerOrderItemModel>[];
    for (final item in items) {
      final orderId = (item['order_id'] as num).toInt();
      final order = orderById[orderId];
      if (order == null) continue;
      final customerId = (order['customer_id'] as num).toInt();
      final customer = customerById[customerId];
      result.add(
        SellerOrderItemModel(
          itemId: (item['id'] as num).toInt(),
          orderId: orderId,
          productId: (item['product_id'] as num).toInt(),
          quantity: (item['quantity'] as num).toInt(),
          itemPrice: (item['item_price'] as num).toDouble(),
          status: item['status'] as String? ?? 'Pending',
          orderDate: order['order_date'] as String? ?? '',
          customerId: customerId,
          productName: item['product_name'] as String? ?? '',
          productImage: item['product_image'] as String? ?? '',
          customerFirstName: customer?.firstName ?? '',
          customerLastName: customer?.lastName ?? '',
          optionId: item['option_id'] as String?,
          optionName: item['option_name'] as String?,
          optionImage: item['option_image'] as String?,
        ),
      );
    }
    result.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return result;
  }

  Stream<OrderTrackingModel?> watchOrderTracking(int orderId, {int? sellerId}) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : OrderTrackingModel.fromOrderMap(
                  _trackingMap(rows.first),
                  sellerId: sellerId,
                ),
        );
  }

  Future<OrderTrackingModel?> getOrderTracking(
    int orderId, {
    int? sellerId,
  }) async {
    final row = await _supabase
        .from('orders')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    return row == null
        ? null
        : OrderTrackingModel.fromOrderMap(
            _trackingMap(row),
            sellerId: sellerId,
          );
  }

  Map<String, dynamic> _trackingMap(Map<String, dynamic> row) => {
    'id': row['id'],
    'status': row['status'],
    'sellerFulfillment': row['seller_fulfillment'],
    'tracking': row['tracking'],
  };

  Future<List<int>> getSellerIdsForOrder(int orderId) async {
    final row = await _supabase
        .from('orders')
        .select('seller_ids')
        .eq('id', orderId)
        .maybeSingle();
    return ((row?['seller_ids'] as List?) ?? const [])
        .map((value) => (value as num).toInt())
        .toSet()
        .toList();
  }

  Future<List<(ProductModel, int)>> getBestSellingProducts({
    int limit = 10,
  }) async {
    final products = await _productRepository.getTopSellingProducts(
      limit: limit,
    );
    return products.map((product) => (product, product.totalSold)).toList();
  }
}
