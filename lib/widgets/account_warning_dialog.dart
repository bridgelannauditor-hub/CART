import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/auth_service.dart';

const _categoryLabels = {
  'inappropriate_products': 'Inappropriate products',
  'user_reports': 'Reported by users',
  'other': 'Other',
};

/// Shows each warning an administrator sent that the user has not yet
/// acknowledged. The user must tap "I understand" before continuing.
Future<void> showPendingAccountWarnings(BuildContext context) async {
  final auth = AuthService();
  final warnings = await auth.pendingWarnings();
  for (final warning in warnings) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            size: 40,
            color: Color(0xFFD97706),
          ),
          title: const Text('Account warning'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'An administrator sent you a warning about your account. '
                  'Further violations may lead to suspension.',
                ),
                const SizedBox(height: 12),
                if ((warning['categories'] as List?)?.isNotEmpty ?? false)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final c in warning['categories'] as List)
                        Chip(
                          label: Text(_categoryLabels['$c'] ?? '$c'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: const Color(0xFFFEF3C7),
                          labelStyle: const TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Text('${warning['message'] ?? ''}'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('I understand'),
            ),
          ],
        ),
      ),
    );
    await auth.acknowledgeWarning((warning['id'] as num).toInt());
  }
}
