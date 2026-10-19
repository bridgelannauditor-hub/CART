import 'package:flutter/material.dart';

import '../services/seller_pending_orders.dart';
import 'count_badge.dart';

/// The seller's Orders tab icon, with a red number of orders waiting for them.
class SellerOrdersNavIcon extends StatefulWidget {
  const SellerOrdersNavIcon({super.key, this.selected = false});
  final bool selected;

  @override
  State<SellerOrdersNavIcon> createState() => _SellerOrdersNavIconState();
}

class _SellerOrdersNavIconState extends State<SellerOrdersNavIcon> {
  @override
  void initState() {
    super.initState();
    SellerPendingOrders.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SellerPendingOrders.instance.count,
      builder: (context, count, _) => CountBadge(
        count: count,
        child: Icon(
          widget.selected ? Icons.receipt_long : Icons.receipt_long_outlined,
        ),
      ),
    );
  }
}
