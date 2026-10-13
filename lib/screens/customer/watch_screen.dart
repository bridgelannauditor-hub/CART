import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../repositories/shop_repository.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/product_image.dart';
import 'live_viewer_screen.dart';
import 'shop_screen.dart';

/// "Watch" tab: every seller who is live right now. Tapping one opens
/// [LiveViewerScreen]; "Visit shop" opens the seller's [ShopScreen].
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final ShopRepository _shopRepository = ShopRepository();

  late Future<List<UserModel>> _liveShopsFuture;

  @override
  void initState() {
    super.initState();
    _liveShopsFuture = _shopRepository.getLiveShops();
  }

  Future<void> _refresh() async {
    final future = _shopRepository.getLiveShops();

    // Block body on purpose: an arrow function here would return the
    // Future and make setState() throw.
    setState(() {
      _liveShopsFuture = future;
    });

    try {
      await future;
    } catch (_) {
      // The error is shown by the FutureBuilder below.
    }
  }

  String _shopName(UserModel shop) {
    final name = shop.shopName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return "${shop.firstName} ${shop.lastName}".trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Watch",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<UserModel>>(
            future: _liveShopsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                // ListView so pull-to-refresh still works after an error.
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * .25),
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: AppColors.lightGrey,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Couldn't load live shops",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Check your connection and pull down to try again",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                );
              }

              final shops = snapshot.data ?? [];

              if (shops.isEmpty) {
                // ListView so pull-to-refresh still works when empty.
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * .25),
                    const Icon(
                      Icons.live_tv_outlined,
                      size: 64,
                      color: AppColors.lightGrey,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "No one is live right now",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Pull down to refresh",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: shops.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildLiveCard(shops[index]),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavbar(currentIndex: 1),
    );
  }

  Widget _buildLiveCard(UserModel shop) {
    final name = _shopName(shop);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";
    final profilePath = shop.profileImage ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LiveViewerScreen(shopName: name, sellerId: shop.id!),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.error, width: 2.5),
              ),
              child: ClipOval(
                child: profilePath.isNotEmpty
                    ? ProductImage(
                        path: profilePath,
                        fit: BoxFit.cover,
                        placeholder: _initialAvatar(initial),
                      )
                    : _initialAvatar(initial),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "● LIVE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveViewerScreen(
                          shopName: name,
                          sellerId: shop.id!,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text("Watch"),
                ),
                if (shop.id != null)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShopScreen(sellerId: shop.id!),
                        ),
                      );
                    },
                    child: const Text(
                      "Visit shop",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar(String initial) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
    );
  }
}
