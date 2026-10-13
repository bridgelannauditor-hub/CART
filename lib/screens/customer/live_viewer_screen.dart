import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../repositories/live_repository.dart';
import '../../repositories/product_repository.dart';
import '../../services/agora_config.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';
import 'product_details_screen.dart';

/// Lets a customer watch a seller's live stream and chat in real time.
///
/// NOTE: like SellerLiveScreen, this joins the single hardcoded test
/// channel from AgoraConfig for now, not a per-seller channel — see the
/// note in that file for what production wiring still needs to happen.
class LiveViewerScreen extends StatefulWidget {
  final String shopName;
  final int sellerId;

  const LiveViewerScreen({
    super.key,
    required this.shopName,
    required this.sellerId,
  });

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  RtcEngine? _engine;
  int? _remoteUid;
  bool _joined = false;
  bool _disposed = false;
  String? _error;
  Timer? _joinTimeout;

  final _chatController = TextEditingController();
  final LiveRepository _liveRepository = LiveRepository();
  final ProductRepository _productRepository = ProductRepository();
  List<ProductModel> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _joinAsViewer();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _productRepository.getProductsBySeller(
        widget.sellerId,
      );
      if (mounted) setState(() => _products = products);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _joinTimeout?.cancel();
    _chatController.dispose();
    _leave();
    super.dispose();
  }

  Future<void> _joinAsViewer() async {
    if (!AgoraConfig.hasToken) {
      // Runs from initState, before the first build, so no setState needed.
      _error =
          "Live streaming isn't set up yet.\n"
          "Add a fresh Agora temp token in agora_config.dart.";
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

      // The screen was closed while the engine was starting up.
      if (_disposed) {
        await engine.release();
        return;
      }

      _engine = engine;

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            _joinTimeout?.cancel();
            if (!mounted) return;
            setState(() => _joined = true);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted) return;
            setState(() => _remoteUid = remoteUid);
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (!mounted) return;
            setState(() => _remoteUid = null);
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint("Agora connection: $state ($reason)");
            if (state == ConnectionStateType.connectionStateFailed) {
              _joinTimeout?.cancel();
              if (!mounted) return;
              setState(() => _error = _describeFailure(reason));
            }
          },
          onError: (err, msg) {
            // Many Agora errors are recoverable, so only log them here.
            // Fatal connection problems arrive via onConnectionStateChanged.
            debugPrint("Agora error: $err $msg");
          },
        ),
      );

      // Without enableVideo() an audience member never receives video.
      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleAudience);

      await engine.joinChannel(
        token: AgoraConfig.testToken,
        channelId: AgoraConfig.testChannelName,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleAudience,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      // If Agora never confirms the join, stop showing a spinner forever.
      _joinTimeout = Timer(const Duration(seconds: 15), () {
        if (!mounted || _joined || _error != null) return;
        setState(() {
          _error =
              "Couldn't connect to the stream.\n"
              "Check your connection and try again.";
        });
      });

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Agora join failed: $e");
      if (!mounted) return;
      setState(() => _error = "Couldn't connect to the stream.");
    }
  }

  String _describeFailure(ConnectionChangedReasonType reason) {
    if (reason == ConnectionChangedReasonType.connectionChangedInvalidToken ||
        reason == ConnectionChangedReasonType.connectionChangedTokenExpired) {
      return "The live-stream token is invalid or has expired.\n"
          "Generate a new temp token in the Agora Console and paste it "
          "into agora_config.dart.";
    }
    return "Couldn't connect to the stream.\n($reason)";
  }

  Future<void> _leave() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;

    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      debugPrint("Agora leave failed: $e");
    }
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final userId = SessionService.userId;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to join the conversation.')),
        );
      }
      return;
    }

    try {
      await _liveRepository.sendMessage(
        userId: userId,
        senderName: SessionService.firstName ?? 'Viewer',
        text: text,
        isSeller: false,
      );
      _chatController.clear();
    } catch (e) {
      debugPrint("Live chat send failed: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message.toString()
                : "Couldn't send your message.",
          ),
        ),
      );
    }
  }

  ProductModel? _productById(Object? id) {
    final productId = (id as num?)?.toInt();
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  void _openProduct(ProductModel product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)),
    );
  }

  void _showProducts() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            '${widget.shopName} products',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_products.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No products are available.'),
            ),
          for (final product in _products)
            ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: ProductImage(
                  path: product.image,
                  placeholder: const Icon(Icons.image_outlined),
                ),
              ),
              title: Text(product.productName),
              subtitle: Text(
                '₱${product.price.toStringAsFixed(2)} • ${product.stock} available',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _openProduct(product);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _heart() async {
    final userId = SessionService.userId;
    if (userId == null) return;
    try {
      await _liveRepository.addHeart(userId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _liveRepository.watchSession(),
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data ?? const <String, dynamic>{};
        final pinned = _productById(session['pinnedProductId']);
        final commentsEnabled = session['commentsEnabled'] != false;
        final liveIsActive =
            session['active'] == true && session['sellerId'] == widget.sellerId;
        final hearts =
            (session['reactionCounts']?['heart'] as num?)?.toInt() ?? 0;
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _buildVideo()),

                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.shopName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  right: 14,
                  bottom: 300,
                  child: Column(
                    children: [
                      _ViewerAction(
                        icon: Icons.favorite,
                        label: '$hearts',
                        onTap: _heart,
                      ),
                      const SizedBox(height: 12),
                      _ViewerAction(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Shop',
                        onTap: _showProducts,
                      ),
                    ],
                  ),
                ),

                if (pinned != null)
                  Positioned(
                    left: 12,
                    right: 80,
                    bottom: 300,
                    child: InkWell(
                      onTap: () => _openProduct(pinned),
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
                                path: pinned.image,
                                placeholder: const Icon(Icons.image_outlined),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'PINNED PRODUCT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    pinned.productName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text('₱${pinned.price.toStringAsFixed(2)}'),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ViewerChatOverlay(
                    chatController: _chatController,
                    onSend: _sendChatMessage,
                    liveRepository: _liveRepository,
                    commentsEnabled: commentsEnabled,
                    broadcastId: session['broadcastId'] as String?,
                  ),
                ),

                if (sessionSnapshot.hasData && !liveIsActive)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.videocam_off_outlined,
                              color: Colors.white70,
                              size: 56,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'This LIVE has ended.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Go back'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideo() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (!_joined || _engine == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_remoteUid == null) {
      return const Center(
        child: Text(
          "Waiting for the seller's stream to start...",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: const RtcConnection(channelId: AgoraConfig.testChannelName),
      ),
    );
  }
}

class _ViewerChatOverlay extends StatelessWidget {
  final TextEditingController chatController;
  final VoidCallback onSend;
  final LiveRepository liveRepository;
  final bool commentsEnabled;
  final String? broadcastId;

  const _ViewerChatOverlay({
    required this.chatController,
    required this.onSend,
    required this.liveRepository,
    required this.commentsEnabled,
    required this.broadcastId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 220,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: liveRepository.watchMessages(),
            builder: (context, snapshot) {
              final docs = (snapshot.data ?? const [])
                  .where(
                    (data) =>
                        data['hidden'] != true &&
                        data['broadcastId'] == broadcastId,
                  )
                  .toList();

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index];
                  final sender = data['senderName'] ?? "Someone";
                  final text = data['text'] ?? "";

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                        children: [
                          TextSpan(
                            text: "$sender  ",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: text),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.black.withValues(alpha: .35),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: chatController,
                      style: const TextStyle(color: Colors.white),
                      maxLength: 300,
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: "Say something...",
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      enabled: commentsEnabled,
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: commentsEnabled ? onSend : null,
                  ),
                ],
              ),
              if (!commentsEnabled)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'The seller paused comments.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ViewerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(28),
    child: Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: icon == Icons.favorite ? AppColors.error : Colors.white,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}
