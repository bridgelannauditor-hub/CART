import 'package:supabase_flutter/supabase_flutter.dart';

class LiveRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Stream<Map<String, dynamic>?> watchSession() {
    return _supabase.from('live_sessions').stream(primaryKey: ['id']).map((
      rows,
    ) {
      if (rows.isEmpty) return null;
      rows.sort(
        (a, b) => (b['created_at'] as String? ?? '').compareTo(
          a['created_at'] as String? ?? '',
        ),
      );
      return _sessionMap(rows.first);
    });
  }

  Stream<List<Map<String, dynamic>>> watchMessages() {
    return _supabase
        .from('live_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50)
        .asyncMap(_enrichMessages);
  }

  Future<Map<String, dynamic>?> _activeSession() async {
    return _supabase
        .from('live_sessions')
        .select()
        .eq('is_live', true)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<String> startSession({
    required int sellerId,
    required String shopName,
    required List<int> productIds,
  }) async {
    final broadcastId = '${sellerId}_${DateTime.now().millisecondsSinceEpoch}';
    await _supabase.from('live_sessions').insert({
      'broadcast_id': broadcastId,
      'seller_id': sellerId,
      'title': shopName,
      'is_live': true,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'product_ids': productIds,
      'comments_enabled': true,
      'reaction_counts': {'heart': 0},
    });
    return broadcastId;
  }

  Future<void> endSession(int sellerId) async {
    await _supabase
        .from('live_sessions')
        .update({
          'is_live': false,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'pinned_product_id': null,
        })
        .eq('seller_id', sellerId)
        .eq('is_live', true);
  }

  Future<void> pinProduct(int sellerId, int? productId) async {
    await _supabase
        .from('live_sessions')
        .update({'pinned_product_id': productId})
        .eq('seller_id', sellerId)
        .eq('is_live', true);
  }

  Future<void> setCommentsEnabled(int sellerId, bool enabled) async {
    await _supabase
        .from('live_sessions')
        .update({'comments_enabled': enabled})
        .eq('seller_id', sellerId)
        .eq('is_live', true);
  }

  Future<void> sendMessage({
    required int userId,
    required String senderName,
    required String text,
    required bool isSeller,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Comments must be between 1 and 300 characters.');
    }
    await _supabase.rpc('send_live_message', params: {'message_text': clean});
  }

  Future<void> addHeart(int userId) async {
    if (userId <= 0) return;
    await _supabase.rpc('add_live_heart');
  }

  Future<void> hideMessage(int sellerId, String messageId) async {
    await _supabase.rpc('hide_live_message', params: {'message_id': messageId});
  }

  Future<void> blockViewer(int sellerId, int viewerId) async {
    final active = await _activeSession();
    if (active == null || (active['seller_id'] as num).toInt() != sellerId) {
      throw StateError('This viewer cannot be blocked.');
    }
    await _supabase.from('live_blocked_users').upsert({
      'session_id': active['id'],
      'user_id': viewerId,
    });
  }

  Map<String, dynamic> _sessionMap(Map<String, dynamic> row) => {
    'id': row['id'],
    'broadcastId': row['broadcast_id'],
    'sellerId': (row['seller_id'] as num).toInt(),
    'shopName': row['title'],
    'active': row['is_live'],
    'startedAt': row['started_at'],
    'endedAt': row['ended_at'],
    'featuredProductIds': row['product_ids'],
    'pinnedProductId': (row['pinned_product_id'] as num?)?.toInt(),
    'commentsEnabled': row['comments_enabled'],
    'reactionCounts': row['reaction_counts'],
  };

  Future<List<Map<String, dynamic>>> _enrichMessages(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final sessionIds = rows.map((row) => row['session_id'] as String).toSet();
    final senderIds = rows
        .map((row) => (row['sender_id'] as num).toInt())
        .toSet();
    final sessions = await _supabase
        .from('live_sessions')
        .select('id,broadcast_id,seller_id')
        .inFilter('id', sessionIds.toList());
    final profiles = await _supabase
        .from('profiles')
        .select('id,first_name,last_name,shop_name')
        .inFilter('id', senderIds.toList());
    final sessionById = {for (final row in sessions) row['id']: row};
    final profileById = {
      for (final row in profiles) (row['id'] as num).toInt(): row,
    };
    return [
      for (final row in rows)
        () {
          final senderId = (row['sender_id'] as num).toInt();
          final session = sessionById[row['session_id']];
          final profile = profileById[senderId];
          final name = profile == null
              ? 'Someone'
              : (profile['shop_name'] as String?)?.trim().isNotEmpty == true
              ? profile['shop_name'] as String
              : '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                    .trim();
          return {
            'id': row['id'],
            'senderId': senderId,
            'broadcastId': session?['broadcast_id'],
            'senderName': name,
            'text': row['text'],
            'isSeller': session?['seller_id'] == senderId,
            'hidden': row['hidden'],
            'createdAt': row['created_at'],
          };
        }(),
    ];
  }
}
