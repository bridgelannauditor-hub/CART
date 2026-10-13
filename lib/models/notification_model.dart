import '../database/tables.dart';

class NotificationModel {
  final String? id;
  final int userId;
  final String title;
  final String body;

  /// e.g. "order" (new order for a seller), "order_status" (status
  /// update for a buyer), "message" (new chat message).
  final String type;

  /// Meaning depends on [type]: an order id for order/order_status
  /// notifications, or the sender's user id for message notifications.
  final int? relatedId;

  final String createdDate;
  final bool isRead;

  NotificationModel({
    this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.relatedId,
    required this.createdDate,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.notifUserId: userId,
      DBTables.notifTitle: title,
      DBTables.notifBody: body,
      DBTables.notifType: type,
      DBTables.notifRelatedId: relatedId,
      DBTables.notifDate: createdDate,
      DBTables.isRead: isRead ? 1 : 0,
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map[DBTables.id]?.toString(),
      userId: map[DBTables.notifUserId],
      title: map[DBTables.notifTitle] ?? '',
      body: map[DBTables.notifBody] ?? '',
      type: map[DBTables.notifType] ?? '',
      relatedId: map[DBTables.notifRelatedId],
      createdDate: map[DBTables.notifDate] ?? '',
      isRead: (map[DBTables.isRead] ?? 0) == 1,
    );
  }

  factory NotificationModel.fromSupabaseMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as String?,
      userId: (map['user_id'] as num).toInt(),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? '',
      relatedId: (map['related_id'] as num?)?.toInt(),
      createdDate: map['created_at'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSupabaseMap() => {
    'user_id': userId,
    'title': title,
    'body': body,
    'type': type,
    'related_id': relatedId,
    'created_at': createdDate,
    'is_read': isRead,
  };
}
