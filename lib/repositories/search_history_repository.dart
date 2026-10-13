import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_service.dart';

class SearchHistoryRepository {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<String>> getRecentSearches() async {
    final userId = SessionService.userId;
    if (userId == null) return [];

    final rows = await _supabase
        .from('search_history')
        .select('query')
        .eq('user_id', userId)
        .order('searched_at', ascending: false)
        .limit(10);
    return rows
        .map((row) => (row['query'] as String? ?? '').trim())
        .where((query) => query.isNotEmpty)
        .toList();
  }

  Future<void> saveRecentSearches(List<String> searches) async {
    final userId = SessionService.userId;
    if (userId == null) return;

    final normalized = <String>[];
    for (final value in searches) {
      final query = value.trim();
      if (query.isNotEmpty && !normalized.contains(query)) {
        normalized.add(query);
      }
      if (normalized.length == 10) break;
    }

    await _supabase.from('search_history').delete().eq('user_id', userId);
    if (normalized.isEmpty) return;

    final now = DateTime.now().toUtc();
    await _supabase.from('search_history').insert([
      for (var index = 0; index < normalized.length; index++)
        {
          'user_id': userId,
          'query': normalized[index],
          'searched_at': now
              .subtract(Duration(milliseconds: index))
              .toIso8601String(),
        },
    ]);
  }
}
