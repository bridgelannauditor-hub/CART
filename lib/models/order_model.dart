import '../database/tables.dart';

class OrderModel {
  final int? id;
  final int customerId;
  final double total;
  final String status;
  final String orderDate;

  OrderModel({
    this.id,
    required this.customerId,
    required this.total,
    this.status = "Pending",
    required this.orderDate,
  });

  Map<String, dynamic> toMap() {
    return {
      DBTables.id: id,
      DBTables.customerId: customerId,
      DBTables.total: total,
      DBTables.status: status,
      DBTables.orderDate: orderDate,
    };
  }

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map[DBTables.id],
      customerId: map[DBTables.customerId],
      total: (map[DBTables.total] as num).toDouble(),
      status: map[DBTables.status] ?? 'Pending',
      orderDate: map[DBTables.orderDate] ?? '',
    );
  }
}
