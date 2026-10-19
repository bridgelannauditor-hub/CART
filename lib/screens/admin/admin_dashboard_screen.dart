import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import 'account_history_screen.dart';
import 'admin_seller_review_screen.dart';
import 'admin_reports_screen.dart';
import 'account_actions.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repository = AdminRepository();
  late Future<bool> _access;

  @override
  void initState() {
    super.initState();
    _access = _repository.isAdmin();
  }

  Future<void> _logout() async {
    await SessionService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Administrator')),
            body: const Center(
              child: Text('Administrator access is required.'),
            ),
          );
        }
        return _AdminHome(repository: _repository, onLogout: _logout);
      },
    );
  }
}

class _AdminHome extends StatefulWidget {
  const _AdminHome({required this.repository, required this.onLogout});

  final AdminRepository repository;
  final Future<void> Function() onLogout;

  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  late Future<Map<String, dynamic>> _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.repository.dashboardSummary();
  }

  Future<void> _refresh() async {
    final summary = widget.repository.dashboardSummary();
    setState(() => _summary = summary);
    await summary;
  }

  void _open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('C+ART Admin', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'Marketplace control center',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Live marketplace activity and moderation queues.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            FutureBuilder<Map<String, dynamic>>(
              future: _summary,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _ErrorCard(onRetry: _refresh);
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return _OverviewCharts(data: snapshot.data!);
              },
            ),
            const SizedBox(height: 28),
            const Text(
              'Management',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _AdminAction(
              icon: Icons.verified_user_outlined,
              title: 'Seller applications',
              subtitle:
                  'Review identity results, shop details, approvals, and appeals.',
              onTap: () => _open(const AdminSellerReviewScreen()),
            ),
            _AdminAction(
              icon: Icons.manage_accounts_outlined,
              title: 'User directory',
              subtitle:
                  'Search customers and sellers and review account status.',
              onTap: () =>
                  _open(AdminUsersScreen(repository: widget.repository)),
            ),
            _AdminAction(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Reports',
              subtitle:
                  'Review reported products and stores, then warn or suspend.',
              onTap: () =>
                  _open(AdminReportsScreen(repository: widget.repository)),
            ),
          ],
        ),
      ),
    );
  }
}

int _count(Object? value) => (value as num?)?.toInt() ?? 0;

class _OverviewCharts extends StatelessWidget {
  const _OverviewCharts({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final active = _count(data['active_sellers']);
    final pending = _count(data['pending_applications']);
    final reports = _count(data['open_reports']);
    return Column(
      children: [
        _ChartPanel(
          title: 'Marketplace size',
          child: _HorizontalBars(
            bars: [
              _BarData('Users', _count(data['users']), AppColors.primary),
              _BarData(
                'Products',
                _count(data['products']),
                AppColors.secondary,
              ),
              _BarData('Orders', _count(data['orders']), AppColors.dark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ChartPanel(
          title: 'Sellers',
          child: _SellerDonut(active: active, pending: pending),
        ),
        const SizedBox(height: 12),
        _ChartPanel(
          title: 'Needs attention',
          child: _HorizontalBars(
            bars: [
              _BarData('Pending sellers', pending, AppColors.secondary),
              _BarData('Open reports', reports, AppColors.error),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _BarData {
  const _BarData(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({required this.bars});
  final List<_BarData> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<int>(
      1,
      (m, bar) => bar.value > m ? bar.value : m,
    );
    return Column(
      children: [
        for (final bar in bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    bar.label,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fraction = bar.value / maxValue;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(end: fraction),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, t, _) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: bar.value == 0
                                ? 4
                                : (constraints.maxWidth * t).clamp(
                                    4,
                                    double.infinity,
                                  ),
                            height: 22,
                            decoration: BoxDecoration(
                              color: bar.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${bar.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SellerDonut extends StatelessWidget {
  const _SellerDonut({required this.active, required this.pending});
  final int active;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final total = active + pending;
    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              painter: _DonutPainter(
                values: [active.toDouble(), pending.toDouble()],
                colors: const [AppColors.primary, AppColors.secondary],
                progress: t,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'sellers',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendRow(AppColors.primary, 'Active', active),
              const SizedBox(height: 10),
              _LegendRow(AppColors.secondary, 'Pending applications', pending),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(this.color, this.label, this.value);
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
      Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.progress,
  });
  final List<double> values;
  final List<Color> colors;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.lightGrey;
    canvas.drawArc(arcRect, 0, 6.283185307179586, false, track);

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    var start = -1.5707963267948966;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * 6.283185307179586 * progress;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = colors[i];
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.values.length != values.length ||
      !_sameValues(old.values, values);

  bool _sameValues(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _AdminAction extends StatelessWidget {
  const _AdminAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.lightGrey),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.lightGrey,
        foregroundColor: AppColors.primary,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.error_outline, color: AppColors.error),
      title: const Text('Admin data could not be loaded.'),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.repository});
  final AdminRepository repository;
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  String? _error;

  Widget? _trailingFor(Map<String, dynamic> row) {
    if (row['is_admin'] == true) return const Chip(label: Text('Admin'));
    final suspended = row['is_suspended'] == true;
    return PopupMenuButton<String>(
      tooltip: 'Account actions',
      onSelected: (action) {
        if (action == 'history') {
          _openHistory(row, suspended);
        } else {
          _changeSuspension(row, action);
        }
      },
      itemBuilder: (_) => [
        if (suspended)
          const PopupMenuItem(value: 'restore', child: Text('Restore account'))
        else ...const [
          PopupMenuItem(value: 'warn', child: Text('Send warning')),
          PopupMenuItem(value: 'suspend', child: Text('Suspend account')),
        ],
        const PopupMenuItem(value: 'history', child: Text('View history')),
      ],
      child: suspended
          ? const Chip(
              label: Text('Suspended'),
              backgroundColor: Color(0xFFFEE2E2),
              labelStyle: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            )
          : row['is_verified_seller'] == true
          ? const Chip(label: Text('Verified'))
          : const Icon(Icons.more_vert),
    );
  }

  void _openHistory(Map<String, dynamic> row, bool suspended) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountHistoryScreen(
          repository: widget.repository,
          profileId: row['profile_id'] as int,
          name: '${row['first_name']} ${row['last_name']}'.trim(),
          isSuspended: suspended,
        ),
      ),
    );
  }

  /// [action] is 'warn', 'suspend' or 'restore'.
  Future<void> _changeSuspension(
    Map<String, dynamic> row,
    String action,
  ) async {
    final changed = await runAccountAction(
      context,
      repository: widget.repository,
      profileId: row['profile_id'] as int,
      name: '${row['first_name']} ${row['last_name']}'.trim(),
      action: action,
    );
    if (changed && mounted) await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.repository.listProfiles(
        query: _search.text.trim(),
      );
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Users could not be loaded.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('User Directory')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search name, email, or shop',
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _rows == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _rows!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final row = _rows![i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            '${row['first_name'] ?? '?'}'
                                .substring(0, 1)
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          '${row['first_name']} ${row['last_name']}'.trim(),
                        ),
                        subtitle: Text(
                          '${row['email']}\n${row['account_type']}${row['shop_name'] == null ? '' : ' • ${row['shop_name']}'}',
                        ),
                        isThreeLine: true,
                        trailing: _trailingFor(row),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
