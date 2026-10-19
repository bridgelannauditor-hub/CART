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
    'details_mismatch': "Details don't match the ID",
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

  Future<void> _viewIdPhotos(Map<String, dynamic> row) async {
    final profileId = row['profile_id'] as int;
    setState(() => _busyProfileId = profileId);
    Map<String, String> urls;
    try {
      urls = await _repository.identityPhotoUrls(profileId);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The photos could not be loaded.')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
    if (!mounted) return;

    const labels = {'front': 'ID front', 'back': 'ID back', 'selfie': 'Selfie'};
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Identity photos · ${row['applicant_name']}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pinch to zoom. These links expire in two minutes.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Name: ${row['first_name'] ?? '—'} ${row['last_name'] ?? ''}',
                    ),
                    Text('Birthdate: ${row['birth_date'] ?? '—'}'),
                    Text('Address: ${row['address'] ?? '—'}'),
                    Text('ID type: ${row['identity_document_type'] ?? '—'}'),
                  ],
                ),
              ),
              for (final entry in labels.entries)
                if (urls[entry.key] != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    entry.value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Image.network(
                        urls[entry.key]!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const SizedBox(
                                height: 160,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 80,
                          child: Center(child: Text('Could not load photo')),
                        ),
                      ),
                    ),
                  ),
                ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _askRetake(Map<String, dynamic> row) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ask to retake because'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'image_blurry'),
            child: const Text('ID photo is unclear'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'liveness_failed'),
            child: const Text('Selfie is unclear'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await _run(
      row['profile_id'] as int,
      () => _repository.requestIdentityRetry(
        profileId: row['profile_id'] as int,
        reasonCode: reason,
      ),
    );
  }

  /// Approving identity is a deliberate confirmation that the submitted
  /// details were compared with the ID photos.
  Future<void> _confirmMatch(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm details match the ID'),
        content: Text(
          'Name: ${row['first_name'] ?? '—'} ${row['last_name'] ?? ''}\n'
          'Birthdate: ${row['birth_date'] ?? '—'}\n'
          'Address: ${row['address'] ?? '—'}\n\n'
          'Only continue if you checked every detail above against the '
          'ID photos and the selfie matches the ID.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('They match'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resolveIdentity(row, true);
  }

  Future<void> _resolveIdentity(Map<String, dynamic> row, bool verified) async {
    final reason = verified
        ? 'manual_review_passed'
        : await _pickReason('Reject because');
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
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Submitted details (compare with ID)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  line(
                    'Name',
                    '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'
                        .trim(),
                  ),
                ),
                Text(line('Birthdate', row['birth_date'])),
                Text(line('Address', row['address'])),
                Text(line('ID type', row['identity_document_type'])),
                Text(line('Payout account name', row['payout_account_name'])),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
                  OutlinedButton.icon(
                    onPressed: () => _viewIdPhotos(row),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('View ID photos'),
                  ),
                  OutlinedButton(
                    onPressed: () => _askRetake(row),
                    child: const Text('Ask to retake'),
                  ),
                  FilledButton(
                    onPressed: () => _confirmMatch(row),
                    child: const Text('Details match ID'),
                  ),
                  OutlinedButton(
                    onPressed: () => _resolveIdentity(row, false),
                    child: const Text("Doesn't match"),
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
