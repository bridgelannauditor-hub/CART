import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/address_model.dart';
import '../models/cart_item_model.dart';

class OrderFunctionsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<int> placeOrder({
    required List<CartItemModel> items,
    required Map<int, String> voucherIds,
    required String paymentMethod,
    required AddressModel deliveryAddress,
  }) async {
    final result = await _supabase.rpc(
      'place_order',
      params: {
        'payload': {
          'items': [
            for (final item in items)
              {
                'product_id': item.productId,
                'quantity': item.quantity,
                'option_id': item.optionId,
              },
          ],
          'voucher_ids': {
            for (final entry in voucherIds.entries) '${entry.key}': entry.value,
          },
          'payment_method': paymentMethod,
          'delivery_address': {
            'addressId': deliveryAddress.id,
            'fullName': deliveryAddress.fullName,
            'phone': deliveryAddress.phone,
            'label': deliveryAddress.label,
            'line1': deliveryAddress.line1,
            'line2': deliveryAddress.line2,
            'city': deliveryAddress.city,
            'province': deliveryAddress.province,
            'postalCode': deliveryAddress.postalCode,
          },
        },
      },
    );
    if (result is! num) {
      throw StateError('The server returned an invalid order.');
    }
    return result.toInt();
  }

  Future<void> cancelOrderItem({
    required int orderId,
    required int itemId,
  }) async {
    await _supabase.rpc(
      'cancel_order_item',
      params: {'target_order_id': orderId, 'target_item_id': itemId},
    );
  }

  Future<void> updateSellerOrder({
    required int orderId,
    required String status,
    String courier = '',
    String trackingNumber = '',
    String estimatedDeliveryDate = '',
    String currentLocation = '',
  }) async {
    await _supabase.rpc(
      'update_seller_order',
      params: {
        'target_order_id': orderId,
        'new_status': status,
        'tracking_data': {
          'courier': courier,
          'trackingNumber': trackingNumber,
          'estimatedDeliveryDate': estimatedDeliveryDate,
          'currentLocation': currentLocation,
        },
      },
    );
  }
}
