import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/customer/chat_screen.dart';
import '../screens/customer/notifications_screen.dart';
import '../utils/routes.dart';
import 'session_service.dart';

/// Phone push notifications through Firebase Cloud Messaging.
///
/// The database sends a push for a new chat message and for every order,
/// order update or account notice (see supabase/functions/send-push). This
/// service asks the user for permission, registers the phone's push address
/// for the signed-in account, shows pushes that arrive while the app is open,
/// and opens the right screen when a notification is tapped.
///
/// Everything here fails quietly: a build without google-services.json, a
/// denied permission or a network error simply leaves push turned off.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channel = AndroidNotificationChannel(
    'cart_default',
    'C+ART notifications',
    description: 'Messages, orders and account notices',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _ready = false;
  // True once the app's own start-up navigation (splash -> home/dashboard)
  // has finished. A tap that launched the app waits for this so the start-up
  // navigation does not replace the screen the tap opened.
  bool _appReady = false;
  String? _registeredToken;
  Map<String, dynamic>? _pendingTap;
  StreamSubscription<String>? _refreshSubscription;

  /// Call once at startup.
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            _handleTap(Map<String, dynamic>.from(jsonDecode(payload) as Map));
          } catch (_) {}
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleTap(message.data),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTap(initial.data);
      _ready = true;
    } catch (error) {
      debugPrint('Push notifications are off: $error');
    }
  }

  /// Asks for permission and registers this phone for the signed-in user.
  /// Safe to call repeatedly (every sign-in and every app start).
  Future<void> registerForCurrentUser() async {
    if (!_ready || !SessionService.isLoggedIn) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // getToken/onTokenRefresh are marked deprecated in favour of the new
      // Firebase Installation ID flow, but they still return the classic
      // registration token that the FCM HTTP v1 send API addresses.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _register(token);
      // ignore: deprecated_member_use
      _refreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (fresh) {
          if (SessionService.isLoggedIn) unawaited(_register(fresh));
        },
      );
    } catch (error) {
      debugPrint('Could not register for push: $error');
    }
  }

  Future<void> _register(String token) async {
    await Supabase.instance.client.rpc(
      'register_push_token',
      params: {'push_token': token, 'push_platform': 'android'},
    );
    _registeredToken = token;
  }

  /// Stops this phone receiving the signed-out user's notifications. Call
  /// before signing out, while the session is still valid.
  Future<void> unregister() async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'unregister_push_token',
        params: {'push_token': token},
      );
    } catch (_) {}
    _registeredToken = null;
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Opens the screen a notification is about. If the app was just launched
  /// by the tap, waits until the user's session has been restored.
  void _handleTap(Map<String, dynamic> data) {
    _pendingTap = data;
    unawaited(_openWhenReady());
  }

  /// Called when start-up navigation is done (see the splash screen).
  void markAppReady() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      _appReady = true;
      if (_pendingTap != null) unawaited(_openWhenReady());
    });
  }

  Future<void> _openWhenReady() async {
    for (var i = 0; i < 50; i++) {
      final navigator = _navigatorKey?.currentState;
      if (_appReady && navigator != null && SessionService.isLoggedIn) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final navigator = _navigatorKey?.currentState;
    final data = _pendingTap;
    _pendingTap = null;
    if (navigator == null || data == null || !SessionService.isLoggedIn) return;

    final type = '${data['type'] ?? ''}';
    final related = int.tryParse('${data['related_id'] ?? ''}');
    if (type == 'message' && related != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            otherUserId: related,
            otherUserName: '${data['sender_name'] ?? 'Chat'}',
          ),
        ),
      );
    } else if (type == 'order') {
      navigator.pushNamed(
        SessionService.isSeller ? AppRoutes.sellerOrders : AppRoutes.orders,
      );
    } else if (type == 'order_status') {
      navigator.pushNamed(AppRoutes.orders);
    } else {
      navigator.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }
  }
}
