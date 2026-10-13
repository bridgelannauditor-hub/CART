import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../utils/routes.dart';
import '../../widgets/custom_logo.dart';

class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  void _continue(BuildContext context, String accountType) {
    Navigator.pushNamed(
      context,
      AppRoutes.registerDetails,
      arguments: accountType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to login',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: CustomLogo()),
                  const SizedBox(height: 8),
                  const Text(
                    'How will you use C+ART?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Every account starts as a customer. After signing in, you can apply to open a shop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _AccountCard(
                    icon: Icons.shopping_bag_outlined,
                    title: 'To buy',
                    description:
                        'Discover handmade crafts, place orders, and follow your favorite sellers.',
                    buttonLabel: 'CONTINUE AS CUSTOMER',
                    onTap: () => _continue(context, 'Customer'),
                  ),
                  const SizedBox(height: 16),
                  _AccountCard(
                    icon: Icons.storefront_outlined,
                    title: 'To sell',
                    description:
                        'Create your customer account first, then submit a separate seller application from your profile.',
                    buttonLabel: 'CREATE ACCOUNT TO APPLY',
                    emphasized: true,
                    onTap: () => _continue(context, 'Customer'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.login,
                    ),
                    child: const Text('Already have an account? Log in'),
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

class _AccountCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final bool emphasized;
  final VoidCallback onTap;

  const _AccountCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized
          ? AppColors.primary.withValues(alpha: .045)
          : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: emphasized
                  ? AppColors.primary.withValues(alpha: .45)
                  : AppColors.lightGrey,
              width: emphasized ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 27),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 17),
              SizedBox(
                width: double.infinity,
                child: emphasized
                    ? FilledButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(buttonLabel),
                      )
                    : OutlinedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(buttonLabel),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
