import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation_model.dart';
import '../models/message_model.dart';
import 'user_repository.dart';

class ConversationPage {
  final List<ConversationModel> items;
  final String? cursor;
  final bool hasMore;

  const ConversationPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class MessageRepository {
  SupabaseClient get _supabase => Supabase.instance.client;
  final UserRepository _userRepository = UserRepository();

  Future<String> _conversationId(int userA, int userB) async {
    final participants = [userA, userB]..sort();
    final existing = await _supabase
        .from('conversations')
        .select('id')
        .contains('participant_ids', participants)
        .limit(1)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final created = await _supabase
        .from('conversations')
        .insert({'participant_ids': participants})
        .select('id')
        .single();
    return created['id'] as String;
  }

  Future<String?> _existingConversationId(int userA, int userB) async {
    final participants = [userA, userB]..sort();
    final row = await _supabase
        .from('conversations')
        .select('id')
        .contains('participant_ids', participants)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<void> sendMessage({
    required int senderId,
    required int receiverId,
    required String text,
    String? contextType,
    int? contextId,
    String? contextName,
    String? contextImage,
    double? contextPrice,
    String messageType = 'text',
    String? mediaUrl,
    int? mediaDurationMs,
    String? replyToId,
    String? replyText,
    String? replyType,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) return;

    final conversationId = await _conversationId(senderId, receiverId);
    final messageDate = DateTime.now().toUtc().toIso8601String();
    final row = {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': cleanText,
      'message_date': messageDate,
      'context_type': contextType,
      'context_id': contextId,
      'context_name': contextName,
      'context_image': contextImage,
      'context_price': contextPrice,
      'message_type': messageType,
      'media_url': mediaUrl,
      'media_duration_ms': mediaDurationMs,
      'reply_to_id': replyToId,
      'reply_text': replyText,
      'reply_type': replyType,
    };
    await _supabase.from('messages').insert(row);

    final preview = MessageModel.fromMap({...row, 'id': null}).previewText;
    await _supabase
        .from('conversations')
        .update({'last_message': preview, 'last_message_date': messageDate})
        .eq('id', conversationId);
  }

  Future<List<MessageModel>> getConversation(int userA, int userB) async {
    final conversationId = await _existingConversationId(userA, userB);
    if (conversationId == null) return [];
    final rows = await _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('message_date');
    return rows.map(MessageModel.fromMap).toList();
  }

  Stream<List<MessageModel>> watchConversation(int userA, int userB) {
    return Stream.fromFuture(_conversationId(userA, userB)).asyncExpand(
      (conversationId) => _supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('message_date')
          .map((rows) => rows.map(MessageModel.fromMap).toList()),
    );
  }

  Future<void> editMessage({
    required int userA,
    required int userB,
    required MessageModel message,
    required String text,
  }) async {
    final messageId = message.documentId;
    final cleanText = text.trim();
    if (messageId == null || cleanText.isEmpty || message.senderId != userA) {
      return;
    }
    final editedAt = DateTime.now().toUtc().toIso8601String();
    await _supabase
        .from('messages')
        .update({'message_text': cleanText, 'edited_at': editedAt})
        .eq('id', messageId)
        .eq('sender_id', userA);

    final conversationId = await _existingConversationId(userA, userB);
    if (conversationId != null) {
      await _supabase
          .from('conversations')
          .update({'last_message': cleanText})
          .eq('id', conversationId)
          .eq('last_message_date', message.messageDate);
    }
  }

  Future<void> deleteMessage({
    required int userA,
    required int userB,
    required String messageId,
  }) async {
    final conversationId = await _existingConversationId(userA, userB);
    if (conversationId == null) return;
    await _supabase
        .from('messages')
        .delete()
        .eq('id', messageId)
        .eq('sender_id', userA);

    final latest = await _supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('message_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (latest == null) {
      await _supabase.from('conversations').delete().eq('id', conversationId);
      return;
    }
    final message = MessageModel.fromMap(latest);
    await _supabase
        .from('conversations')
        .update({
          'last_message': message.previewText,
          'last_message_date': message.messageDate,
        })
        .eq('id', conversationId);
  }

  Future<void> markConversationRead({
    required int currentUserId,
    required int otherUserId,
  }) async {
    final conversationId = await _existingConversationId(
      currentUserId,
      otherUserId,
    );
    if (conversationId == null) return;
    await _supabase
        .from('messages')
        .update({'is_read': true})
        .eq('conversation_id', conversationId)
        .eq('receiver_id', currentUserId)
        .eq('is_read', false);
  }

  Future<ConversationPage> getConversationsPage(
    int userId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase.from('conversations').select().contains(
      'participant_ids',
      [userId],
    );
    if (after != null) query = query.lt('last_message_date', after);
    final rows = await query
        .order('last_message_date', ascending: false)
        .limit(pageSize + 1);
    return _conversationPage(rows, userId, pageSize, after);
  }

  Stream<ConversationPage> watchConversationPage(
    int userId, {
    int pageSize = 20,
  }) {
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final filtered =
              rows.where((row) {
                final ids = (row['participant_ids'] as List?) ?? const [];
                return ids.any((id) => (id as num).toInt() == userId);
              }).toList()..sort(
                (a, b) => (b['last_message_date'] as String? ?? '').compareTo(
                  a['last_message_date'] as String? ?? '',
                ),
              );
          return filtered.take(pageSize + 1).toList();
        })
        .asyncMap((rows) => _conversationPage(rows, userId, pageSize, null));
  }

  Future<ConversationPage> _conversationPage(
    List<Map<String, dynamic>> rows,
    int userId,
    int pageSize,
    String? previousCursor,
  ) async {
    final pageRows = rows.take(pageSize).toList();
    final otherIds = pageRows
        .map((row) => _otherParticipant(row, userId))
        .whereType<int>()
        .toSet();
    final users = await _userRepository.getUsersByIds(otherIds);
    final usersById = {for (final user in users) user.id: user};
    final conversations = <ConversationModel>[];

    for (final row in pageRows) {
      final otherId = _otherParticipant(row, userId);
      if (otherId == null) continue;
      final otherUser = usersById[otherId];
      final fullName = otherUser == null
          ? ''
          : '${otherUser.firstName} ${otherUser.lastName}'.trim();
      final shopName = otherUser?.shopName?.trim() ?? '';
      final unreadRows = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', row['id'])
          .eq('receiver_id', userId)
          .eq('is_read', false);
      conversations.add(
        ConversationModel(
          otherUserId: otherId,
          otherUserName: shopName.isNotEmpty
              ? shopName
              : (fullName.isNotEmpty ? fullName : 'User $otherId'),
          otherUserProfileImage: otherUser?.profileImage,
          lastMessage: MessageModel(
            senderId: otherId,
            receiverId: userId,
            messageText: row['last_message'] as String? ?? '',
            messageDate: row['last_message_date'] as String? ?? '',
          ),
          unreadCount: unreadRows.length,
        ),
      );
    }

    return ConversationPage(
      items: conversations,
      cursor: pageRows.isEmpty
          ? previousCursor
          : pageRows.last['last_message_date'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<int> getUnreadCount(int userId) async {
    final rows = await _supabase
        .from('messages')
        .select('id')
        .eq('receiver_id', userId)
        .eq('is_read', false);
    return rows.length;
  }

  Stream<int> watchUnreadCount(int userId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .map((rows) => rows.where((row) => row['is_read'] != true).length);
  }

  int? _otherParticipant(Map<String, dynamic> row, int userId) {
    final participants = (row['participant_ids'] as List?)?.map(
      (id) => (id as num).toInt(),
    );
    if (participants == null) return null;
    for (final participant in participants) {
      if (participant != userId) return participant;
    }
    return null;
  }
}
