import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/address_model.dart';
import '../models/cart_item_model.dart';

class OrderFunctionsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// [flashSaleIds] maps product ids to the flash sale the customer was
  /// shown, so checkout is blocked rather than charging a higher price if
  /// that sale has ended, sold out, or the customer's limit is reached.
  Future<int> placeOrder({
    required List<CartItemModel> items,
    required Map<int, String> voucherIds,
    required String paymentMethod,
    required AddressModel deliveryAddress,
    Map<int, int> flashSaleIds = const {},
  }) async {
    final Object? result;
    try {
      result = await _supabase.rpc(
        'place_order',
        params: {
          'payload': {
            'items': [
              for (final item in items)
                {
                  'product_id': item.productId,
                  'quantity': item.quantity,
                  'option_id': item.optionId,
                  if (flashSaleIds[item.productId] != null)
                    'flash_sale_id': flashSaleIds[item.productId],
                },
            ],
            'voucher_ids': {
              for (final entry in voucherIds.entries)
                '${entry.key}': entry.value,
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
    } on PostgrestException catch (error) {
      // Checkout errors (stock, vouchers, flash sale limits) are written for
      // customers, so pass them through.
      throw StateError(error.message);
    }
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
