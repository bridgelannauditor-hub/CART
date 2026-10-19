import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Why an account is being suspended, as chosen by the administrator.
class SuspensionDecision {
  const SuspensionDecision({required this.reason, required this.categories});
  final String reason;
  final List<String> categories;
}

const suspensionCategoryLabels = {
  'inappropriate_products': 'Inappropriate products',
  'user_reports': 'Reported by users',
  'other': 'Other',
};

const _reportReasonLabels = {
  'not_handmade': 'not handmade',
  'counterfeit': 'counterfeit',
  'misleading': 'misleading',
  'scam': 'scam',
  'inappropriate': 'inappropriate',
  'impersonation': 'impersonation',
  'other': 'other',
};

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

Map<String, dynamic> _section(Map<String, dynamic> evidence, String key) {
  final value = evidence[key];
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

/// "3 reports (counterfeit ×2, misleading ×1), 2 still open" or null if none.
String? summarizeReports(Map<String, dynamic> section, String noun) {
  final total = _int(section['total']);
  if (total == 0) return null;
  final byReason = section['by_reason'];
  final reasons = byReason is Map
      ? [
          for (final entry in byReason.entries)
            '${_reportReasonLabels[entry.key] ?? entry.key} ×${entry.value}',
        ].join(', ')
      : '';
  final open = _int(section['open']);
  return '$total $noun${total == 1 ? '' : 's'}'
      '${reasons.isEmpty ? '' : ' ($reasons)'}'
      ', $open still open';
}

/// The sentence the dialog writes for a category from the evidence snapshot.
String _composeFor(String category, Map<String, dynamic> evidence) {
  switch (category) {
    case 'inappropriate_products':
      final summary = summarizeReports(
        _section(evidence, 'listing_reports'),
        'listing report',
      );
      return summary == null
          ? 'Inappropriate products.'
          : 'Inappropriate products: $summary.';
    case 'user_reports':
      final summary = summarizeReports(
        _section(evidence, 'shop_reports'),
        'shop report',
      );
      return summary == null
          ? 'Reported by other users.'
          : 'Reported by users: $summary.';
    default:
      return '';
  }
}

/// Asks an administrator to confirm a suspension. The evidence (reports found
/// against the account) selects the suggested categories and writes a first
/// draft of the reason, but the administrator makes the decision and can edit.
Future<SuspensionDecision?> showSuspensionDialog(
  BuildContext context, {
  required String name,
  required Map<String, dynamic> evidence,
  bool warning = false,
}) {
  return showDialog<SuspensionDecision>(
    context: context,
    builder: (_) =>
        _SuspensionDialog(name: name, evidence: evidence, warning: warning),
  );
}

enum WarnFirstChoice { warn, suspendAnyway }

/// Shown before suspending an account that has never been warned.
Future<WarnFirstChoice?> showWarnFirstDialog(
  BuildContext context, {
  required String name,
}) {
  return showDialog<WarnFirstChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Send a warning first?'),
      content: Text(
        '$name has not been warned. A warning lets them fix the problem '
        'before losing access. You can still suspend right away if the '
        'violation is serious.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, WarnFirstChoice.suspendAnyway),
          child: const Text(
            'Suspend anyway',
            style: TextStyle(color: AppColors.error),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, WarnFirstChoice.warn),
          child: const Text('Send warning'),
        ),
      ],
    ),
  );
}

class _SuspensionDialog extends StatefulWidget {
  const _SuspensionDialog({
    required this.name,
    required this.evidence,
    required this.warning,
  });
  final String name;
  final Map<String, dynamic> evidence;
  final bool warning;

  @override
  State<_SuspensionDialog> createState() => _SuspensionDialogState();
}

class _SuspensionDialogState extends State<_SuspensionDialog> {
  final _controller = TextEditingController();
  late final Set<String> _categories;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    final suggested = widget.evidence['suggested_categories'];
    _categories = {
      if (suggested is List)
        for (final c in suggested)
          if (suspensionCategoryLabels.containsKey(c)) c as String,
    };
    _controller.text = _draft();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _draft() {
    final text = [
      for (final category in suspensionCategoryLabels.keys)
        if (_categories.contains(category))
          _composeFor(category, widget.evidence),
    ].where((s) => s.isNotEmpty).join(' ');
    final drafted = widget.warning && text.isNotEmpty
        ? '$text Further violations may lead to suspension.'
        : text;
    return drafted.length > 500 ? drafted.substring(0, 500) : drafted;
  }

  void _toggle(String category, bool selected) {
    setState(() {
      selected ? _categories.add(category) : _categories.remove(category);
      // Keep the written draft in step until the administrator edits it.
      if (!_edited) _controller.text = _draft();
    });
  }

  @override
  Widget build(BuildContext context) {
    final listing = summarizeReports(
      _section(widget.evidence, 'listing_reports'),
      'listing report',
    );
    final shop = summarizeReports(
      _section(widget.evidence, 'shop_reports'),
      'shop report',
    );
    final reason = _controller.text.trim();
    final valid =
        _categories.isNotEmpty && reason.length >= 3 && reason.length <= 500;
    final warned = _int(_section(widget.evidence, 'warnings')['total']);
    final accent = widget.warning ? const Color(0xFFD97706) : AppColors.error;
    return AlertDialog(
      title: Text(
        widget.warning ? 'Warn ${widget.name}?' : 'Suspend ${widget.name}?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.lightGrey),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Found automatically',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (listing == null && shop == null)
                    const Text(
                      'No reports against this account. Choose a category and '
                      'explain the reason.',
                    ),
                  if (listing != null) Text('Product reports: $listing'),
                  if (shop != null) Text('Shop reports: $shop'),
                  Text(
                    warned == 0
                        ? 'Previous warnings: none'
                        : 'Previous warnings: $warned',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in suspensionCategoryLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _categories.contains(entry.key),
                    onSelected: (selected) => _toggle(entry.key, selected),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) => setState(() => _edited = true),
              decoration: InputDecoration(
                hintText: widget.warning
                    ? 'Tell the user what to fix'
                    : 'Explain why this account is being suspended',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: valid
              ? () => Navigator.pop(
                  context,
                  SuspensionDecision(
                    reason: reason,
                    categories: _categories.toList(),
                  ),
                )
              : null,
          child: Text(widget.warning ? 'Send warning' : 'Suspend'),
        ),
      ],
    );
  }
}
