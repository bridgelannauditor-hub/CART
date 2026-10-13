import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Generic "not built yet" placeholder page. Used by profile menu

/// items (Personal Information, Delivery Addresses, Password &

/// Security, Settings, Help & Support, About) until each gets a

/// real screen of its own.

class ComingSoonScreen extends StatelessWidget {
  final String title;

  final IconData icon;

  const ComingSoonScreen({
    super.key,

    required this.title,

    this.icon = Icons.construction_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(title: Text(title)),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Container(
                width: 84,

                height: 84,

                alignment: Alignment.center,

                decoration: BoxDecoration(
                  shape: BoxShape.circle,

                  color: AppColors.primary.withValues(alpha: 0.08),
                ),

                child: Icon(icon, size: 36, color: AppColors.primary),
              ),

              const SizedBox(height: 20),

              Text(
                "$title is coming soon",

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontSize: 16,

                  fontWeight: FontWeight.w700,

                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "We're still working on this section. Check back later!",

                textAlign: TextAlign.center,

                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
