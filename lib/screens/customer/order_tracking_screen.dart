import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/order_tracking_model.dart';
import '../../repositories/order_repository.dart';
import '../../utils/date_formatter.dart';

const _trackingStatuses = [
  'Pending',
  'Preparing',
  'Shipped',
  'Out for Delivery',
  'Delivered',
];

class OrderTrackingScreen extends StatelessWidget {
  final int orderId;
  final int? sellerId;

  const OrderTrackingScreen({super.key, required this.orderId, this.sellerId});

  @override
  Widget build(BuildContext context) {
    final repository = OrderRepository();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Track Order #$orderId'),
      ),
      body: StreamBuilder<OrderTrackingModel?>(
        stream: repository.watchOrderTracking(orderId, sellerId: sellerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(
              child: Text('Tracking information is currently unavailable.'),
            );
          }

          final tracking = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TrackingHeader(tracking: tracking),
              const SizedBox(height: 14),
              _DeliveryMap(tracking: tracking),
              const SizedBox(height: 14),
              _ShippingDetails(tracking: tracking),
              const SizedBox(height: 20),
              const Text(
                'Delivery progress',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _StatusTimeline(tracking: tracking),
              if (tracking.history.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Tracking updates',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...tracking.history.reversed.map(
                  (event) => _HistoryTile(event: event),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _TrackingHeader extends StatelessWidget {
  final OrderTrackingModel tracking;
  const _TrackingHeader({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final delivered = tracking.status == 'Delivered';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: delivered
              ? [AppColors.success, const Color(0xFF57B894)]
              : [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              delivered ? Icons.check_rounded : Icons.local_shipping_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracking.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (tracking.currentLocation.isNotEmpty)
                  Text(
                    tracking.currentLocation,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryMap extends StatelessWidget {
  final OrderTrackingModel tracking;
  const _DeliveryMap({required this.tracking});

  int get _progress {
    final index = _trackingStatuses.indexOf(tracking.status);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RouteMapPainter(progress: _progress)),
          ),
          const Positioned(
            left: 18,
            bottom: 14,
            child: _MapLabel(icon: Icons.storefront_outlined, label: 'Seller'),
          ),
          const Positioned(
            right: 18,
            top: 14,
            child: _MapLabel(icon: Icons.home_outlined, label: 'Delivery'),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 82,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tracking.currentLocation.isEmpty
                            ? 'Waiting for a location update'
                            : tracking.currentLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 12,
            top: 12,
            child: Text(
              'DELIVERY ROUTE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  final int progress;
  const _RouteMapPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFFDDE1D8)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    final minorRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final y = 35.0 + (i * 48);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 25), roadPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 25), minorRoad);
    }

    final route = Path()
      ..moveTo(45, size.height - 38)
      ..cubicTo(
        size.width * .28,
        size.height * .70,
        size.width * .62,
        size.height * .45,
        size.width - 46,
        42,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.28)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    final fraction = (progress / 4).clamp(0.0, 1.0);
    final metric = route.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteMapPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MapLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MapLabel({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

class _ShippingDetails extends StatelessWidget {
  final OrderTrackingModel tracking;
  const _ShippingDetails({required this.tracking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        children: [
          _DetailRow(
            label: 'Courier',
            value: tracking.courier.isEmpty
                ? 'Not assigned yet'
                : tracking.courier,
          ),
          const Divider(height: 18),
          _DetailRow(
            label: 'Tracking number',
            value: tracking.trackingNumber.isEmpty
                ? 'Not available yet'
                : tracking.trackingNumber,
          ),
          const Divider(height: 18),
          _DetailRow(
            label: 'Estimated delivery',
            value: tracking.estimatedDeliveryDate.isEmpty
                ? 'To be announced'
                : formatOrderDate(tracking.estimatedDeliveryDate),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 125,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _StatusTimeline extends StatelessWidget {
  final OrderTrackingModel tracking;
  const _StatusTimeline({required this.tracking});
  @override
  Widget build(BuildContext context) {
    final activeIndex = _trackingStatuses.indexOf(tracking.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        children: List.generate(_trackingStatuses.length, (index) {
          final active = index <= activeIndex;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: active
                        ? AppColors.primary
                        : AppColors.lightGrey,
                    child: Icon(
                      active ? Icons.check_rounded : Icons.circle_outlined,
                      size: 14,
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                  if (index < _trackingStatuses.length - 1)
                    Container(
                      width: 2,
                      height: 31,
                      color: active
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : AppColors.lightGrey,
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  _trackingStatuses[index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final TrackingEventModel event;
  const _HistoryTile({required this.event});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          color: AppColors.primary,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.status,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (event.location.isNotEmpty)
                Text(
                  event.location,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        Text(
          formatOrderDate(event.date),
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}
