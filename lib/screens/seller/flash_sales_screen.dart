import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/flash_sale_model.dart';
import '../../repositories/flash_sale_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';
import 'create_flash_sale_screen.dart';

class FlashSalesScreen extends StatefulWidget {
  const FlashSalesScreen({super.key});

  @override
  State<FlashSalesScreen> createState() => _FlashSalesScreenState();
}

class _FlashSalesScreenState extends State<FlashSalesScreen> {
  final _repository = FlashSaleRepository();
  List<FlashSaleListing> _sales = [];
  bool _loading = true;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps "starts in" / "ends in" current while the screen is open.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sales = await _repository.mySales(SessionService.userId!);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is StateError
            ? error.message
            : "Couldn't load flash sales. Pull to retry.";
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateFlashSaleScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _cancel(FlashSaleListing listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel flash sale?'),
        content: Text(
          'Customers will see the regular price for '
          '"${listing.product?.productName ?? 'this product'}" right away. '
          'Orders already placed keep their flash price.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel sale'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.cancel(listing.sale.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          content: Text(
            error is StateError ? error.message : "Couldn't cancel: $error",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool inGroup(FlashSaleListing listing, Set<FlashSaleStatus> statuses) =>
        statuses.contains(listing.sale.statusAt(now));
    final live = _sales
        .where(
          (s) => inGroup(s, {FlashSaleStatus.live, FlashSaleStatus.soldOut}),
        )
        .toList();
    final upcoming =
        _sales.where((s) => inGroup(s, {FlashSaleStatus.scheduled})).toList()
          ..sort((a, b) => a.sale.startsAt.compareTo(b.sale.startsAt));
    final past = _sales
        .where(
          (s) => inGroup(s, {FlashSaleStatus.ended, FlashSaleStatus.cancelled}),
        )
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F5),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Flash Sale',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.bolt_rounded),
        label: const Text('New flash sale'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  if (_sales.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        'No flash sales yet.\n\nA product can join a flash '
                        'sale once it has been listed for 7 days and has at '
                        'least 1 delivered sale.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ..._section('Live', live, now),
                  ..._section('Upcoming', upcoming, now),
                  ..._section('Past', past, now),
                ],
              ),
            ),
    );
  }

  List<Widget> _section(
    String title,
    List<FlashSaleListing> sales,
    DateTime now,
  ) {
    if (sales.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      for (final listing in sales)
        _FlashSaleCard(
          listing: listing,
          now: now,
          onCancel: () => _cancel(listing),
        ),
    ];
  }
}

class _FlashSaleCard extends StatelessWidget {
  final FlashSaleListing listing;
  final DateTime now;
  final VoidCallback onCancel;

  const _FlashSaleCard({
    required this.listing,
    required this.now,
    required this.onCancel,
  });

  static String _duration(Duration duration) {
    if (duration.inDays >= 1) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    return '${duration.inMinutes.clamp(1, 59)}m';
  }

  @override
  Widget build(BuildContext context) {
    final sale = listing.sale;
    final product = listing.product;
    final status = sale.statusAt(now);
    final format = DateFormat.yMMMd().add_jm();
    final (statusLabel, statusColor) = switch (status) {
      FlashSaleStatus.live => ('Live', AppColors.success),
      FlashSaleStatus.soldOut => ('Sold out', AppColors.secondary),
      FlashSaleStatus.scheduled => ('Scheduled', AppColors.primary),
      FlashSaleStatus.ended => ('Ended', AppColors.textSecondary),
      FlashSaleStatus.cancelled => ('Cancelled', AppColors.textSecondary),
    };
    final timing = switch (status) {
      FlashSaleStatus.scheduled =>
        'Starts in ${_duration(sale.startsAt.difference(now))} · '
            '${format.format(sale.startsAt)}',
      FlashSaleStatus.live || FlashSaleStatus.soldOut =>
        'Ends in ${_duration(sale.endsAt.difference(now))} · '
            '${format.format(sale.endsAt)}',
      FlashSaleStatus.ended => 'Ended ${format.format(sale.endsAt)}',
      FlashSaleStatus.cancelled =>
        'Cancelled ${format.format(sale.cancelledAt!)}',
    };
    final priceText = product == null
        ? '${sale.discountPercent}% off'
        : product.hasImageOptions
        ? '${sale.discountPercent}% off every picture price'
        : '${sale.discountPercent}% off · '
              '₱${sale.priceFor(product.price).toStringAsFixed(2)} '
              '(was ₱${product.price.toStringAsFixed(2)})';
    final canCancel =
        status != FlashSaleStatus.ended && status != FlashSaleStatus.cancelled;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ProductImage(
                path: product?.image ?? '',
                maxDecodeWidth: 120,
                placeholder: Container(
                  color: AppColors.lightGrey,
                  child: const Icon(Icons.image_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product?.productName ?? 'Removed product',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(priceText, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  '${sale.sold} of ${sale.promoStock} sold · limit '
                  '${sale.perCustomerLimit} per customer',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timing,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (canCancel)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Cancel sale'),
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
