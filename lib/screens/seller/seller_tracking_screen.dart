import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/order_tracking_model.dart';
import '../../models/seller_order_item_model.dart';
import '../../repositories/order_repository.dart';
import '../../services/order_functions_service.dart';
import '../../services/session_service.dart';
import '../../utils/date_formatter.dart';

List<String> _sellerTrackingStatuses(String current) => [
  current,
  ...switch (current) {
    'Pending' => const ['Preparing', 'Cancelled'],
    'Preparing' => const ['Shipped', 'Cancelled'],
    'Shipped' => const ['Out for Delivery'],
    'Out for Delivery' => const ['Delivered'],
    _ => const <String>[],
  },
];

class SellerTrackingScreen extends StatefulWidget {
  final SellerOrderItemModel order;

  const SellerTrackingScreen({super.key, required this.order});

  @override
  State<SellerTrackingScreen> createState() => _SellerTrackingScreenState();
}

class _SellerTrackingScreenState extends State<SellerTrackingScreen> {
  final OrderRepository _orders = OrderRepository();
  final OrderFunctionsService _orderFunctions = OrderFunctionsService();
  final TextEditingController _courierController = TextEditingController();
  final TextEditingController _trackingNumberController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String _status = 'Pending';
  String _persistedStatus = 'Pending';
  DateTime? _estimatedDate;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tracking = await _orders.getOrderTracking(
        widget.order.orderId,
        sellerId: SessionService.userId,
      );
      if (!mounted) return;
      if (tracking != null) _populate(tracking);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _populate(OrderTrackingModel tracking) {
    _status = tracking.status;
    _persistedStatus = tracking.status;
    _courierController.text = tracking.courier;
    _trackingNumberController.text = tracking.trackingNumber;
    _locationController.text = tracking.currentLocation;
    _estimatedDate = DateTime.tryParse(tracking.estimatedDeliveryDate);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _estimatedDate != null && _estimatedDate!.isAfter(now)
        ? _estimatedDate!
        : now.add(const Duration(days: 3));
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _estimatedDate = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _orderFunctions.updateSellerOrder(
        orderId: widget.order.orderId,
        status: _status,
        courier: _courierController.text,
        trackingNumber: _trackingNumberController.text,
        estimatedDeliveryDate: _estimatedDate?.toIso8601String() ?? '',
        currentLocation: _locationController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking update could not be saved.')),
      );
    }
  }

  @override
  void dispose() {
    _courierController.dispose();
    _trackingNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: AppColors.lightGrey),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: AppColors.lightGrey),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Tracking #${widget.order.orderId}'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.order.productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Customer: ${widget.order.customerName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: _decoration(
                    'Delivery status',
                    Icons.local_shipping_outlined,
                  ),
                  items: _sellerTrackingStatuses(_persistedStatus)
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _courierController,
                  decoration: _decoration(
                    'Courier or delivery service',
                    Icons.delivery_dining_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _trackingNumberController,
                  decoration: _decoration(
                    'Tracking number',
                    Icons.confirmation_number_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  decoration: _decoration(
                    'Current checkpoint or location',
                    Icons.location_on_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: _decoration(
                      'Estimated delivery date',
                      Icons.event_outlined,
                    ),
                    child: Text(
                      _estimatedDate == null
                          ? 'Select a date'
                          : formatOrderDate(_estimatedDate!.toIso8601String()),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'SAVING...' : 'SAVE TRACKING UPDATE'),
                  ),
                ),
              ],
            ),
    );
  }
}
