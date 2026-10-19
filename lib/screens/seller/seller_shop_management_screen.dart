import 'marketing_centre_screen.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/seller_order_item_model.dart';
import '../../repositories/order_repository.dart';
import '../../services/session_service.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class SellerShopManagementScreen extends StatefulWidget {
  const SellerShopManagementScreen({super.key});

  @override
  State<SellerShopManagementScreen> createState() =>
      _SellerShopManagementScreenState();
}

class _SellerShopManagementScreenState
    extends State<SellerShopManagementScreen> {
  final _orders = OrderRepository();
  late Future<List<SellerOrderItemModel>> _future;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  // false: revenue from delivered orders only; true: also orders in progress.
  bool _includeInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final sellerId = SessionService.userId;
    _future = sellerId == null
        ? Future.value(const [])
        : _orders.getSellerOrderItemsForPeriod(
            sellerId,
            start: DateTime(_year - 1, 12),
            end: DateTime(_year + 1),
          );
  }

  void _changeYear(int value) {
    setState(() {
      _year = value;
      _load();
    });
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F5),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              label: const Text('Marketing Centre'),
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MarketingCentreScreen(),
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Shop Management',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: FutureBuilder<List<SellerOrderItemModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _refresh);
            }
            return _AnalyticsBody(
              orders: snapshot.data ?? const [],
              year: _year,
              month: _month,
              includeInProgress: _includeInProgress,
              onYearChanged: _changeYear,
              onMonthChanged: (value) => setState(() => _month = value),
              onBasisChanged: (value) =>
                  setState(() => _includeInProgress = value),
            );
          },
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final List<SellerOrderItemModel> orders;
  final int year;
  final int month;
  final bool includeInProgress;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<bool> onBasisChanged;

  const _AnalyticsBody({
    required this.orders,
    required this.year,
    required this.month,
    required this.includeInProgress,
    required this.onYearChanged,
    required this.onMonthChanged,
    required this.onBasisChanged,
  });

  static const _inProgressStatuses = {
    'pending',
    'preparing',
    'shipped',
    'out for delivery',
  };

  /// Whether an order line counts towards revenue on the chosen basis.
  bool _counts(SellerOrderItemModel order) {
    final status = order.status.toLowerCase();
    return status == 'delivered' ||
        (includeInProgress && _inProgressStatuses.contains(status));
  }

  @override
  Widget build(BuildContext context) {
    final monthlyRevenue = List<double>.filled(12, 0);
    final monthlyOrderIds = List.generate(12, (_) => <int>{});
    final days = DateTime(year, month + 1, 0).day;
    final dailyRevenue = List<double>.filled(days, 0);
    final productRevenue = <String, double>{};
    final productUnits = <String, int>{};
    // Orders in the chosen month by status (an order is counted once; all of
    // a seller's items in one order share a status).
    final statusOrderIds = <String, Set<int>>{};
    var inProgressValue = 0.0;

    final now = DateTime.now();
    final previousMonth = month == 1 ? 12 : month - 1;
    final previousYear = month == 1 ? year - 1 : year;
    final isCurrentMonth = year == now.year && month == now.month;
    final previousMonthDays = DateTime(previousYear, previousMonth + 1, 0).day;
    final comparisonDay = now.day < previousMonthDays
        ? now.day
        : previousMonthDays;
    var previousRevenue = 0.0;

    for (final order in orders) {
      // Bucket by the seller's local calendar, not UTC, so an order placed
      // late on the last day of a month is not counted in the next one.
      final date = DateTime.tryParse(order.orderDate)?.toLocal();
      if (date == null) continue;
      final inChosenMonth = date.year == year && date.month == month;
      final status = order.status.toLowerCase();
      if (inChosenMonth) {
        (statusOrderIds[order.status] ??= <int>{}).add(order.orderId);
        if (_inProgressStatuses.contains(status)) {
          inProgressValue += order.lineTotal;
        }
      }
      if (!_counts(order)) continue;
      if (date.year == year) {
        monthlyRevenue[date.month - 1] += order.lineTotal;
        monthlyOrderIds[date.month - 1].add(order.orderId);
      }
      if (inChosenMonth) {
        dailyRevenue[date.day - 1] += order.lineTotal;
        productRevenue[order.productName] =
            (productRevenue[order.productName] ?? 0) + order.lineTotal;
        productUnits[order.productName] =
            (productUnits[order.productName] ?? 0) + order.quantity;
      }
      if (date.year == previousYear &&
          date.month == previousMonth &&
          (!isCurrentMonth || date.day <= comparisonDay)) {
        previousRevenue += order.lineTotal;
      }
    }

    final monthlyOrders = [for (final ids in monthlyOrderIds) ids.length];
    final currentYear = now.year;
    final sortedYears = List<int>.generate(10, (index) => currentYear - index);
    final monthRevenue = monthlyRevenue[month - 1];
    final yearlyRevenue = monthlyRevenue.fold<double>(0, (a, b) => a + b);
    final monthOrderCount = monthlyOrders[month - 1];
    final averageOrder = monthOrderCount == 0
        ? 0.0
        : monthRevenue / monthOrderCount;
    final change = previousRevenue == 0
        ? null
        : (monthRevenue - previousRevenue) / previousRevenue * 100;
    final products = productRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final inProgressOrders = {
      for (final status in _inProgressStatuses)
        ...?statusOrderIds[_titleCase(status)],
    }.length;
    final cancelledOrders = statusOrderIds['Cancelled']?.length ?? 0;
    var bestDay = 0;
    for (var i = 0; i < days; i++) {
      if (dailyRevenue[i] > dailyRevenue[bestDay]) bestDay = i;
    }
    final basisLabel = includeInProgress
        ? 'delivered and in-progress orders'
        : 'confirmed delivered orders';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        const Text(
          'Sales analytics',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Revenue from $basisLabel.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Selector(
                value: month,
                items: {for (var i = 0; i < 12; i++) i + 1: _months[i]},
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Selector(
                value: year,
                items: {for (final value in sortedYears) value: '$value'},
                onChanged: onYearChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Delivered only')),
              ButtonSegment(value: true, label: Text('Incl. in progress')),
            ],
            selected: {includeInProgress},
            onSelectionChanged: (value) => onBasisChanged(value.first),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: '${_months[month - 1]} revenue',
                value: _peso(monthRevenue),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: '$year total',
                value: _peso(yearlyRevenue),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Orders in ${_months[month - 1]}',
                value: '$monthOrderCount',
                icon: Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Average order',
                value: _peso(averageOrder),
                icon: Icons.shopping_basket_outlined,
              ),
            ),
          ],
        ),
        if (!includeInProgress && inProgressOrders > 0) ...[
          const SizedBox(height: 12),
          _NoteCard(
            icon: Icons.local_shipping_outlined,
            color: const Color(0xFFD97706),
            text:
                '$inProgressOrders order${inProgressOrders == 1 ? '' : 's'} '
                'worth ${_peso(inProgressValue)} '
                '${inProgressOrders == 1 ? 'is' : 'are'} still in progress. '
                'They count as revenue once delivered.',
          ),
        ],
        if (cancelledOrders > 0) ...[
          const SizedBox(height: 12),
          _NoteCard(
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            text:
                '$cancelledOrders cancelled order'
                '${cancelledOrders == 1 ? '' : 's'} in ${_months[month - 1]} '
                '(not counted in revenue).',
          ),
        ],
        const SizedBox(height: 12),
        _AnalysisCard(
          change: change,
          current: monthRevenue,
          previous: previousRevenue,
          previousLabel:
              '${_months[previousMonth - 1]}${isCurrentMonth ? ' for the same period' : ''}',
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 720;
            final width = twoColumns
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: _ChartCard(
                    title: 'Orders by status',
                    subtitle: '${_months[month - 1]} $year',
                    child: _StatusBreakdown(statusOrderIds: statusOrderIds),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ChartCard(
                    title: 'Revenue by month',
                    subtitle: '$year overview',
                    child: _BarChart(
                      labels: _months.map((month) => month[0]).toList(),
                      values: monthlyRevenue,
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ChartCard(
                    title: 'Daily revenue',
                    subtitle: dailyRevenue[bestDay] > 0
                        ? '${_months[month - 1]} $year • best day: '
                              '${bestDay + 1} (${_peso(dailyRevenue[bestDay])})'
                        : '${_months[month - 1]} $year',
                    child: _ScrollableBarChart(
                      labels: List.generate(days, (index) => '${index + 1}'),
                      values: dailyRevenue,
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ChartCard(
                    title: 'Top products',
                    subtitle: 'By revenue in ${_months[month - 1]}',
                    child: _ProductRevenue(
                      entries: [
                        for (final entry in products.take(5))
                          (
                            entry.key,
                            entry.value,
                            productUnits[entry.key] ?? 0,
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ChartCard(
                    title: 'Orders by month',
                    subtitle: 'Orders counted in revenue, $year',
                    child: _BarChart(
                      labels: _months.map((month) => month[0]).toList(),
                      values: [for (final n in monthlyOrders) n.toDouble()],
                      currency: false,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _titleCase(String status) => status
    .split(' ')
    .map(
      (word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
    )
    .join(' ');

const _statusOrder = [
  'Pending',
  'Preparing',
  'Shipped',
  'Out for Delivery',
  'Delivered',
  'Cancelled',
];

Color _statusColor(String status) => switch (status) {
  'Pending' => const Color(0xFFD97706),
  'Preparing' => const Color(0xFF2563EB),
  'Shipped' => const Color(0xFF7C3AED),
  'Out for Delivery' => const Color(0xFF0891B2),
  'Delivered' => AppColors.success,
  _ => AppColors.error,
};

/// A stacked bar of how many orders are in each status, with a legend.
class _StatusBreakdown extends StatelessWidget {
  final Map<String, Set<int>> statusOrderIds;
  const _StatusBreakdown({required this.statusOrderIds});

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final status in _statusOrder)
        status: statusOrderIds[status]?.length ?? 0,
    };
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: Text(
            'No orders this month',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final entry in counts.entries)
                  if (entry.value > 0)
                    Expanded(
                      flex: entry.value,
                      child: Container(color: _statusColor(entry.key)),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in counts.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor(entry.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(entry.key)),
                Text(
                  '${entry.value}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    '${(entry.value / total * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _NoteCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Selector extends StatelessWidget {
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;
  const _Selector({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        isExpanded: true,
        value: value,
        items: [
          for (final item in items.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(height: 13),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _BarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final bool currency;
  final bool scrollable;
  const _BarChart({
    required this.labels,
    required this.values,
    this.currency = true,
    this.scrollable = false,
  });
  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 170,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const axisWidth = 42.0;
          final availableWidth = constraints.maxWidth - axisWidth - 8;
          final minimumWidth = values.length * 44.0;
          final chartWidth = scrollable && minimumWidth > availableWidth
              ? minimumWidth
              : availableWidth;
          final bars = SizedBox(
            width: chartWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: currency
                          ? _peso(values[i])
                          : values[i].round().toString(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _compactValue(values[i], currency),
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: double.infinity,
                                      height: values[i] == 0
                                          ? 3
                                          : 8 + values[i] / max * 102,
                                      decoration: BoxDecoration(
                                        color: values[i] == 0
                                            ? AppColors.lightGrey
                                            : AppColors.secondary,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(5),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              labels[i],
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          return Row(
            children: [
              SizedBox(
                width: axisWidth,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _compactValue(max, currency),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _compactValue(max / 2, currency),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        currency ? '₱0' : '0',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: bars,
                      )
                    : bars,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScrollableBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  const _ScrollableBarChart({required this.labels, required this.values});
  @override
  Widget build(BuildContext context) =>
      _BarChart(labels: labels, values: values, scrollable: true);
}

class _ProductRevenue extends StatelessWidget {
  final List<(String, double, int)> entries;
  const _ProductRevenue({required this.entries});
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(
          child: Text(
            'No product revenue yet',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final max = entries.first.$2;
    return Column(
      children: [
        for (final (index, entry) in entries.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _peso(entry.$2),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : entry.$2 / max,
                          minHeight: 8,
                          backgroundColor: AppColors.lightGrey,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${entry.$3} sold',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final double? change, current, previous;
  final String previousLabel;
  const _AnalysisCard({
    required this.change,
    required this.current,
    required this.previous,
    required this.previousLabel,
  });
  @override
  Widget build(BuildContext context) {
    // Revenue that started from nothing is good news, not a decline.
    final up = change == null ? current! > 0 : change! >= 0;
    final same = current == previous;
    final color = same
        ? AppColors.textSecondary
        : up
        ? AppColors.success
        : AppColors.error;
    final text = change == null
        ? (current! > 0
              ? 'Revenue started this month; $previousLabel had no delivered sales.'
              : 'No delivered revenue for either month.')
        : same
        ? 'Revenue is unchanged from $previousLabel.'
        : 'Revenue ${up ? 'increased' : 'decreased'} by ${change!.abs().toStringAsFixed(1)}% compared with $previousLabel.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            same
                ? Icons.remove
                : up
                ? Icons.trending_up
                : Icons.trending_down,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text('Unable to load shop analytics.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    ],
  );
}

BoxDecoration _card() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: AppColors.lightGrey.withValues(alpha: .75)),
);

String _peso(double value) {
  final raw = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
    out.write(raw[i]);
  }
  return '₱$out';
}

String _compactValue(double value, bool currency) {
  final prefix = currency ? '₱' : '';
  if (value >= 1000000) {
    return '$prefix${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '$prefix${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
  }
  return '$prefix${value.round()}';
}
