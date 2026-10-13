import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/voucher_model.dart';
import '../../repositories/voucher_repository.dart';
import '../../services/session_service.dart';
import 'shop_screen.dart';

class MyVouchersScreen extends StatefulWidget {
  const MyVouchersScreen({super.key});
  @override
  State<MyVouchersScreen> createState() => _MyVouchersScreenState();
}

class _MyVouchersScreenState extends State<MyVouchersScreen> {
  final VoucherRepository _repository = VoucherRepository();
  final List<VoucherModel> _vouchers = [];
  String? _cursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final userId = SessionService.userId;
    if (userId == null || (!reset && (_isLoadingMore || !_hasMore))) return;

    setState(() {
      _error = null;
      if (reset) {
        _isLoading = true;
        _cursor = null;
        _hasMore = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await _repository.walletPage(
        userId,
        after: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _vouchers.clear();
        final ids = _vouchers.map((voucher) => voucher.id).toSet();
        _vouchers.addAll(
          page.items.where((voucher) => !ids.contains(voucher.id)),
        );
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load vouchers.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('My Vouchers'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Available'),
            Tab(text: 'Used'),
            Tab(text: 'Expired'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _vouchers.isEmpty
          ? Center(
              child: TextButton(
                onPressed: () => _load(reset: true),
                child: Text('$_error Retry'),
              ),
            )
          : TabBarView(
              children: [
                'Available',
                'Used',
                'Expired',
              ].map(_buildVoucherTab).toList(),
            ),
    ),
  );

  Widget _buildVoucherTab(String status) {
    final vouchers = _vouchers
        .where((voucher) => voucher.statusAt(DateTime.now()) == status)
        .toList();
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount:
            vouchers.length +
            (_hasMore ? 1 : 0) +
            (vouchers.isEmpty && !_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (vouchers.isEmpty && !_hasMore) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No ${status.toLowerCase()} vouchers.'),
            );
          }
          if (index == vouchers.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => _load(reset: false),
                        child: Text(
                          _error == null ? 'Load older vouchers' : 'Retry',
                        ),
                      ),
              ),
            );
          }
          return _voucherCard(vouchers[index], status);
        },
      ),
    );
  }

  Widget _voucherCard(VoucherModel voucher, String status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              voucher.sellerName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              voucher.label,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('Minimum purchase: ₱${voucher.minimum.toStringAsFixed(2)}'),
            if (voucher.data['type'] == 'percentage' &&
                voucher.data['maximum'] != null)
              Text('Maximum discount: ₱${voucher.data['maximum']}'),
            const Text('Eligible products: entire seller shop'),
            Text(
              'Expires ${DateFormat('MMM d, yyyy • h:mm a').format(voucher.expiresAt)}',
            ),
            if (status == 'Available')
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopScreen(sellerId: voucher.sellerId),
                  ),
                ),
                child: const Text('Shop now'),
              ),
          ],
        ),
      ),
    );
  }
}
