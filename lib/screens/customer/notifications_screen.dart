import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/notification_model.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/shop_repository.dart';
import '../../services/session_service.dart';
import 'orders_screen.dart';
import 'order_tracking_screen.dart';
import 'live_viewer_screen.dart';
import '../seller/seller_orders_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationRepository _notificationRepository =
      NotificationRepository();

  final List<NotificationModel> _notifications = [];
  String? _cursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final userId = SessionService.userId;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _notifications.clear();
          _isLoading = false;
          _hasMore = false;
        });
      }
      return;
    }
    if (!reset && (_isLoadingMore || !_hasMore)) return;

    setState(() {
      _error = null;
      if (reset) {
        _isLoading = true;
        _cursor = null;
        _hasMore = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await _notificationRepository.getNotificationsPage(
        userId,
        after: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _notifications.clear();
        final existingIds = _notifications
            .map((notification) => notification.id)
            .toSet();
        _notifications.addAll(
          page.items.where(
            (notification) => !existingIds.contains(notification.id),
          ),
        );
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Notifications could not be loaded.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _load(reset: true);
  }

  Future<void> _markAllRead() async {
    final userId = SessionService.userId;
    if (userId == null) return;

    await _notificationRepository.markAllRead(userId);
    await _load(reset: true);
  }

  Future<void> _openNotification(NotificationModel notification) async {
    if (notification.id != null && !notification.isRead) {
      await _notificationRepository.markRead(notification.id!);
    }

    if (notification.type == 'order') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SellerOrdersScreen()),
      );
    } else if (notification.type == 'order_status') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => notification.relatedId == null
              ? const OrdersScreen()
              : OrderTrackingScreen(orderId: notification.relatedId!),
        ),
      );
    } else if (notification.type == 'live' && notification.relatedId != null) {
      final shop = await ShopRepository().getShop(notification.relatedId!);
      if (!mounted || shop == null) return;
      if (!shop.isLive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This LIVE has already ended.')),
        );
      } else {
        final shopName = (shop.shopName?.trim().isNotEmpty ?? false)
            ? shop.shopName!.trim()
            : '${shop.firstName} ${shop.lastName}'.trim();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LiveViewerScreen(shopName: shopName, sellerId: shop.id!),
          ),
        );
      }
    }

    await _load(reset: true);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case "order":
        return Icons.storefront_outlined;
      case "order_status":
        return Icons.local_shipping_outlined;
      case "live":
        return Icons.live_tv_outlined;
      default:
        return Icons.notifications_outlined;
    }
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
          "Notifications",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text(
              "Mark all read",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          const SizedBox(height: 100),
          Icon(
            _error == null
                ? Icons.notifications_none_rounded
                : Icons.cloud_off_rounded,
            size: 56,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'No notifications yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _error == null
                  ? 'Order updates will show up here.'
                  : 'Pull down to try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      itemCount: _notifications.length + (_hasMore || _error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _notifications.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isLoadingMore
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : OutlinedButton(
                      onPressed: () => _load(reset: false),
                      child: Text(
                        _error == null ? 'Load older notifications' : 'Retry',
                      ),
                    ),
            ),
          );
        }
        final notification = _notifications[index];
        return _NotificationTile(
          notification: notification,
          icon: _iconForType(notification.type),
          onTap: () => _openNotification(notification),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final IconData icon;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: unread
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.lightGrey,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
