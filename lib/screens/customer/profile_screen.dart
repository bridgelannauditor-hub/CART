import 'my_vouchers_screen.dart';
import '../../repositories/voucher_repository.dart';
import '../../repositories/shop_repository.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../database/seed_data.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import '../../widgets/bottom_navbar.dart';
import 'about_screen.dart';
import 'delivery_addresses_screen.dart';
import 'favorites_screen.dart';
import 'help_support_screen.dart';
import 'notifications_screen.dart';
import 'password_security_screen.dart';
import 'personal_information_screen.dart';
import 'settings_screen.dart';
import 'seller_onboarding_screen.dart';
import '../../repositories/admin_repository.dart';
import '../admin/admin_seller_review_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isResetting = false;
  int _voucherCount = 0;
  int _followedCount = 0;
  bool _isAdmin = false;
  @override
  void initState() {
    super.initState();
    _loadCounts();
    _loadAdminAccess();
  }

  // Only decides whether to show the admin tile; the server re-checks access.
  Future<void> _loadAdminAccess() async {
    final isAdmin = await AdminRepository().isAdmin();
    if (mounted && isAdmin != _isAdmin) setState(() => _isAdmin = isAdmin);
  }

  Future<void> _loadCounts() async {
    final id = SessionService.userId;
    if (id == null) return;
    try {
      final availableVoucherCount = await VoucherRepository()
          .availableVoucherCount(id);
      final followedShopCount = await ShopRepository().getFollowedShopCount(id);
      if (mounted) {
        setState(() {
          _voucherCount = availableVoucherCount;
          _followedCount = followedShopCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    await SessionService.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) => _loadCounts());
  }

  Future<void> _confirmResetLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Reset local data?"),
        content: const Text(
          "This clears ALL local app data on this device — every account, "
          "product, order, and message — and starts fresh with just the "
          "category list. This cannot be undone. Use this if you're seeing "
          "products or data that don't belong to your account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text("Reset"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    setState(() => _isResetting = true);

    await DatabaseHelper.instance.deleteDatabaseFile();
    await SeedData.insertInitialData();

    if (!context.mounted) return;

    await SessionService.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstName = SessionService.firstName ?? "";
    final lastName = SessionService.lastName ?? "";
    final fullName = "$firstName $lastName".trim();
    final email = SessionService.email ?? "";
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : "?";

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNavbar(currentIndex: 4),
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openScreen(context, const SettingsScreen()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isResetting
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        "Resetting local data...",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  // ==========================
                  // HEADER CARD — avatar left, info right
                  // ==========================

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.dark.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName.isEmpty ? "Guest" : fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "Customer Account",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ==========================
                  // STATS ROW
                  // ==========================
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.dark.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatItem(
                          value: '$_followedCount',
                          label: "Followed Stores",
                        ),
                        const _StatDivider(),
                        _StatItem(value: '$_voucherCount', label: "Vouchers"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==========================
                  // ACCOUNT SECTION
                  // ==========================
                  const _SectionHeader(label: "ACCOUNT"),
                  const SizedBox(height: 10),

                  _TileGroup(
                    tiles: [
                      _ProfileTile(
                        icon: Icons.person_outline,
                        label: "Personal Information",
                        onTap: () => _openScreen(
                          context,
                          const PersonalInformationScreen(),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.location_on_outlined,
                        label: "Delivery Addresses",
                        onTap: () => _openScreen(
                          context,
                          const DeliveryAddressesScreen(),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.local_offer_outlined,
                        label: 'My Vouchers',
                        onTap: () =>
                            _openScreen(context, const MyVouchersScreen()),
                      ),
                      _ProfileTile(
                        icon: Icons.favorite_border_rounded,
                        label: "Favorites",
                        onTap: () =>
                            _openScreen(context, const FavoritesScreen()),
                      ),
                      _ProfileTile(
                        icon: Icons.lock_outline_rounded,
                        label: "Password & Security",
                        onTap: () => _openScreen(
                          context,
                          const PasswordSecurityScreen(),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.storefront_outlined,
                        label: "Apply to Sell",
                        onTap: () => _openScreen(
                          context,
                          const SellerOnboardingScreen(),
                        ),
                      ),
                      if (_isAdmin)
                        _ProfileTile(
                          icon: Icons.admin_panel_settings_outlined,
                          label: "Admin: Seller Applications",
                          onTap: () => _openScreen(
                            context,
                            const AdminSellerReviewScreen(),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ==========================
                  // OTHER SECTION
                  // ==========================
                  const _SectionHeader(label: "OTHER"),
                  const SizedBox(height: 10),

                  _TileGroup(
                    tiles: [
                      _ProfileTile(
                        icon: Icons.notifications_none_rounded,
                        label: "Notifications",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.settings_outlined,
                        label: "Settings",
                        onTap: () =>
                            _openScreen(context, const SettingsScreen()),
                      ),
                      _ProfileTile(
                        icon: Icons.help_outline_rounded,
                        label: "Help & Support",
                        onTap: () =>
                            _openScreen(context, const HelpSupportScreen()),
                      ),
                      _ProfileTile(
                        icon: Icons.info_outline_rounded,
                        label: "About C+ART",
                        onTap: () => _openScreen(context, const AboutScreen()),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  _TileGroup(
                    tiles: [
                      _ProfileTile(
                        icon: Icons.restart_alt_rounded,
                        label: "Reset Local Data",
                        danger: true,
                        onTap: () => _confirmResetLocalData(context),
                      ),
                      _ProfileTile(
                        icon: Icons.logout_rounded,
                        label: "Log Out",
                        danger: true,
                        onTap: () => _logout(context),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: AppColors.lightGrey);
  }
}

/// Wraps a set of [_ProfileTile] rows into one rounded, shadowed card
/// with a thin divider between rows — so a whole section (e.g. all of
/// ACCOUNT) reads as a single merged block instead of separate floating
/// boxes.
class _TileGroup extends StatelessWidget {
  final List<_ProfileTile> tiles;

  const _TileGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1)
              const Divider(
                height: 1,
                thickness: 0.6,
                indent: 62,
                color: AppColors.lightGrey,
              ),
          ],
        ],
      ),
    );
  }
}

/// A single row inside a [_TileGroup].
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    final iconBg = danger
        ? AppColors.error.withValues(alpha: 0.1)
        : AppColors.primary.withValues(alpha: 0.08);
    final iconColor = danger ? AppColors.error : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
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
