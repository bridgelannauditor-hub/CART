class MessageModel {
  final String? documentId;
  final int? id;
  final int senderId;
  final int receiverId;
  final String messageText;
  final String messageDate;
  final int isRead;
  final String? contextType;
  final int? contextId;
  final String? contextName;
  final String? contextImage;
  final double? contextPrice;
  final String messageType;
  final String? mediaUrl;
  final int? mediaDurationMs;
  final String? editedAt;
  final String? replyToId;
  final String? replyText;
  final String? replyType;

  MessageModel({
    this.documentId,
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    required this.messageDate,
    this.isRead = 0,
    this.contextType,
    this.contextId,
    this.contextName,
    this.contextImage,
    this.contextPrice,
    this.messageType = 'text',
    this.mediaUrl,
    this.mediaDurationMs,
    this.editedAt,
    this.replyToId,
    this.replyText,
    this.replyType,
  });

  String get previewText {
    if (messageText.trim().isNotEmpty) return messageText;
    switch (messageType) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice message';
      default:
        return 'Message';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': messageText,
      'message_date': messageDate,
      'is_read': isRead,
      'context_type': contextType,
      'context_id': contextId,
      'context_name': contextName,
      'context_image': contextImage,
      'context_price': contextPrice,
      'message_type': messageType,
      'media_url': mediaUrl,
      'media_duration_ms': mediaDurationMs,
      'edited_at': editedAt,
      'reply_to_id': replyToId,
      'reply_text': replyText,
      'reply_type': replyType,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      documentId: map['id']?.toString(),
      senderId: (map['sender_id'] as num).toInt(),
      receiverId: (map['receiver_id'] as num).toInt(),
      messageText: map['message_text'] as String? ?? '',
      messageDate: map['message_date'] as String? ?? '',
      isRead: map['is_read'] == true ? 1 : 0,
      contextType: map['context_type'] as String?,
      contextId: map['context_id'] as int?,
      contextName: map['context_name'] as String?,
      contextImage: map['context_image'] as String?,
      contextPrice: (map['context_price'] as num?)?.toDouble(),
      messageType: map['message_type'] as String? ?? 'text',
      mediaUrl: map['media_url'] as String?,
      mediaDurationMs: (map['media_duration_ms'] as num?)?.toInt(),
      editedAt: map['edited_at'] as String?,
      replyToId: map['reply_to_id'] as String?,
      replyText: map['reply_text'] as String?,
      replyType: map['reply_type'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'messageText': messageText,
      'messageDate': messageDate,
      'isRead': isRead == 1,
      'contextType': contextType,
      'contextId': contextId,
      'contextName': contextName,
      'contextImage': contextImage,
      'contextPrice': contextPrice,
      'messageType': messageType,
      'mediaUrl': mediaUrl,
      'mediaDurationMs': mediaDurationMs,
      'editedAt': editedAt,
      'replyToId': replyToId,
      'replyText': replyText,
      'replyType': replyType,
    };
  }

  factory MessageModel.fromFirestoreMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    return MessageModel(
      documentId: documentId,
      senderId: (map['senderId'] as num).toInt(),
      receiverId: (map['receiverId'] as num).toInt(),
      messageText: map['messageText'] as String? ?? '',
      messageDate: map['messageDate'] as String? ?? '',
      isRead: (map['isRead'] as bool? ?? false) ? 1 : 0,
      contextType: map['contextType'] as String?,
      contextId: (map['contextId'] as num?)?.toInt(),
      contextName: map['contextName'] as String?,
      contextImage: map['contextImage'] as String?,
      contextPrice: (map['contextPrice'] as num?)?.toDouble(),
      messageType: map['messageType'] as String? ?? 'text',
      mediaUrl: map['mediaUrl'] as String?,
      mediaDurationMs: (map['mediaDurationMs'] as num?)?.toInt(),
      editedAt: map['editedAt'] as String?,
      replyToId: map['replyToId'] as String?,
      replyText: map['replyText'] as String?,
      replyType: map['replyType'] as String?,
    );
  }
}
