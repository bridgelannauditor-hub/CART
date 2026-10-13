import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../constants/app_colors.dart';
import '../../repositories/shop_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/live_repository.dart';
import '../../repositories/notification_repository.dart';
import '../../models/product_model.dart';
import '../../services/agora_config.dart';
import '../../services/session_service.dart';
import '../../widgets/seller_bottom_navbar.dart';
import '../../widgets/product_image.dart';

/// Lets a seller start or stop a live session for their shop.
///
/// Going live now does two things:
///  1. publishes the seller's camera + microphone to the Agora channel, and
///  2. flags the shop as live in Firestore (and the local db), so the
///     Watch tab and the red "live" ring on the Messages screen show it.
///
/// The shop is only flagged live AFTER Agora confirms the join, so
/// viewers never see a "live" shop with no stream behind it. Leaving
/// this screen while live ends the stream.
///
/// NOTE: this uses the single test channel from AgoraConfig for now —
/// see the note in that file for what production wiring still needs.
class SellerLiveScreen extends StatefulWidget {
  const SellerLiveScreen({super.key});

  @override
  State<SellerLiveScreen> createState() => _SellerLiveScreenState();
}

class _SellerLiveScreenState extends State<SellerLiveScreen> {
  final ShopRepository _shopRepository = ShopRepository();
  final ProductRepository _productRepository = ProductRepository();
  final LiveRepository _liveRepository = LiveRepository();
  final NotificationRepository _notifications = NotificationRepository();
  final TextEditingController _commentController = TextEditingController();
  List<ProductModel> _products = [];
  int? _pinnedProductId;
  bool _commentsEnabled = true;
  int _viewerCount = 0;
  String? _broadcastId;

  RtcEngine? _engine;
  Timer? _joinTimeout;

  bool _isStarting = false;
  bool _isLive = false;
  bool _isEnding = false;

  late final Future<void> _initialClear;

  @override
  void initState() {
    super.initState();
    _initialClear = _clearStaleLiveFlag();
    _loadProducts();
  }

  @override
  void dispose() {
    _joinTimeout?.cancel();
    _commentController.dispose();

    final userId = SessionService.userId;
    final wasLive = _isLive || _isStarting;

    _teardownEngine();

    if (userId != null && wasLive) {
      _liveRepository.endSession(userId).catchError((_) {});
      _shopRepository
          .setLiveStatus(userId, false, firebaseUid: SessionService.firebaseUid)
          .catchError(
            (Object e) => debugPrint("Clearing live flag failed: $e"),
          );
    }

    super.dispose();
  }

  Future<void> _loadProducts() async {
    final sellerId = SessionService.userId;
    if (sellerId == null) return;
    try {
      final products = await _productRepository.getProductsBySeller(sellerId);
      if (mounted) setState(() => _products = products);
    } catch (_) {}
  }

  /// A stream can't survive the app being killed, so a shop still flagged
  /// live from a previous session is stale. Clear it on entry.
  Future<void> _clearStaleLiveFlag() async {
    final userId = SessionService.userId;
    if (userId == null) return;

    try {
      await _shopRepository.setLiveStatus(
        userId,
        false,
        firebaseUid: SessionService.firebaseUid,
      );
    } catch (e) {
      debugPrint("Clearing stale live flag failed: $e");
    }
  }

  // ==========================
  // START
  // ==========================

  Future<void> _startLive() async {
    if (_isStarting || _isLive) return;

    final userId = SessionService.userId;
    if (userId == null) return;

    if (!AgoraConfig.hasToken) {
      _showSnack(
        "Add a fresh Agora temp token in agora_config.dart before going live.",
      );
      return;
    }

    setState(() => _isStarting = true);

    // Make sure the stale-flag cleanup can't land after our "live" write.
    await _initialClear;

    final statuses = await [Permission.camera, Permission.microphone].request();
    final cameraOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    if (!mounted) return;

    if (!cameraOk || !micOk) {
      await _fail(
        "Camera and microphone access are needed to go live. "
        "You can allow them in your phone's app settings.",
      );
      return;
    }

    final engine = createAgoraRtcEngine();

    try {
      await engine.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      if (!mounted) {
        await engine.release();
        return;
      }

      _engine = engine;

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            _onJoined(userId);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _viewerCount++);
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) {
              setState(
                () => _viewerCount = (_viewerCount - 1).clamp(0, 999999),
              );
            }
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint("Agora connection: $state ($reason)");
            if (state == ConnectionStateType.connectionStateFailed) {
              _fail(_describeFailure(reason));
            }
          },
          onError: (err, msg) {
            // Many Agora errors are recoverable, so only log them here.
            debugPrint("Agora error: $err $msg");
          },
        ),
      );

      await engine.enableVideo();
      await engine.enableAudio();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.startPreview();

      await engine.joinChannel(
        token: AgoraConfig.testToken,
        channelId: AgoraConfig.testChannelName,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      // If Agora never confirms the join, don't leave the button spinning.
      _joinTimeout = Timer(const Duration(seconds: 15), () {
        if (_isStarting) {
          _fail(
            "Couldn't start the stream. Check your connection and try again.",
          );
        }
      });
    } catch (e) {
      debugPrint("Agora start failed: $e");
      await _fail("Couldn't start the stream. Please try again.");
    }
  }

  /// Agora confirmed we're in the channel: now flag the shop as live.
  Future<void> _onJoined(int userId) async {
    _joinTimeout?.cancel();
    if (!mounted || _isLive) return;

    try {
      await _shopRepository.setLiveStatus(
        userId,
        true,
        firebaseUid: SessionService.firebaseUid,
      );
      final shop = await _shopRepository.getShop(userId);
      final shopName = (shop?.shopName?.trim().isNotEmpty ?? false)
          ? shop!.shopName!.trim()
          : '${SessionService.firstName ?? ''} ${SessionService.lastName ?? ''}'
                .trim();
      _broadcastId = await _liveRepository.startSession(
        sellerId: userId,
        shopName: shopName.isEmpty ? 'A shop' : shopName,
        productIds: _products
            .map((product) => product.id)
            .whereType<int>()
            .toList(),
      );
      unawaited(
        _notifications
            .notifyFollowersSellerLive(
              sellerId: userId,
              shopName: shopName.isEmpty ? 'A shop' : shopName,
            )
            .catchError((Object error) {
              debugPrint('LIVE follower notifications failed: $error');
            }),
      );
    } catch (e) {
      debugPrint("Marking shop live failed: $e");
      try {
        await _liveRepository.endSession(userId);
        await _shopRepository.setLiveStatus(
          userId,
          false,
          firebaseUid: SessionService.firebaseUid,
        );
      } catch (_) {}
      await _fail(
        "The stream started, but we couldn't mark your shop as live. "
        "Check your connection and try again.",
      );
      return;
    }

    // The seller left the screen while the write was in flight: dispose()
    // already tried to clear the flag, but our write may have landed after.
    if (!mounted) {
      _shopRepository
          .setLiveStatus(userId, false, firebaseUid: SessionService.firebaseUid)
          .catchError(
            (Object e) => debugPrint("Clearing live flag failed: $e"),
          );
      return;
    }

    setState(() {
      _isLive = true;
      _isStarting = false;
      _commentsEnabled = true;
      _pinnedProductId = null;
      _viewerCount = 0;
    });

    _showSnack("You're live! Followers can now watch your stream.");
  }

  // ==========================
  // END
  // ==========================

  Future<void> _endLive() async {
    if (_isEnding) return;

    setState(() => _isEnding = true);

    await _teardownEngine();

    final userId = SessionService.userId;
    if (userId != null) {
      try {
        await _liveRepository.endSession(userId);
        await _shopRepository.setLiveStatus(
          userId,
          false,
          firebaseUid: SessionService.firebaseUid,
        );
      } catch (e) {
        debugPrint("Clearing live flag failed: $e");
      }
    }

    if (!mounted) return;

    setState(() {
      _isLive = false;
      _isEnding = false;
      _pinnedProductId = null;
      _broadcastId = null;
      _viewerCount = 0;
    });

    _showSnack("You've ended your live session.");
  }

  ProductModel? get _pinnedProduct {
    for (final product in _products) {
      if (product.id == _pinnedProductId) return product;
    }
    return null;
  }

  Future<void> _selectPinnedProduct() async {
    final selection = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Text(
            'Pin a product',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_pinnedProductId != null)
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Unpin current product'),
              onTap: () => Navigator.pop(context, -1),
            ),
          for (final item in _products)
            ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: ProductImage(
                  path: item.image,
                  placeholder: const Icon(Icons.image_outlined),
                ),
              ),
              title: Text(item.productName),
              subtitle: Text(
                '₱${item.price.toStringAsFixed(2)} • ${item.stock} available',
              ),
              onTap: () => Navigator.pop(context, item.id),
            ),
        ],
      ),
    );
    if (!mounted || selection == null) return;
    final id = selection == -1 ? null : selection;
    await _liveRepository.pinProduct(SessionService.userId!, id);
    if (mounted) setState(() => _pinnedProductId = id);
  }

  Future<void> _toggleComments() async {
    final enabled = !_commentsEnabled;
    await _liveRepository.setCommentsEnabled(SessionService.userId!, enabled);
    if (mounted) setState(() => _commentsEnabled = enabled);
  }

  Future<void> _sendSellerComment() async {
    final text = _commentController.text;
    if (text.trim().isEmpty) return;
    try {
      await _liveRepository.sendMessage(
        userId: SessionService.userId!,
        senderName: SessionService.firstName ?? 'Seller',
        text: text,
        isSeller: true,
      );
      _commentController.clear();
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _moderateMessage(
    String messageId,
    Map<String, dynamic> message,
  ) async {
    final viewerId = (message['senderId'] as num?)?.toInt();
    if (viewerId == null || message['isSeller'] == true) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide comment'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.error),
              title: const Text('Block viewer'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
          ],
        ),
      ),
    );
    if (action == 'hide') {
      await _liveRepository.hideMessage(SessionService.userId!, messageId);
    }
    if (action == 'block') {
      await _liveRepository.blockViewer(SessionService.userId!, viewerId);
      await _liveRepository.hideMessage(SessionService.userId!, messageId);
    }
  }

  // ==========================
  // HELPERS
  // ==========================

  /// Something went wrong while starting: release everything and reset.
  Future<void> _fail(String message) async {
    _joinTimeout?.cancel();

    // The connection can also drop mid-stream (e.g. token expiry); in that
    // case the shop is already flagged live and must be cleared.
    final wasLive = _isLive;
    final userId = SessionService.userId;

    await _teardownEngine();

    if (wasLive && userId != null) {
      try {
        await _shopRepository.setLiveStatus(
          userId,
          false,
          firebaseUid: SessionService.firebaseUid,
        );
      } catch (e) {
        debugPrint("Clearing live flag failed: $e");
      }
    }

    if (!mounted) return;

    setState(() {
      _isStarting = false;
      _isLive = false;
    });

    _showSnack(message);
  }

  Future<void> _teardownEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;

    try {
      await engine.stopPreview();
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      debugPrint("Agora teardown failed: $e");
    }
  }

  String _describeFailure(ConnectionChangedReasonType reason) {
    if (reason == ConnectionChangedReasonType.connectionChangedInvalidToken ||
        reason == ConnectionChangedReasonType.connectionChangedTokenExpired) {
      return "The live-stream token is invalid or has expired. Generate a new "
          "temp token in the Agora Console and paste it into agora_config.dart.";
    }
    return "Couldn't connect to the live stream ($reason).";
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  // ==========================
  // UI
  // ==========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Go Live",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      bottomNavigationBar: const SellerBottomNavbar(currentIndex: 2),
      body: SafeArea(child: _isLive ? _buildLiveView() : _buildIdleView()),
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lightGrey.withValues(alpha: .5),
                border: Border.all(color: AppColors.lightGrey, width: 2.5),
              ),
              child: const Icon(
                Icons.podcasts,
                size: 56,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "You're not live",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Go live to stream your shop with your camera and mic. "
              "Followers will see a live ring around your shop.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isStarting ? null : _startLive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Start Live",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveView() {
    final engine = _engine;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: engine == null
                ? const SizedBox.shrink()
                : AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: engine,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "● LIVE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _LiveChip(
                icon: Icons.visibility_outlined,
                label: '$_viewerCount',
              ),
              const SizedBox(width: 8),
              StreamBuilder<Map<String, dynamic>?>(
                stream: _liveRepository.watchSession(),
                builder: (context, snapshot) => _LiveChip(
                  icon: Icons.favorite,
                  label: '${snapshot.data?['reactionCounts']?['heart'] ?? 0}',
                ),
              ),
            ],
          ),
        ),

        Positioned(
          top: 10,
          right: 8,
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Pin product',
                onPressed: _selectPinnedProduct,
                icon: const Icon(Icons.push_pin_outlined),
              ),
              IconButton.filledTonal(
                tooltip: _commentsEnabled
                    ? 'Pause comments'
                    : 'Resume comments',
                onPressed: _toggleComments,
                icon: Icon(
                  _commentsEnabled
                      ? Icons.chat_outlined
                      : Icons.comments_disabled_outlined,
                ),
              ),
            ],
          ),
        ),

        if (_pinnedProduct case final ProductModel product)
          Positioned(
            left: 12,
            right: 12,
            bottom: 310,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ProductImage(
                      path: product.image,
                      placeholder: const Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PINNED',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          product.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₱${product.price.toStringAsFixed(2)} • ${product.stock} available',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _selectPinnedProduct,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),

        Positioned(
          left: 12,
          right: 12,
          bottom: 82,
          child: Container(
            height: 215,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _liveRepository.watchMessages(),
                    builder: (context, snapshot) {
                      final docs = (snapshot.data ?? const [])
                          .where(
                            (data) =>
                                data['hidden'] != true &&
                                data['broadcastId'] == _broadcastId,
                          )
                          .toList();
                      return ListView.builder(
                        reverse: true,
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index];
                          return GestureDetector(
                            onLongPress: () =>
                                _moderateMessage(data['id'] as String, data),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${data['senderName'] ?? 'Viewer'}  ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: data['isSeller'] == true
                                            ? AppColors.secondary
                                            : Colors.white,
                                      ),
                                    ),
                                    TextSpan(text: data['text'] ?? ''),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.white),
                        maxLength: 300,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Reply to viewers…',
                          hintStyle: TextStyle(color: Colors.white70),
                        ),
                        onSubmitted: (_) => _sendSellerComment(),
                      ),
                    ),
                    IconButton(
                      onPressed: _sendSellerComment,
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isEnding ? null : _endLive,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lightGrey,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isEnding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Text(
                      "End Live",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LiveChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
