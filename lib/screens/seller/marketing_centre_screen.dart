import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'flash_sales_screen.dart';
import 'follower_vouchers_screen.dart';

/// Seller promotion tools. Promotions live here rather than on the product
/// form so a product is published first and promoted once it has a record.
class MarketingCentreScreen extends StatelessWidget {
  const MarketingCentreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F5),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Marketing Centre',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ToolTile(
            icon: Icons.bolt_rounded,
            title: 'Flash Sale',
            subtitle:
                'Run a short, scheduled discount on a proven product with its '
                'own promo stock and purchase limit.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FlashSalesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ToolTile(
            icon: Icons.local_offer_outlined,
            title: 'Followers & Vouchers',
            subtitle: 'Reward new shop followers with a voucher.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FollowerVouchersScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
