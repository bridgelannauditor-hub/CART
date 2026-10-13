import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/review_model.dart';
import 'product_repository.dart';

class ReviewPage {
  final List<ReviewModel> items;
  final String? cursor;
  final bool hasMore;

  const ReviewPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class ReviewRepository {
  SupabaseClient get _supabase => Supabase.instance.client;
  final ProductRepository _productRepository = ProductRepository();

  Future<ReviewModel?> getMyReview(int productId, int customerId) async {
    final row = await _supabase
        .from('reviews')
        .select()
        .eq('product_id', productId)
        .eq('customer_id', customerId)
        .maybeSingle();
    return row == null ? null : ReviewModel.fromMap(row);
  }

  Future<void> submitReview({
    required int productId,
    required int customerId,
    required double rating,
    String? comment,
  }) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Must be between 1 and 5.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('first_name,last_name')
        .eq('id', customerId)
        .single();
    await _supabase.from('reviews').upsert({
      'product_id': productId,
      'customer_id': customerId,
      'rating': rating,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'customer_first_name': profile['first_name'] ?? '',
      'customer_last_name': profile['last_name'] ?? '',
    }, onConflict: 'product_id,customer_id');
  }

  Future<ReviewPage> getReviewsPage(
    int productId, {
    String? after,
    int pageSize = 20,
  }) async {
    var query = _supabase.from('reviews').select().eq('product_id', productId);
    if (after != null) query = query.lt('created_at', after);
    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize + 1);
    final pageRows = rows.take(pageSize).toList();

    return ReviewPage(
      items: pageRows.map(ReviewModel.fromMap).toList(),
      cursor: pageRows.isEmpty ? after : pageRows.last['created_at'] as String?,
      hasMore: rows.length > pageSize,
    );
  }

  Future<({double average, int count})> getRatingSummary(int productId) async {
    final product = await _productRepository.getProductById(productId);
    return (average: product?.rating ?? 0, count: product?.reviewCount ?? 0);
  }
}
