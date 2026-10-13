import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../repositories/voucher_repository.dart';
import '../../repositories/user_repository.dart';
import '../../models/voucher_model.dart';
import '../../services/session_service.dart';

class FollowerVouchersScreen extends StatefulWidget {
  const FollowerVouchersScreen({super.key});
  @override
  State<FollowerVouchersScreen> createState() => _FollowerVouchersScreenState();
}

class _FollowerVouchersScreenState extends State<FollowerVouchersScreen> {
  final _repo = VoucherRepository();
  final _form = GlobalKey<FormState>();
  final _value = TextEditingController(text: '10');
  final _minimum = TextEditingController(text: '500');
  final _maximum = TextEditingController(text: '100');
  final _quantity = TextEditingController(text: '100');
  final _days = TextEditingController(text: '7');
  String _type = 'percentage';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 30));
  Map<String, dynamic>? _campaign;
  int _claimed = 0;
  int _redeemed = 0;
  double _revenue = 0;
  int _followers = 0;
  bool _busy = true;
  String? _error;
  int get _sellerId => SessionService.userId!;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_value, _minimum, _maximum, _quantity, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final campaign = await _repo.getCampaign(_sellerId);
      final analytics = campaign == null
          ? FollowerCampaignAnalytics.empty
          : await _repo.getCampaignAnalytics(_sellerId, campaign);
      if (!mounted) return;
      setState(() {
        _campaign = campaign;
        _claimed = analytics.claimed;
        _redeemed = analytics.redeemed;
        _revenue = analytics.revenue;
        _followers = analytics.newFollowers;
        _busy = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not load campaigns. Please retry.';
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _number(
    String label,
    TextEditingController controller, {
    bool integer = false,
    bool zero = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (text) {
        final n = num.tryParse(text ?? '');
        return n == null ||
                !n.isFinite ||
                n < (zero ? 0 : 0.01) ||
                (integer && n != n.round())
            ? 'Enter a valid ${integer ? 'whole number' : 'amount'}'
            : null;
      },
    ),
  );
  Future<void> _pick(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date != null && mounted) {
      setState(() {
        if (start) {
          _start = date;
        } else {
          _end = DateTime(date.year, date.month, date.day, 23, 59, 59);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign;
    final canCreate =
        c == null ||
        c['status'] == 'ended' ||
        !DateTime.now().isBefore(c['expiresAt'] as DateTime);
    return Scaffold(
      appBar: AppBar(title: const Text('Followers & Vouchers')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    TextButton(onPressed: _load, child: Text(_error!)),
                  if (c != null) ...[
                    Text(
                      '${VoucherModel('', c).label} • ${campaignCanClaim(c, DateTime.now())
                          ? 'Active'
                          : c['status'] == 'active'
                          ? 'Scheduled, expired or fully claimed'
                          : c['status']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'New followers: $_followers\nVouchers claimed: $_claimed\nVouchers redeemed: $_redeemed\nRedemption rate: ${_claimed == 0 ? '0' : (_redeemed / _claimed * 100).toStringAsFixed(1)}%\nRevenue through vouchers: ₱${_revenue.toStringAsFixed(2)}\nRemaining quantity: ${(c['quantity'] as num) - (c['claimed'] as num)}',
                    ),
                    Text(
                      'Minimum ₱${c['minimum']} • Valid ${c['validDays']} days after claiming\n${DateFormat.yMMMd().format(c['startsAt'] as DateTime)} – ${DateFormat.yMMMd().format(c['expiresAt'] as DateTime)}',
                    ),
                    if (!canCreate)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _act(
                              () => _repo.setStatus(
                                _sellerId,
                                c['status'] == 'active' ? 'paused' : 'active',
                              ),
                            ),
                            child: Text(
                              c['status'] == 'active' ? 'Pause' : 'Activate',
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _act(() => _repo.setStatus(_sellerId, 'ended')),
                            child: const Text('End campaign'),
                          ),
                        ],
                      ),
                    const Divider(height: 32),
                  ],
                  if (canCreate)
                    Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            c == null
                                ? 'No follower voucher'
                                : 'Create next campaign',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text(
                            'New followers only • One claim per customer • Entire shop\nIssued vouchers remain valid when paused or ended.',
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _type,
                            decoration: const InputDecoration(
                              labelText: 'Discount type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'percentage',
                                child: Text('Percentage discount'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('Fixed discount (₱)'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _type = v!),
                          ),
                          _number(
                            _type == 'percentage'
                                ? 'Discount (%)'
                                : 'Discount (₱)',
                            _value,
                          ),
                          _number('Minimum purchase (₱)', _minimum, zero: true),
                          if (_type == 'percentage')
                            _number('Maximum discount (₱)', _maximum),
                          _number('Voucher quantity', _quantity, integer: true),
                          _number(
                            'Validity after claiming (days)',
                            _days,
                            integer: true,
                          ),
                          ListTile(
                            title: const Text('Start date'),
                            subtitle: Text(DateFormat.yMMMd().format(_start)),
                            onTap: () => _pick(true),
                          ),
                          ListTile(
                            title: const Text('Expiration date'),
                            subtitle: Text(DateFormat.yMMMd().format(_end)),
                            onTap: () => _pick(false),
                          ),
                          FilledButton(
                            onPressed: () {
                              if (!_form.currentState!.validate()) return;
                              _act(() async {
                                final seller = await UserRepository()
                                    .getUserById(_sellerId);
                                await _repo.createCampaign(_sellerId, {
                                  'sellerName': seller?.shopName ?? 'Shop',
                                  'type': _type,
                                  'value': double.parse(_value.text),
                                  'minimum': double.parse(_minimum.text),
                                  'maximum': _type == 'percentage'
                                      ? double.parse(_maximum.text)
                                      : null,
                                  'quantity': int.parse(_quantity.text),
                                  'validDays': int.parse(_days.text),
                                  'startsAt': _start,
                                  'expiresAt': _end,
                                });
                              });
                            },
                            child: const Text('Activate campaign'),
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
