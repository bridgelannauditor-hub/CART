import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';

class NotificationPage {
  final List<NotificationModel> items;
  final String? cursor;
  final bool hasMore;

  const NotificationPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class NotificationRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<NotificationModel>> getNotificationsForUser(int userId) async {
    final rows = await _supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .neq('type', 'message')
        .order('created_at', ascending: false);
    return rows.map(NotificationModel.fromSupabaseMap).toList();
  }

  Future<NotificationPage> getNotificationsPage(
    int userId, {
    String? after,
    int pageSize = 20,
  }) async {
    if (pageSize <= 0 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Use 1 to 50 items.');
    }

    var query = _supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .neq('type', 'message');
    if (after != null) query = query.lt('created_at', after);
    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();

    return NotificationPage(
      items: pageRows.map(NotificationModel.fromSupabaseMap).toList(),
      cursor: pageRows.isEmpty ? after : pageRows.last['created_at'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<int> getUnreadCount(int userId) async {
    final rows = await _supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return rows.length;
  }

  Future<void> markRead(String id) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);
  }

  Future<void> markAllRead(int userId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  Future<void> _create({
    required int userId,
    required String title,
    required String body,
    required String type,
    int? relatedId,
  }) async {
    await _supabase.rpc(
      'create_notification',
      params: {
        'target_user_id': userId,
        'notification_title': title,
        'notification_body': body,
        'notification_type': type,
        'notification_related_id': relatedId,
      },
    );
  }

  Future<void> notifyNewOrder({
    required int sellerId,
    required int orderId,
    required String productName,
  }) {
    return _create(
      userId: sellerId,
      title: 'New order received',
      body: 'Someone ordered "$productName".',
      type: 'order',
      relatedId: orderId,
    );
  }

  Future<void> notifyOrderStatusChange({
    required int customerId,
    required int orderId,
    required String status,
  }) {
    return _create(
      userId: customerId,
      title: 'Order #$orderId update',
      body: 'Your order is now "$status".',
      type: 'order_status',
      relatedId: orderId,
    );
  }

  Future<void> notifyOrderCancelled({
    required int sellerId,
    required int orderId,
    String? productName,
  }) {
    final cancelledProduct = productName?.trim();
    return _create(
      userId: sellerId,
      title: 'Product cancelled from order #$orderId',
      body: cancelledProduct == null || cancelledProduct.isEmpty
          ? 'The customer cancelled a pending product.'
          : 'The customer cancelled "$cancelledProduct".',
      type: 'order',
      relatedId: orderId,
    );
  }

  Future<void> notifyFollowersSellerLive({
    required int sellerId,
    required String shopName,
  }) async {
    final follows = await _supabase
        .from('shop_follows')
        .select('follower_id')
        .eq('seller_id', sellerId);
    await Future.wait([
      for (final follow in follows)
        _create(
          userId: (follow['follower_id'] as num).toInt(),
          title: '$shopName is LIVE',
          body: 'Watch now, ask questions, and browse featured products.',
          type: 'live',
          relatedId: sellerId,
        ),
    ]);
  }
}
