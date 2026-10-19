import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A tappable gradient tile for a craft category group: a large lead icon, a
/// row of the group's technique icons, and the title at the bottom. It is
/// intentionally icon-only (no network video) so it renders instantly and
/// never shows a loading spinner.
class CategoryVideoCard extends StatelessWidget {
  final String title;
  final IconData leadIcon;
  final List<IconData> icons;
  final VoidCallback onTap;

  const CategoryVideoCard({
    super.key,
    required this.title,
    required this.leadIcon,
    required this.icons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.darkGrey],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        child: Icon(leadIcon, color: Colors.white, size: 38),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      for (final icon in icons.take(4))
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            icon,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
