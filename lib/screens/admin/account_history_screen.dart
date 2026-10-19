import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';
import 'suspension_dialog.dart';

/// Timeline of status changes and reviews for one account, newest first.
class AccountHistoryScreen extends StatefulWidget {
  const AccountHistoryScreen({
    super.key,
    required this.repository,
    required this.profileId,
    required this.name,
    required this.isSuspended,
  });

  final AdminRepository repository;
  final int profileId;
  final String name;
  final bool isSuspended;

  @override
  State<AccountHistoryScreen> createState() => _AccountHistoryScreenState();
}

class _AccountHistoryScreenState extends State<AccountHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.repository.accountHistory(widget.profileId);
  }

  Future<void> _refresh() async {
    final history = widget.repository.accountHistory(widget.profileId);
    setState(() => _history = history);
    await history;
  }

  /// Suspending or restoring a seller also logs a seller-access event at the
  /// same instant; show only the account event so one action is one row.
  static List<Map<String, dynamic>> _collapse(List<Map<String, dynamic>> rows) {
    final accountTimes = {
      for (final row in rows)
        if ((row['action'] as String).startsWith('account_'))
          row['occurred_at'] as String,
    };
    return [
      for (final row in rows)
        if (!((row['action'] as String).startsWith('seller_account_') &&
            accountTimes.contains(row['occurred_at'] as String)))
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account history',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              widget.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('History could not be loaded.'),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = _collapse(snapshot.data!);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusBanner(isSuspended: widget.isSuspended),
                const SizedBox(height: 16),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Center(child: Text('No history recorded yet.')),
                  )
                else
                  for (final event in events) _EventTile(event: event),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.isSuspended});
  final bool isSuspended;

  @override
  Widget build(BuildContext context) {
    final color = isSuspended ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isSuspended ? Icons.block : Icons.check_circle, color: color),
          const SizedBox(width: 10),
          Text(
            isSuspended ? 'Currently suspended' : 'Currently in good standing',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final Map<String, dynamic> event;

  static const _labels = {
    'account_warned': (
      'Warning sent',
      Icons.warning_amber_rounded,
      Color(0xFFD97706),
    ),
    'account_suspended': ('Account suspended', Icons.block, AppColors.error),
    'account_restored': (
      'Account restored',
      Icons.check_circle,
      AppColors.success,
    ),
    'seller_account_suspended': (
      'Seller access suspended',
      Icons.storefront,
      AppColors.error,
    ),
    'seller_account_active': (
      'Seller access restored',
      Icons.storefront,
      AppColors.success,
    ),
    'seller_account_revoked': (
      'Seller access revoked',
      Icons.storefront,
      AppColors.error,
    ),
    'application_submitted': (
      'Seller application submitted',
      Icons.assignment_outlined,
      AppColors.textSecondary,
    ),
    'application_approve': (
      'Seller application approved',
      Icons.verified_outlined,
      AppColors.success,
    ),
    'application_reject': (
      'Seller application rejected',
      Icons.cancel_outlined,
      AppColors.error,
    ),
    'application_appealed': (
      'Seller application appealed',
      Icons.gavel,
      AppColors.textSecondary,
    ),
    'shop_submitted': (
      'Shop details submitted',
      Icons.store_mall_directory_outlined,
      AppColors.textSecondary,
    ),
    'identity_review_resolved': (
      'Identity review resolved',
      Icons.badge_outlined,
      AppColors.textSecondary,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final action = event['action'] as String;
    final (title, icon, color) =
        _labels[action] ??
        (action.replaceAll('_', ' '), Icons.history, AppColors.textSecondary);
    final reason = event['reason'] as String?;
    final actor = event['actor_email'] as String?;
    final when = DateTime.tryParse('${event['occurred_at']}')?.toLocal();
    final actorKind = event['actor_kind'] as String?;
    final details = event['details'];
    final recorded = details is Map ? Map<String, dynamic>.from(details) : null;
    final categories = [
      if (recorded?['categories'] is List)
        for (final c in recorded!['categories'] as List) '$c',
    ];
    // What the system found when the account was suspended.
    final evidence = recorded?['evidence'];
    final evidenceLines = <String>[];
    if (evidence is Map) {
      final listing = summarizeReports(
        Map<String, dynamic>.from(evidence['listing_reports'] as Map? ?? {}),
        'listing report',
      );
      final shop = summarizeReports(
        Map<String, dynamic>.from(evidence['shop_reports'] as Map? ?? {}),
        'shop report',
      );
      if (listing != null) evidenceLines.add('Product reports: $listing');
      if (shop != null) evidenceLines.add('Shop reports: $shop');
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lightGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final category in categories)
                          Chip(
                            label: Text(
                              suspensionCategoryLabels[category] ?? category,
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: const Color(0xFFFEE2E2),
                            labelStyle: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (reason != null) ...[
                    const SizedBox(height: 4),
                    Text('Reason: $reason'),
                  ],
                  for (final line in evidenceLines) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (when != null)
                        DateFormat('MMM d, y • h:mm a').format(when),
                      if (actorKind == 'admin' && actor != null) 'by $actor',
                      if (actorKind == 'applicant') 'by the user',
                    ].join('  '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
