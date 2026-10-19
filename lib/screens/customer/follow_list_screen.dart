import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../repositories/shop_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';
import 'shop_screen.dart';

enum FollowListMode { followers, following }

/// People who follow a shop, or the shops a user follows.
///
/// A shop's owner sees followers' full names; everyone else sees a short form
/// ("Maria S.") so follower identities are not exposed publicly.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key, required this.mode, required this.userId});

  final FollowListMode mode;

  /// The shop (followers) or the follower (following) whose list is shown.
  final int userId;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final ShopRepository _repository = ShopRepository();
  final List<UserModel> _items = [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  bool get _isFollowers => widget.mode == FollowListMode.followers;
  bool get _viewerIsOwner =>
      _isFollowers && SessionService.userId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loadingMore || !_hasMore)) return;
    setState(() {
      _failed = false;
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
    });
    try {
      final after = more ? _cursor : null;
      final page = _isFollowers
          ? await _repository.getFollowersPage(widget.userId, after: after)
          : await _repository.getFollowedShopsPage(widget.userId, after: after);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String _nameFor(UserModel user) {
    final shop = user.shopName?.trim() ?? '';
    if (!_isFollowers && shop.isNotEmpty) return shop;
    final first = user.firstName.trim();
    final last = user.lastName.trim();
    if (_isFollowers && !_viewerIsOwner) {
      final initial = last.isEmpty ? '' : ' ${last[0].toUpperCase()}.';
      return '$first$initial'.trim();
    }
    return '$first $last'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isFollowers ? 'Followers' : 'Followed stores',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _failed && _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('This list could not be loaded.'),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _isFollowers
                      ? 'No followers yet.'
                      : 'You are not following any stores yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton(
                        onPressed: _loadingMore
                            ? null
                            : () => _load(more: true),
                        child: _loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Load more'),
                      ),
                    );
                  }
                  final user = _items[index];
                  final name = _nameFor(user);
                  final image = user.profileImage ?? '';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.lightGrey,
                      child: ClipOval(
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: image.isEmpty
                              ? Center(
                                  child: Text(
                                    name.isEmpty ? '?' : name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : ProductImage(
                                  path: image,
                                  placeholder: const SizedBox.shrink(),
                                ),
                        ),
                      ),
                    ),
                    title: Text(
                      name.isEmpty ? 'User ${user.id}' : name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: !_isFollowers && user.firstName.isNotEmpty
                        ? Text('${user.firstName} ${user.lastName}'.trim())
                        : null,
                    trailing: _isFollowers
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: _isFollowers || user.id == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ShopScreen(sellerId: user.id!),
                            ),
                          ),
                  );
                },
              ),
            ),
    );
  }
}
