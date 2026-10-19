import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../data/craft_categories.dart';
import 'category_video_card.dart';

/// Auto-advancing, single-card-at-a-time carousel of the craft
/// category groups. Slides right-to-left on a timer, and can also be
/// swiped manually. Loops indefinitely via a large virtual page count.
class CraftVideoCarousel extends StatefulWidget {
  final ValueChanged<CraftCategoryGroup> onTapGroup;

  const CraftVideoCarousel({super.key, required this.onTapGroup});

  @override
  State<CraftVideoCarousel> createState() => _CraftVideoCarouselState();
}

class _CraftVideoCarouselState extends State<CraftVideoCarousel> {
  // Start deep into a very large virtual page range so we can always
  // advance forward (right-to-left) without ever hitting an edge.
  static const int _initialPage = 5000;

  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = _initialPage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupCount = craftCategoryGroups.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) {
              final group = craftCategoryGroups[index % groupCount];
              return CategoryVideoCard(
                title: group.title,
                leadIcon: group.items.first.icon,
                icons: [for (final item in group.items) item.icon],
                onTap: () => widget.onTapGroup(group),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(groupCount, (i) {
            final active = (_currentPage % groupCount) == i;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.lightGrey,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
