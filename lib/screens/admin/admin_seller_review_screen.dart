import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';

/// Admin queue for Seller applications. Visibility here is a convenience; the
/// server rejects every action from a non-admin.
class AdminSellerReviewScreen extends StatefulWidget {
  const AdminSellerReviewScreen({super.key});

  @override
  State<AdminSellerReviewScreen> createState() =>
      _AdminSellerReviewScreenState();
}

class _AdminSellerReviewScreenState extends State<AdminSellerReviewScreen> {
  final _repository = AdminRepository();
  String? _filter = 'under_review';
  List<Map<String, dynamic>>? _rows;
  String? _error;
  int? _busyProfileId;

  static const _rejectReasons = {
    'policy_violation': 'Violates Seller policy',
    'prohibited_items': 'Prohibited items',
    'shop_details_incomplete': 'Shop details incomplete',
    'document_unsupported': 'ID not accepted',
    'document_expired': 'ID expired',
    'face_mismatch': 'Selfie does not match ID',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await _repository.listSellerApplications(status: _filter);
      if (mounted) setState(() => _rows = rows);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == '42501'
              ? 'Administrator access is required.'
              : 'Applications could not be loaded.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Applications could not be loaded.');
    }
  }

  Future<String?> _pickReason(String title) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final entry in _rejectReasons.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
  }

  Future<void> _run(int profileId, Future<void> Function() action) async {
    setState(() => _busyProfileId = profileId);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved.')));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
      await _load();
    }
  }

  Future<void> _decide(Map<String, dynamic> row, String decision) async {
    String? reason;
    if (decision != 'approve') {
      reason = await _pickReason(
        decision == 'reject' ? 'Reject because' : 'Request changes because',
      );
      if (reason == null) return;
    }
    await _run(
      row['profile_id'] as int,
      () => _repository.reviewApplication(
        profileId: row['profile_id'] as int,
        revision: row['revision'] as int,
        decision: decision,
        reasonCode: reason,
      ),
    );
  }

  Future<void> _resolveIdentity(Map<String, dynamic> row, bool verified) async {
    final reason = verified
        ? 'manual_review_passed'
        : await _pickReason('Identity failed because');
    if (reason == null) return;
    await _run(
      row['profile_id'] as int,
      () => _repository.resolveIdentityReview(
        profileId: row['profile_id'] as int,
        verified: verified,
        reasonCode: reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Seller Applications')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final entry in const {
                  'under_review': 'In review',
                  'appealed': 'Appeals',
                  'approved': 'Approved',
                  'rejected': 'Rejected',
                  null: 'All',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _filter == entry.key,
                      onSelected: (_) {
                        setState(() {
                          _filter = entry.key;
                          _rows = null;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) return Center(child: Text(_error!));
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return const Center(child: Text('No applications.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _card(rows[index]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final busy = _busyProfileId == row['profile_id'];
    final reviewable =
        row['status'] == 'under_review' || row['status'] == 'appealed';
    final canApprove =
        reviewable &&
        row['identity_status'] == 'verified' &&
        row['shop_status'] == 'submitted';
    final identityNeedsReview = row['identity_status'] == 'under_review';

    String line(String label, Object? value) =>
        '$label: ${value == null || value == '' ? '—' : value}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row['applicant_name']} · ${row['seller_type']}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          Text(
            row['applicant_email'] as String? ?? '',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            line('Application', '${row['status']} (rev ${row['revision']})'),
          ),
          Text(
            line(
              'Identity',
              '${row['identity_status']} · ${row['identity_attempts']} attempt(s)',
            ),
          ),
          Text(
            line('Shop', '${row['shop_status']} · ${row['shop_name'] ?? '—'}'),
          ),
          Text(line('Craft', row['shop_category'])),
          Text(line('City', row['shop_city'])),
          if (row['organization_name'] != null)
            Text(
              line(
                'Business',
                '${row['organization_name']} · ${row['business_registration_number']}',
              ),
            ),
          if ((row['shop_description'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(
              row['shop_description'] as String,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (row['appeal_message'] != null && row['status'] == 'appealed') ...[
            const SizedBox(height: 6),
            Text('Appeal: ${row['appeal_message']}'),
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (identityNeedsReview) ...[
                  FilledButton(
                    onPressed: () => _resolveIdentity(row, true),
                    child: const Text('Identity OK'),
                  ),
                  OutlinedButton(
                    onPressed: () => _resolveIdentity(row, false),
                    child: const Text('Identity failed'),
                  ),
                ],
                if (reviewable) ...[
                  FilledButton(
                    onPressed: canApprove
                        ? () => _decide(row, 'approve')
                        : null,
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: () => _decide(row, 'request_changes'),
                    child: const Text('Request changes'),
                  ),
                  TextButton(
                    onPressed: () => _decide(row, 'reject'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    child: const Text('Reject'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
