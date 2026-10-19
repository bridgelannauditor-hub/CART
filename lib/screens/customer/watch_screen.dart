import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../repositories/shop_repository.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/product_image.dart';
import 'live_viewer_screen.dart';
import 'product_videos_view.dart';
import 'shop_screen.dart';

/// "Watch" tab with two sections: **Live** (every seller live right now;
/// tapping one opens [LiveViewerScreen], "Visit shop" opens [ShopScreen]) and
/// **Videos** (product videos uploaded by shops). The search icon filters the
/// current section.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final ShopRepository _shopRepository = ShopRepository();

  late Future<List<UserModel>> _liveShopsFuture;

  bool _showVideos = false;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setSearching(bool value) {
    setState(() {
      _searching = value;
      if (!value) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  PreferredSizeWidget _buildAppBar() {
    if (_searching) {
      return AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _setSearching(false),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          cursorColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: _showVideos ? 'Search videos' : 'Search live shops',
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _searchController.clear();
                _query = '';
              }),
            ),
        ],
      );
    }

    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          _SectionButton(
            label: 'Live',
            selected: !_showVideos,
            onTap: () => setState(() => _showVideos = false),
          ),
          const SizedBox(width: 20),
          _SectionButton(
            label: 'Videos',
            selected: _showVideos,
            onTap: () => setState(() => _showVideos = true),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => _setSearching(true),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

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
      appBar: _buildAppBar(),
      body: SafeArea(
        child: _showVideos
            ? ProductVideosView(query: _query)
            : RefreshIndicator(
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
                          SizedBox(
                            height: MediaQuery.of(context).size.height * .25,
                          ),
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

                    final query = _query.trim().toLowerCase();
                    final shops = [
                      for (final shop in snapshot.data ?? const <UserModel>[])
                        if (query.isEmpty ||
                            _shopName(shop).toLowerCase().contains(query))
                          shop,
                    ];

                    if (shops.isEmpty) {
                      // ListView so pull-to-refresh still works when empty.
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * .25,
                          ),
                          const Icon(
                            Icons.live_tv_outlined,
                            size: 64,
                            color: AppColors.lightGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.trim().isEmpty
                                ? "No one is live right now"
                                : "No live shops match your search",
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
                      itemBuilder: (context, index) =>
                          _buildLiveCard(shops[index]),
                    );
                  },
                ),
              ),
      ),
      bottomNavigationBar: const BottomNavbar(currentIndex: 2),
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

/// Text-only section switch used in the app bar: the selected one is bold
/// white with an underline, the other is dimmed.
class _SectionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 20,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: selected ? 24 : 0,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
