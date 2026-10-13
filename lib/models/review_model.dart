import '../database/tables.dart';

class ReviewModel {
  final int? id;
  final int productId;
  final int customerId;
  final double rating;
  final String? comment;
  final String createdAt;
  final String customerFirstName;
  final String customerLastName;

  ReviewModel({
    this.id,
    required this.productId,
    required this.customerId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.customerFirstName = '',
    this.customerLastName = '',
  });

  String get customerName {
    final full = "$customerFirstName $customerLastName".trim();
    return full.isEmpty ? "Customer" : full;
  }

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.productId: productId,
      DBTables.customerId: customerId,
      DBTables.rating: rating,
      DBTables.reviewComment: comment,
      DBTables.createdAt: createdAt,
    };
  }

  factory ReviewModel.fromMap(Map<String, dynamic> map) {
    return ReviewModel(
      id: map[DBTables.id],
      productId: map['product_id'] ?? map[DBTables.productId],
      customerId: map['customer_id'] ?? map[DBTables.customerId],
      rating: (map[DBTables.rating] as num).toDouble(),
      comment: map['comment'] ?? map[DBTables.reviewComment],
      createdAt: map['created_at'] ?? map[DBTables.createdAt] ?? '',
      customerFirstName: map['customer_first_name'] ?? '',
      customerLastName: map['customer_last_name'] ?? '',
    );
  }

  // ==========================
  // FIRESTORE MAP
  // ==========================

  Map<String, dynamic> toFirestoreMap() {
    return {
      'productId': productId,
      'customerId': customerId,
      'customerFirstName': customerFirstName,
      'customerLastName': customerLastName,
      'rating': rating,
      'comment': comment,
      'createdAt': createdAt,
    };
  }

  factory ReviewModel.fromFirestoreMap(Map<String, dynamic> map) {
    return ReviewModel(
      productId: map['productId'] as int,
      customerId: map['customerId'] as int,
      rating: (map['rating'] as num).toDouble(),
      comment: map['comment'] as String?,
      createdAt: map['createdAt'] ?? '',
      customerFirstName: map['customerFirstName'] ?? '',
      customerLastName: map['customerLastName'] ?? '',
    );
  }
}
