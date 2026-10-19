import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../database/seed_data.dart';
import '../../models/user_model.dart';
import '../../repositories/shop_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/cloudinary_service.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import '../../widgets/product_image.dart';
import '../../widgets/seller_bottom_navbar.dart';
import '../customer/about_screen.dart';
import '../customer/help_support_screen.dart';
import '../customer/follow_list_screen.dart';
import '../customer/notifications_screen.dart';
import '../customer/password_security_screen.dart';
import '../customer/personal_information_screen.dart';
import '../customer/settings_screen.dart';
import '../customer/shop_screen.dart';
import 'seller_shop_management_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  final _shops = ShopRepository();
  final _users = UserRepository();
  UserModel? _user;
  bool _loading = true;
  bool _savingImage = false;
  bool _resetting = false;
  String? _error;
  int _following = 0;
  int _followers = 0;
  int _visitors = 0;
  int _unitsSold = 0;
  double _rating = 0;
  int _reviews = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _openFollowList(FollowListMode mode) {
    final id = SessionService.userId;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListScreen(mode: mode, userId: id),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final id = SessionService.userId;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'Your seller session has expired.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _users.getUserById(id),
        _shops.getFollowedShopCount(id),
        _shops.getFollowerCount(id),
        _shops.getVisitorCount(id),
        _shops.getProductMetrics(id),
      ]);
      if (!mounted) return;
      final metrics = values[4] as SellerProductMetrics;
      setState(() {
        _user = values[0] as UserModel?;
        _following = values[1] as int;
        _followers = values[2] as int;
        _visitors = values[3] as int;
        _unitsSold = metrics.unitsSold;
        _rating = metrics.averageRating;
        _reviews = metrics.reviewCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'We could not load your shop profile.';
        });
      }
    }
  }

  String get _shopName {
    final name = _user?.shopName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final owner =
        '${SessionService.firstName ?? ''} ${SessionService.lastName ?? ''}'
            .trim();
    return owner.isEmpty ? 'My Shop' : owner;
  }

  int get _completion {
    final done = [
      _user?.shopName?.trim().isNotEmpty ?? false,
      _user?.coverImage?.trim().isNotEmpty ?? false,
      _user?.profileImage?.trim().isNotEmpty ?? false,
      _user?.phone?.trim().isNotEmpty ?? false,
    ].where((value) => value).length;
    return (done / 4 * 100).round();
  }

  String get _nextStep {
    if (!(_user?.shopName?.trim().isNotEmpty ?? false)) {
      return 'Add your shop name and owner details';
    }
    if (!(_user?.profileImage?.trim().isNotEmpty ?? false)) {
      return 'Add a recognizable shop photo';
    }
    if (!(_user?.coverImage?.trim().isNotEmpty ?? false)) {
      return 'Add a cover that shows your craft';
    }
    if (!(_user?.phone?.trim().isNotEmpty ?? false)) {
      return 'Add a contact number';
    }
    return 'Your shop profile is ready for customers';
  }

  Future<void> _open(Widget screen, {bool reload = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (reload && mounted) await _load();
  }

  void _viewShop() {
    final id = SessionService.userId;
    if (id != null) _open(ShopScreen(sellerId: id));
  }

  void _switchToCustomerMode() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.home,
      (route) => false,
    );
  }

  Future<void> _pickImage({required bool cover}) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null || SessionService.userId == null) return;
    setState(() => _savingImage = true);
    try {
      final url = await CloudinaryService.upload(
        File(image.path),
        resourceType: 'image',
      );
      await _users.updateShopImages(
        sellerId: SessionService.userId!,
        firebaseUid: SessionService.firebaseUid,
        coverImage: cover ? url : null,
        profileImage: cover ? null : url,
      );
      if (!mounted) return;
      setState(() {
        _user = _user?.copyWith(
          coverImage: cover ? url : null,
          profileImage: cover ? null : url,
        );
        _savingImage = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shop appearance updated.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update the shop image.")),
      );
    }
  }

  void _editAppearance() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit shop appearance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose what customers see on your storefront.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Edit shop name'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editShopName();
                },
              ),
              ListTile(
                leading: const Icon(Icons.landscape_outlined),
                title: const Text('Change cover image'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(cover: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Change shop photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(cover: false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editShopName() async {
    final controller = TextEditingController(text: _user?.shopName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shop name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Shop name',
            hintText: 'Give your shop a memorable name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted || SessionService.userId == null) return;
    try {
      await _users.updateShopName(
        sellerId: SessionService.userId!,
        firebaseUid: SessionService.firebaseUid,
        shopName: name,
      );
      if (!mounted) return;
      setState(() => _user = _user?.copyWith(shopName: name));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update the shop name.")),
        );
      }
    }
  }

  Future<void> _continueProfile() async {
    if (!(_user?.shopName?.trim().isNotEmpty ?? false)) {
      await _editShopName();
    } else if (!(_user?.phone?.trim().isNotEmpty ?? false)) {
      await _open(const PersonalInformationScreen(), reload: true);
    } else if (!(_user?.profileImage?.trim().isNotEmpty ?? false)) {
      await _pickImage(cover: false);
    } else if (!(_user?.coverImage?.trim().isNotEmpty ?? false)) {
      await _pickImage(cover: true);
    }
  }

  Future<void> _logout() async {
    await SessionService.logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  Future<void> _resetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset local data?'),
        content: const Text(
          'This clears all local app data on this device and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);
    await DatabaseHelper.instance.deleteDatabaseFile();
    await SeedData.insertInitialData();
    if (mounted) await _logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const SellerBottomNavbar(currentIndex: 4),
      body: SafeArea(
        child: _resetting
            ? const _Status(message: 'Resetting local data...')
            : _loading
            ? const _Status(message: 'Loading your shop...')
            : _error != null
            ? _Error(message: _error!, retry: _load)
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _Hero(
                      shopName: _shopName,
                      user: _user,
                      saving: _savingImage,
                      edit: _editAppearance,
                      view: _viewShop,
                      unitsSold: _unitsSold,
                      rating: _rating,
                      reviews: _reviews,
                    ),
                    const SizedBox(height: 16),
                    _Stats(
                      following: _following,
                      followers: _followers,
                      visitors: _visitors,
                      onFollowing: () =>
                          _openFollowList(FollowListMode.following),
                      onFollowers: () =>
                          _openFollowList(FollowListMode.followers),
                    ),
                    if (_user?.sellerVerification != null) ...[
                      const SizedBox(height: 16),
                      _VerificationCard(user: _user!),
                    ],
                    const SizedBox(height: 16),
                    _Completion(
                      percent: _completion,
                      message: _nextStep,
                      next: _completion == 100 ? null : _continueProfile,
                    ),
                    const SizedBox(height: 28),
                    const _Label('SHOP MANAGEMENT'),
                    const SizedBox(height: 10),
                    _Group(
                      children: [
                        _Tile(
                          Icons.analytics_outlined,
                          'Sales analytics',
                          () => _open(const SellerShopManagementScreen()),
                          subtitle: 'Revenue, products, and order charts',
                        ),
                        _Tile(
                          Icons.store_mall_directory_outlined,
                          'Shop information',
                          _editShopName,
                          subtitle: 'Shop name and public identity',
                        ),
                        _Tile(
                          Icons.palette_outlined,
                          'Appearance and branding',
                          _editAppearance,
                          subtitle: 'Cover and shop photo',
                        ),
                        _Tile(
                          Icons.visibility_outlined,
                          'View public shop',
                          _viewShop,
                          subtitle: 'Preview what customers see',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _Label('ACCOUNT'),
                    const SizedBox(height: 10),
                    _Group(
                      children: [
                        _Tile(
                          Icons.swap_horiz_rounded,
                          'Switch to Customer mode',
                          _switchToCustomerMode,
                          subtitle: 'Browse, buy, and use your Buyer features',
                        ),
                        _Tile(
                          Icons.person_outline_rounded,
                          'Personal information',
                          () => _open(
                            const PersonalInformationScreen(),
                            reload: true,
                          ),
                        ),
                        _Tile(
                          Icons.lock_outline_rounded,
                          'Password and security',
                          () => _open(const PasswordSecurityScreen()),
                        ),
                        _Tile(
                          Icons.notifications_none_rounded,
                          'Notifications',
                          () => _open(const NotificationsScreen()),
                        ),
                        _Tile(
                          Icons.tune_rounded,
                          'Preferences',
                          () => _open(const SettingsScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _Label('SUPPORT'),
                    const SizedBox(height: 10),
                    _Group(
                      children: [
                        _Tile(
                          Icons.help_outline_rounded,
                          'Help and support',
                          () => _open(const HelpSupportScreen()),
                        ),
                        _Tile(
                          Icons.info_outline_rounded,
                          'About C+ART',
                          () => _open(const AboutScreen()),
                        ),
                      ],
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      const _Label('DEVELOPER TOOLS'),
                      const SizedBox(height: 10),
                      _Group(
                        children: [
                          _Tile(
                            Icons.restart_alt_rounded,
                            'Reset local data',
                            _resetData,
                            danger: true,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                          color: AppColors.error.withValues(alpha: .35),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Log out',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final UserModel user;

  const _VerificationCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final verification = user.sellerVerification!;
    final isApproved = user.hasCurrentSellerVerification;
    final color = isApproved
        ? const Color(0xFF2E7D32)
        : const Color(0xFF9A6700);
    final title = isApproved
        ? verification.sellerType == 'student'
              ? 'Verified Student Crafter'
              : 'Verified Seller'
        : 'Verification under review';
    final sellerLabel = switch (verification.sellerType) {
      'student' => 'Student / side-hustle seller',
      'business' => 'Business seller',
      _ => 'Individual seller',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isApproved ? Icons.verified_rounded : Icons.schedule_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  isApproved
                      ? '$sellerLabel · Tier ${user.sellerTier} · Trust ${user.trustScore.toStringAsFixed(0)}/100'
                      : '$sellerLabel · Up to ${verification.listingLimit} listings during review',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (isApproved && user.verificationExpiry != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Verification valid until ${user.verificationExpiry!.split('T').first}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String shopName;
  final UserModel? user;
  final bool saving;
  final VoidCallback edit;
  final VoidCallback view;
  final int unitsSold;
  final double rating;
  final int reviews;
  const _Hero({
    required this.shopName,
    required this.user,
    required this.saving,
    required this.edit,
    required this.view,
    required this.unitsSold,
    required this.rating,
    required this.reviews,
  });
  @override
  Widget build(BuildContext context) {
    final initial = shopName[0].toUpperCase();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _card(radius: 24, shadow: true),
      child: AspectRatio(
        aspectRatio: 2.39,
        child: Stack(
          fit: StackFit.expand,
          children: [
            (user?.coverImage ?? '').isEmpty
                ? const _Cover()
                : ProductImage(
                    path: user!.coverImage!,
                    fit: BoxFit.cover,
                    placeholder: const _Cover(),
                  ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .12),
                    Colors.black.withValues(alpha: .36),
                    Colors.black.withValues(alpha: .88),
                  ],
                  stops: const [0, .42, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: (user?.profileImage ?? '').isEmpty
                              ? _Avatar(initial)
                              : ProductImage(
                                  path: user!.profileImage!,
                                  fit: BoxFit.cover,
                                  placeholder: _Avatar(initial),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 5),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '$unitsSold sold',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '•',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFFFC857),
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    reviews == 0
                                        ? 'No ratings'
                                        : '${rating.toStringAsFixed(1)} ($reviews)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : edit,
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text(
                            'Edit shop',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            elevation: 0,
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: view,
                          icon: const Icon(Icons.visibility_outlined, size: 15),
                          label: const Text(
                            'View shop',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (saving)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover();
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.dark, AppColors.primary, AppColors.secondary],
      ),
    ),
    child: const Align(
      alignment: Alignment(.7, -.2),
      child: Icon(Icons.auto_awesome, color: Colors.white24, size: 56),
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String initial;
  const _Avatar(this.initial);
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.primary,
    alignment: Alignment.center,
    child: Text(
      initial,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class _Stats extends StatelessWidget {
  final int following, followers, visitors;
  final VoidCallback onFollowing, onFollowers;
  const _Stats({
    required this.following,
    required this.followers,
    required this.visitors,
    required this.onFollowing,
    required this.onFollowers,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: _card(),
    child: Row(
      children: [
        Expanded(child: _Stat('$following', 'Following', onTap: onFollowing)),
        const _Divider(),
        Expanded(child: _Stat('$followers', 'Followers', onTap: onFollowers)),
        const _Divider(),
        Expanded(child: _Stat('$visitors', 'Visitors')),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label;
  final VoidCallback? onTap;
  const _Stat(this.value, this.label, {this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.lightGrey);
}

class _Completion extends StatelessWidget {
  final int percent;
  final String message;
  final VoidCallback? next;
  const _Completion({
    required this.percent,
    required this.message,
    required this.next,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                percent == 100 ? 'Shop profile complete' : 'Complete your shop',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '$percent%',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 7,
            backgroundColor: Colors.white,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (next != null)
              TextButton(onPressed: next, child: const Text('Continue')),
          ],
        ),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .9,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  final List<_Tile> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: _card(),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const Divider(height: 1, indent: 62, color: AppColors.lightGrey),
        ],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback tap;
  final bool danger;
  const _Tile(
    this.icon,
    this.label,
    this.tap, {
    this.subtitle,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.error : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (!danger)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String message;
  const _Status({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 14),
        Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _Error({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

BoxDecoration _card({double radius = 18, bool shadow = false}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: AppColors.lightGrey.withValues(alpha: .7)),
  boxShadow: shadow
      ? [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: .08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ]
      : null,
);
