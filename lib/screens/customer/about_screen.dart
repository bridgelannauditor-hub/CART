import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../widgets/custom_logo.dart';

/// Static "About the app" screen — brand story, version, and legal
/// links. Everything here is fixed copy; nothing reads from the
/// database.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "About C+ART",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            Center(
              child: Column(
                children: [
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    child: CustomLogo(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    AppStrings.appName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    AppStrings.tagline,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Version 1.0.0",
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

            const SizedBox(height: 28),

            const _InfoCard(
              icon: Icons.favorite_border_rounded,
              title: "Our Story",
              body:
                  "${AppStrings.appName} was built to give independent "
                  "artisans and small craft businesses a place to sell "
                  "directly to people who care about handmade, "
                  "one-of-a-kind work — from knitting and pottery to "
                  "woodworking and jewelry.",
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.handshake_outlined,
              title: "Our Mission",
              body:
                  "To connect makers and buyers directly, so every purchase "
                  "supports a real craftsperson and every product has a "
                  "story behind it.",
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.groups_outlined,
              title: "Who We're For",
              body:
                  "Shoppers looking for genuine handmade goods, and sellers "
                  "who want an easy way to showcase and sell their craft "
                  "— no storefront required.",
            ),

            const SizedBox(height: 24),

            const _SectionHeader(label: "LEGAL"),
            const SizedBox(height: 10),

            _LegalTile(
              icon: Icons.description_outlined,
              label: "Terms of Service",
              onTap: () => _showComingSoon(context, "Terms of Service"),
            ),
            _LegalTile(
              icon: Icons.privacy_tip_outlined,
              label: "Privacy Policy",
              onTap: () => _showComingSoon(context, "Privacy Policy"),
            ),
            _LegalTile(
              icon: Icons.gavel_outlined,
              label: "Licenses",
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppStrings.appName,
                applicationVersion: "1.0.0",
              ),
            ),

            const SizedBox(height: 24),

            const Center(
              child: Text(
                "© 2025 C+ART. All rights reserved.",
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$title will be available soon")));
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LegalTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
