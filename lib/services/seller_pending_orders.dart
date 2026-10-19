import 'package:flutter/foundation.dart';

import '../repositories/order_repository.dart';
import '../utils/orders_live_refresh.dart';
import 'session_service.dart';

/// How many of the signed-in seller's orders are waiting for their action
/// (status Pending), shared by every screen's Orders tab and kept current as
/// orders arrive or change.
class SellerPendingOrders {
  SellerPendingOrders._();
  static final SellerPendingOrders instance = SellerPendingOrders._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);
  final OrderRepository _orders = OrderRepository();
  OrdersLiveRefresh? _live;
  int? _sellerId;

  /// Starts watching for the current seller (safe to call repeatedly) and
  /// refreshes the number.
  void start() {
    final id = SessionService.userId;
    if (id == null) {
      stop();
      return;
    }
    if (_sellerId != id) {
      _live?.dispose();
      count.value = 0;
      _sellerId = id;
      _live = OrdersLiveRefresh(
        name: 'seller-pending-orders',
        onChange: refresh,
      )..start();
    }
    refresh();
  }

  Future<void> refresh() async {
    final id = _sellerId;
    if (id == null) return;
    try {
      final pending = await _orders.getSellerPendingOrderCount(id);
      if (_sellerId == id) count.value = pending;
    } catch (_) {
      // Keep the last known number if the lookup fails.
    }
  }

  void stop() {
    _live?.dispose();
    _live = null;
    _sellerId = null;
    count.value = 0;
  }
}
