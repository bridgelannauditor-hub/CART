import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';

/// Static FAQ + contact info screen. No backend ticketing system
/// exists yet, so "Contact Us" surfaces the ways to reach support
/// rather than opening a live chat.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    (
      "How do I place an order?",
      "Browse a shop or product, tap \"Add to Cart\", then go to your "
          "cart and tap Checkout. Confirm your delivery address and "
          "payment method to place the order.",
    ),
    (
      "How can I track my order?",
      "Open the Orders tab from the bottom navigation to see the "
          "status of every order you've placed, from Pending to "
          "Delivered.",
    ),
    (
      "Can I cancel an order?",
      "Orders that are still Pending can usually be cancelled by "
          "messaging the seller directly from the order details. Once "
          "an order ships, cancellation depends on the seller.",
    ),
    (
      "How do refunds work?",
      "Refund policies are set by each individual seller/shop. Message "
          "the shop directly from the product page or your order to "
          "start a return or refund request.",
    ),
    (
      "How do I become a seller on ${AppStrings.appName}?",
      "Stay signed in to your customer account, open Profile, and select "
          "\"Become a Seller.\" You can keep shopping while identity "
          "verification and administrator review are in progress.",
    ),
    (
      "Is my payment information safe?",
      "${AppStrings.appName} never stores full card details on this "
          "device. Always avoid sharing your password or one-time "
          "codes with anyone, including people claiming to be C+ART "
          "staff.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Help & Support",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            const Text(
              "FREQUENTLY ASKED QUESTIONS",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            Container(
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
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: Column(
                  children: [
                    for (int i = 0; i < _faqs.length; i++) ...[
                      _FaqTile(question: _faqs[i].$1, answer: _faqs[i].$2),
                      if (i != _faqs.length - 1)
                        const Divider(
                          height: 1,
                          thickness: 0.6,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.lightGrey,
                        ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "CONTACT US",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            const _ContactCard(
              icon: Icons.email_outlined,
              title: "Email Support",
              subtitle: "support@cplusart.app",
            ),
            const SizedBox(height: 10),
            const _ContactCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: "Message a Shop",
              subtitle:
                  "For order-specific issues, message the seller directly "
                  "from the product or order page.",
            ),
            const SizedBox(height: 10),
            const _ContactCard(
              icon: Icons.schedule_outlined,
              title: "Support Hours",
              subtitle: "Monday – Saturday, 9:00 AM – 6:00 PM (PH Time)",
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.textSecondary,
      title: Text(
        question,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answer,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
