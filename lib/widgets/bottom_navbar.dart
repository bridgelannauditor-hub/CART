import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/routes.dart';
import 'message_navigation_icon.dart';

class BottomNavbar extends StatelessWidget {
  final int currentIndex;

  const BottomNavbar({super.key, required this.currentIndex});

  void _onItemTapped(BuildContext context, int index) {
    // Re-tapping the current tab shouldn't rebuild the whole screen.
    if (index == currentIndex) return;
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        break;

      case 1:
        Navigator.pushReplacementNamed(context, AppRoutes.messages);
        break;

      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.watch);
        break;

      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.orders);
        break;

      case 4:
        Navigator.pushReplacementNamed(context, AppRoutes.profile);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: .15),
      onDestinationSelected: (index) {
        _onItemTapped(context, index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: "Home",
        ),
        NavigationDestination(
          icon: MessageNavigationIcon(),
          selectedIcon: MessageNavigationIcon(selected: true),
          label: "Messages",
        ),
        NavigationDestination(
          icon: Icon(Icons.live_tv_outlined),
          selectedIcon: Icon(Icons.live_tv),
          label: "Watch",
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
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
