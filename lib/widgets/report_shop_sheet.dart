import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_colors.dart';
import '../repositories/moderation_repository.dart';

const _reasons = <(String, String)>[
  ('not_handmade', 'Not handmade / mass-produced'),
  ('scam', 'Scam or fraud'),
  ('inappropriate', 'Inappropriate content'),
  ('impersonation', 'Impersonating someone else'),
  ('other', 'Something else'),
];

/// Bottom sheet that lets a buyer report a shop, then submits the report and
/// shows the outcome in a snackbar.
Future<void> showReportShopSheet(
  BuildContext context, {
  required int shopId,
  required int reporterId,
  required String shopName,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  final result = await showModalBottomSheet<({String reason, String details})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportShopSheet(shopName: shopName),
  );
  if (result == null) return;

  String message;
  try {
    await ModerationRepository().reportShop(
      shopId: shopId,
      reporterId: reporterId,
      reason: result.reason,
      details: result.details,
    );
    message = 'Report sent to moderation. Thank you.';
  } on PostgrestException catch (error) {
    message = error.code == '23505'
        ? 'You already reported this shop for that reason.'
        : 'Could not send the report. Please try again later.';
  } catch (_) {
    message = 'Could not send the report. Please try again later.';
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _ReportShopSheet extends StatefulWidget {
  final String shopName;

  const _ReportShopSheet({required this.shopName});

  @override
  State<_ReportShopSheet> createState() => _ReportShopSheetState();
}

class _ReportShopSheetState extends State<_ReportShopSheet> {
  String? _reason;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Report ${widget.shopName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Why are you reporting this store?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final (value, label) in _reasons)
                    RadioListTile<String>(
                      value: value,
                      title: Text(label),
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              maxLength: 1000,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add details (optional)',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _reason == null
                    ? null
                    : () => Navigator.pop(context, (
                        reason: _reason!,
                        details: _details.text,
                      )),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Send report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
