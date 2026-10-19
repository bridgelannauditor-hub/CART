import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/routes.dart';
import 'message_navigation_icon.dart';
import 'seller_orders_nav_icon.dart';

/// Bottom navigation for the seller side of the app.
/// Order: Home, Messages, Live, Orders, Profile — Live sits in the
/// middle slot as a quick-access "go live" shortcut for the shop.
class SellerBottomNavbar extends StatelessWidget {
  final int currentIndex;

  const SellerBottomNavbar({super.key, required this.currentIndex});

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, AppRoutes.sellerDashboard);
        break;
      case 1:
        Navigator.pushReplacementNamed(context, AppRoutes.sellerMessages);
        break;
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.sellerLive);
        break;
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.sellerOrders);
        break;
      case 4:
        Navigator.pushReplacementNamed(context, AppRoutes.sellerProfile);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: .15),
      onDestinationSelected: (index) => _onItemTapped(context, index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: "Home",
        ),
        NavigationDestination(
          icon: MessageNavigationIcon(),
          selectedIcon: MessageNavigationIcon(selected: true),
          label: "Messages",
        ),
        NavigationDestination(
          icon: Icon(Icons.add_circle_outline),
          selectedIcon: Icon(Icons.add_circle),
          label: "Live",
        ),
        NavigationDestination(
          icon: SellerOrdersNavIcon(),
          selectedIcon: SellerOrdersNavIcon(selected: true),
          label: "Orders",
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: "Profile",
        ),
      ],
    );
  }
}
