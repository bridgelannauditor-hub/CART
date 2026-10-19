import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls [onChange] shortly after any order the signed-in user can see is
/// created or updated, so an order list reflects a status change (such as
/// "Delivered") without the user having to pull to refresh.
///
/// Database changes are filtered by row-level security, so a user is only
/// notified about their own orders.
class OrdersLiveRefresh {
  OrdersLiveRefresh({required this.name, required this.onChange});

  final String name;
  final void Function() onChange;

  RealtimeChannel? _channel;
  Timer? _debounce;

  void start() {
    if (_channel != null) return;
    _channel = Supabase.instance.client
        .channel(name)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 600), onChange);
          },
        )
        .subscribe();
  }

  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
  }
}
