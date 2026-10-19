import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';
import '../../widgets/product_image.dart';
import 'account_actions.dart';
import 'account_history_screen.dart';

const _reasonLabels = {
  'not_handmade': 'Not handmade',
  'counterfeit': 'Counterfeit',
  'misleading': 'Misleading',
  'scam': 'Scam',
  'inappropriate': 'Inappropriate',
  'impersonation': 'Impersonation',
  'other': 'Other',
};

const _statusLabels = {
  'open': 'Open',
  'reviewing': 'Reviewing',
  'resolved': 'Resolved',
  'dismissed': 'Dismissed',
};

Color _statusColor(String status) => switch (status) {
  'open' => AppColors.error,
  'reviewing' => const Color(0xFFD97706),
  'resolved' => AppColors.success,
  _ => AppColors.textSecondary,
};

/// Moderation queue for reports against products and stores.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, required this.repository});
  final AdminRepository repository;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  // 'listing' (products) or 'shop' (stores).
  String _kind = 'listing';
  String? _status = 'open';
  List<Map<String, dynamic>>? _rows;
  Map<String, dynamic> _counts = const {};
  String? _error;
  int? _busy;

  bool get _isListing => _kind == 'listing';

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _count(String kind, String status) {
    final section = _counts[kind];
    return section is Map ? (section[status] as num?)?.toInt() ?? 0 : 0;
  }

  int _openTotal(String kind) =>
      _count(kind, 'open') + _count(kind, 'reviewing');

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _isListing
            ? widget.repository.listListingReports(status: _status)
            : widget.repository.listShopReports(status: _status),
        widget.repository.reportCounts().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<Map<String, dynamic>>;
        _counts = results[1] as Map<String, dynamic>;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Reports could not be loaded.');
    }
  }

  Future<void> _setStatus(int id, String status) async {
    setState(() => _busy = id);
    try {
      if (_isListing) {
        await widget.repository.updateListingReport(
          reportId: id,
          status: status,
        );
      } else {
        await widget.repository.updateShopReport(reportId: id, status: status);
      }
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _takeAction(Map<String, dynamic> row, String action) async {
    final sellerId = (_isListing ? row['seller_id'] : row['shop_id']) as int;
    final name =
        (_isListing ? row['seller_name'] : row['shop_name']) as String? ??
        'this seller';
    if (action == 'history') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountHistoryScreen(
            repository: widget.repository,
            profileId: sellerId,
            name: name,
            isSuspended: false,
          ),
        ),
      );
      return;
    }
    await runAccountAction(
      context,
      repository: widget.repository,
      profileId: sellerId,
      name: name,
      action: action,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F5),
      appBar: AppBar(
        title: const Text(
          'Reports',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 'listing',
                    label: Text('Products (${_openTotal('listing')})'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: 'shop',
                    label: Text('Stores (${_openTotal('shop')})'),
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) {
                  setState(() {
                    _kind = value.first;
                    _rows = null;
                  });
                  _load();
                },
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                for (final entry in _statusLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${entry.value} (${_count(_kind, entry.key)})',
                      ),
                      selected: _status == entry.key,
                      onSelected: (_) {
                        setState(() {
                          _status = entry.key;
                          _rows = null;
                        });
                        _load();
                      },
                    ),
                  ),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _status == null,
                  onSelected: (_) {
                    setState(() {
                      _status = null;
                      _rows = null;
                    });
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _rows == null
                ? const Center(child: CircularProgressIndicator())
                : _rows!.isEmpty
                ? Center(
                    child: Text(
                      _status == 'open'
                          ? 'No open reports. Nice and quiet.'
                          : 'No reports here.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rows!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ReportCard(
                        row: _rows![i],
                        isListing: _isListing,
                        busy: _busy == _rows![i]['report_id'],
                        onStatus: (status) =>
                            _setStatus(_rows![i]['report_id'] as int, status),
                        onAction: (action) => _takeAction(_rows![i], action),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.row,
    required this.isListing,
    required this.busy,
    required this.onStatus,
    required this.onAction,
  });

  final Map<String, dynamic> row;
  final bool isListing;
  final bool busy;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String? ?? 'open';
    final reason = row['reason'] as String? ?? 'other';
    final details = (row['details'] as String?)?.trim() ?? '';
    final title = isListing
        ? (row['product_name'] as String? ?? 'Product #${row['product_id']}')
        : (row['shop_name'] as String? ?? 'Store #${row['shop_id']}');
    final subtitle = isListing
        ? 'Seller: ${row['seller_name'] ?? '—'}'
        : 'Store report';
    final image = isListing ? (row['product_image'] as String? ?? '') : '';
    final when = DateTime.tryParse('${row['created_at']}')?.toLocal();
    final closed = status == 'resolved' || status == 'dismissed';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lightGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: image.isEmpty
                        ? Container(
                            color: AppColors.lightGrey,
                            child: Icon(
                              isListing
                                  ? Icons.inventory_2_outlined
                                  : Icons.storefront_outlined,
                              color: AppColors.primary,
                            ),
                          )
                        : ProductImage(
                            path: image,
                            placeholder: Container(color: AppColors.lightGrey),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Pill(
                            label: _reasonLabels[reason] ?? reason,
                            color: AppColors.primary,
                          ),
                          _Pill(
                            label: _statusLabels[status] ?? status,
                            color: _statusColor(status),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Reported by ${row['reporter_name'] ?? 'a user'}'
              '${when == null ? '' : ' • ${DateFormat('MMM d, y • h:mm a').format(when)}'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(details),
                ),
              ),
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (status == 'open')
                    OutlinedButton(
                      onPressed: () => onStatus('reviewing'),
                      child: const Text('Reviewing'),
                    ),
                  if (!closed)
                    FilledButton(
                      onPressed: () => onStatus('resolved'),
                      child: const Text('Resolve'),
                    ),
                  if (!closed)
                    TextButton(
                      onPressed: () => onStatus('dismissed'),
                      child: const Text('Dismiss'),
                    ),
                  if (closed)
                    TextButton(
                      onPressed: () => onStatus('open'),
                      child: const Text('Reopen'),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Take action on the seller',
                    onSelected: onAction,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'warn', child: Text('Warn seller')),
                      PopupMenuItem(
                        value: 'suspend',
                        child: Text('Suspend seller'),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: Text('View seller history'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Take action',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
