import 'message_model.dart';

/// A summarized conversation with one other user — used for the
/// conversation list screen. Built in Dart from raw message rows
/// (see MessageRepository), not stored directly in the database.
class ConversationModel {
  final int otherUserId;
  final String otherUserName;
  final String? otherUserProfileImage;
  final MessageModel lastMessage;
  final int unreadCount;

  ConversationModel({
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserProfileImage,
    required this.lastMessage,
    required this.unreadCount,
  });
}
