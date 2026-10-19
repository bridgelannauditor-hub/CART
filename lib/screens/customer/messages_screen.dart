import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/conversation_model.dart';
import '../../models/user_model.dart';
import '../../repositories/message_repository.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/shop_repository.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/product_image.dart';
import '../../widgets/seller_bottom_navbar.dart';
import 'chat_screen.dart';
import 'live_viewer_screen.dart';
import 'notifications_screen.dart';
import 'shop_screen.dart';

class MessagesScreen extends StatefulWidget {
  final bool showBottomNav;

  // When true, shows the seller bottom navbar instead of the
  // customer one — used when a seller opens Messages from their tabs.
  final bool isSeller;

  const MessagesScreen({
    super.key,
    this.showBottomNav = true,
    this.isSeller = false,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final MessageRepository _messageRepository = MessageRepository();
  final NotificationRepository _notificationRepository =
      NotificationRepository();
  final ShopRepository _shopRepository = ShopRepository();

  late Stream<ConversationPage> _conversationsStream;
  final List<ConversationModel> _olderConversations = [];
  String? _olderConversationCursor;
  bool _hasMoreConversations = true;
  bool _isLoadingOlderConversations = false;

  int cartCount = 0;
  int unreadNotifications = 0;
  final List<UserModel> _followedShops = [];
  String? _followedShopsCursor;
  bool _hasMoreFollowedShops = true;
  bool _isLoadingMoreFollowedShops = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadCartCount();
    _loadUnreadNotifications();
    _loadFollowedShops();
  }

  Future<void> _loadFollowedShops({bool reset = true}) async {
    if (widget.isSeller) return;

    final userId = SessionService.userId;
    if (userId == null) return;
    if (!reset && (_isLoadingMoreFollowedShops || !_hasMoreFollowedShops)) {
      return;
    }

    if (mounted) {
      setState(() => _isLoadingMoreFollowedShops = !reset);
    }
    try {
      final page = await _shopRepository.getFollowedShopsPage(
        userId,
        after: reset ? null : _followedShopsCursor,
      );

      if (!mounted) return;
      setState(() {
        if (reset) _followedShops.clear();
        final existingIds = _followedShops.map((shop) => shop.id).toSet();
        _followedShops.addAll(
          page.items.where((shop) => !existingIds.contains(shop.id)),
        );
        _followedShopsCursor = page.cursor;
        _hasMoreFollowedShops = page.hasMore;
        _isLoadingMoreFollowedShops = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMoreFollowedShops = false);
    }
  }

  Future<void> _loadCartCount() async {
    if (widget.isSeller) return;

    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;
      setState(() => cartCount = 0);
      return;
    }

    final count = await DatabaseHelper.instance.getCartItemCount(userId);

    if (!mounted) return;
    setState(() => cartCount = count);
  }

  Future<void> _loadUnreadNotifications() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;
      setState(() => unreadNotifications = 0);
      return;
    }

    final count = await _notificationRepository.getUnreadCount(userId);

    if (!mounted) return;
    setState(() => unreadNotifications = count);
  }

  void _loadConversations() {
    final userId = SessionService.userId;
    _conversationsStream = userId == null
        ? Stream.value(
            const ConversationPage(items: [], cursor: null, hasMore: false),
          )
        : _messageRepository.watchConversationPage(userId);
  }

  Future<void> _loadOlderConversations(ConversationPage newestPage) async {
    final userId = SessionService.userId;
    if (userId == null ||
        _isLoadingOlderConversations ||
        !_hasMoreConversations) {
      return;
    }
    final cursor = _olderConversationCursor ?? newestPage.cursor;
    if (cursor == null) return;

    setState(() => _isLoadingOlderConversations = true);
    try {
      final page = await _messageRepository.getConversationsPage(
        userId,
        after: cursor,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _olderConversations
            .map((conversation) => conversation.otherUserId)
            .toSet();
        _olderConversations.addAll(
          page.items.where(
            (conversation) => !existingIds.contains(conversation.otherUserId),
          ),
        );
        _olderConversationCursor = page.cursor;
        _hasMoreConversations = page.hasMore;
        _isLoadingOlderConversations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingOlderConversations = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _olderConversations.clear();
      _olderConversationCursor = null;
      _hasMoreConversations = true;
      _loadConversations();
    });
    await Future.wait([
      _loadCartCount(),
      _loadUnreadNotifications(),
      _loadFollowedShops(reset: true),
    ]);
  }

  Future<void> _openChat(ConversationModel conversation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: conversation.otherUserId,
          otherUserName: conversation.otherUserName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Messages",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // =====================================================
          // NOTIFICATIONS
          // =====================================================
          _AppBarIconWithBadge(
            icon: Icons.notifications_outlined,
            count: unreadNotifications,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );

              if (!mounted) return;
              await _loadUnreadNotifications();
            },
          ),

          // =====================================================
          // CART (customer only)
          // =====================================================
          if (!widget.isSeller)
            _AppBarIconWithBadge(
              icon: Icons.shopping_bag_outlined,
              count: cartCount,
              onTap: () async {
                await Navigator.pushNamed(context, AppRoutes.cart);

                if (!mounted) return;
                await _loadCartCount();
              },
            ),

          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: widget.isSeller
          ? const SellerBottomNavbar(currentIndex: 1)
          : widget.showBottomNav
          ? const BottomNavbar(currentIndex: 1)
          : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: Column(
          children: [
            if (!widget.isSeller && _followedShops.isNotEmpty)
              _buildFollowingRow(),

            Expanded(
              child: StreamBuilder<ConversationPage>(
                stream: _conversationsStream,
                builder: (context, snapshot) {
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final newestPage =
                      snapshot.data ??
                      const ConversationPage(
                        items: [],
                        cursor: null,
                        hasMore: false,
                      );
                  final newestIds = newestPage.items
                      .map((conversation) => conversation.otherUserId)
                      .toSet();
                  final conversations = [
                    ...newestPage.items,
                    ..._olderConversations.where(
                      (conversation) =>
                          !newestIds.contains(conversation.otherUserId),
                    ),
                  ];
                  final hasMore = _olderConversationCursor == null
                      ? newestPage.hasMore
                      : _hasMoreConversations;

                  if (isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (conversations.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      children: const [
                        SizedBox(height: 100),
                        Icon(
                          Icons.forum_outlined,
                          size: 56,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          "No messages yet",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 6),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            "Message a seller from a product page to start a conversation.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conversations.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == conversations.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _isLoadingOlderConversations
                                ? const CircularProgressIndicator(
                                    color: AppColors.primary,
                                  )
                                : OutlinedButton(
                                    onPressed: () =>
                                        _loadOlderConversations(newestPage),
                                    child: const Text(
                                      'Load older conversations',
                                    ),
                                  ),
                          ),
                        );
                      }
                      final conversation = conversations[index];
                      return _ConversationTile(
                        conversation: conversation,
                        onTap: () => _openChat(conversation),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // FOLLOWING (story row of followed shops, red ring = live)
  // =========================================================

  Widget _buildFollowingRow() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lightGrey)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _followedShops.length + (_hasMoreFollowedShops ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == _followedShops.length) {
            return SizedBox(
              width: 62,
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: _isLoadingMoreFollowedShops
                    ? null
                    : () => _loadFollowedShops(reset: false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.lightGrey),
                      ),
                      child: _isLoadingMoreFollowedShops
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.more_horiz_rounded),
                    ),
                    const SizedBox(height: 3),
                    const Text('More', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            );
          }
          final shop = _followedShops[index];
          final shopName = (shop.shopName?.trim().isNotEmpty ?? false)
              ? shop.shopName!.trim()
              : "${shop.firstName} ${shop.lastName}".trim();
          final initial = shopName.isNotEmpty ? shopName[0].toUpperCase() : "?";
          final profilePath = shop.profileImage ?? '';

          return GestureDetector(
            onTap: () {
              if (shop.isLive) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveViewerScreen(
                      shopName: shopName,
                      sellerId: shop.id!,
                    ),
                  ),
                );
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopScreen(sellerId: shop.id!),
                ),
              );
            },
            child: SizedBox(
              width: 62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: shop.isLive
                            ? AppColors.error
                            : AppColors.lightGrey,
                        width: shop.isLive ? 2.5 : 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: profilePath.isNotEmpty
                          ? ProductImage(
                              path: profilePath,
                              fit: BoxFit.cover,
                              placeholder: _shopInitialAvatar(initial),
                            )
                          : _shopInitialAvatar(initial),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    shop.isLive ? "Live" : shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: shop.isLive
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: shop.isLive
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shopInitialAvatar(String initial) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}

// =========================================================
// APP BAR ICON WITH BADGE (Notifications / Cart)
// =========================================================
class _AppBarIconWithBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _AppBarIconWithBadge({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: (conversation.otherUserProfileImage ?? '').isNotEmpty
                    ? ProductImage(
                        path: conversation.otherUserProfileImage!,
                        fit: BoxFit.cover,
                        placeholder: _ConversationAvatarFallback(
                          name: conversation.otherUserName,
                        ),
                      )
                    : _ConversationAvatarFallback(
                        name: conversation.otherUserName,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.lastMessage.contextName?.isNotEmpty == true
                        ? '${conversation.lastMessage.contextType == 'product' ? 'Product' : 'Shop'}: ${conversation.lastMessage.contextName} · ${conversation.lastMessage.previewText}'
                        : conversation.lastMessage.previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasUnread
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: hasUnread
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${conversation.unreadCount}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConversationAvatarFallback extends StatelessWidget {
  final String name;

  const _ConversationAvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
