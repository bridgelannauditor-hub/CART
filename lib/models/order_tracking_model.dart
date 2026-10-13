class TrackingEventModel {
  final String status;
  final String location;
  final String date;

  const TrackingEventModel({
    required this.status,
    required this.location,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'status': status,
    'location': location,
    'date': date,
  };

  factory TrackingEventModel.fromMap(Map<String, dynamic> map) {
    return TrackingEventModel(
      status: map['status'] as String? ?? 'Pending',
      location: map['location'] as String? ?? '',
      date: map['date'] as String? ?? '',
    );
  }
}

class OrderTrackingModel {
  final int orderId;
  final String status;
  final String courier;
  final String trackingNumber;
  final String estimatedDeliveryDate;
  final String currentLocation;
  final String lastUpdated;
  final List<TrackingEventModel> history;

  const OrderTrackingModel({
    required this.orderId,
    required this.status,
    this.courier = '',
    this.trackingNumber = '',
    this.estimatedDeliveryDate = '',
    this.currentLocation = '',
    this.lastUpdated = '',
    this.history = const [],
  });

  factory OrderTrackingModel.fromOrderMap(
    Map<String, dynamic> map, {
    int? sellerId,
  }) {
    final sellerFulfillment = map['sellerFulfillment'] is Map
        ? Map<String, dynamic>.from(map['sellerFulfillment'] as Map)
        : const <String, dynamic>{};
    final sellerRecord =
        sellerId != null && sellerFulfillment['$sellerId'] is Map
        ? Map<String, dynamic>.from(sellerFulfillment['$sellerId'] as Map)
        : const <String, dynamic>{};
    final trackingSource = sellerRecord['tracking'] ?? map['tracking'];
    final tracking = trackingSource is Map
        ? Map<String, dynamic>.from(trackingSource)
        : <String, dynamic>{};
    return OrderTrackingModel(
      orderId: (map['id'] as num).toInt(),
      status:
          sellerRecord['status'] as String? ??
          map['status'] as String? ??
          'Pending',
      courier: tracking['courier'] as String? ?? '',
      trackingNumber: tracking['trackingNumber'] as String? ?? '',
      estimatedDeliveryDate: tracking['estimatedDeliveryDate'] as String? ?? '',
      currentLocation: tracking['currentLocation'] as String? ?? '',
      lastUpdated: tracking['lastUpdated'] as String? ?? '',
      history: ((tracking['history'] as List?) ?? [])
          .map(
            (item) => TrackingEventModel.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
