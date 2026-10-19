import '../../models/voucher_model.dart';
import '../../repositories/voucher_repository.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/cart_item_model.dart';
import '../../models/address_model.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/order_functions_service.dart';
import '../../services/session_service.dart';
import '../../utils/routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/product_image.dart';
import 'add_edit_address_screen.dart';

class CheckoutScreen extends StatefulWidget {
  // When provided, checkout is limited to these cart items only
  // (the customer's checkbox selection on the cart screen). When
  // null, falls back to the customer's full cart.
  final List<CartItemModel>? selectedItems;

  const CheckoutScreen({super.key, this.selectedItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ProductRepository _productRepository = ProductRepository();
  final OrderFunctionsService _orderFunctions = OrderFunctionsService();

  List<CartItemModel> cartItems = [];
  List<ProductModel> products = [];
  List<VoucherModel> _vouchers = [];
  List<AddressModel> _addresses = [];
  final Map<int, String> _selectedVouchers = {};
  int? _selectedAddressId;
  String _paymentMethod = 'Cash on Delivery';

  bool isLoading = true;
  bool isPlacingOrder = false;
  int? placedOrderId;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        _selectedVouchers.clear();
      });
    }
    try {
      await _loadCartData();
    } catch (_) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checkout could not be loaded. Tap refresh to try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadCartData() async {
    final userId = SessionService.userId;

    if (userId == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    // If specific items were passed in (checkbox selection on the
    // cart screen), use those. Otherwise fall back to the full cart.
    final items =
        widget.selectedItems ??
        await DatabaseHelper.instance.getCartItems(userId);
    final relevantProductIds = items.map((e) => e.productId).toSet();
    final productList = await _productRepository.getProductsByIds(
      relevantProductIds.toList(),
    );
    final addressRows = await DatabaseHelper.instance.getAddressesForUser(
      userId,
    );
    final addresses = addressRows.map(AddressModel.fromMap).toList();
    List<VoucherModel> vouchers = [];
    try {
      vouchers = await VoucherRepository().availableWallet(userId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vouchers could not be loaded. Refresh checkout to try again.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;

    setState(() {
      _vouchers = vouchers;
      _addresses = addresses;
      if (!addresses.any((address) => address.id == _selectedAddressId)) {
        _selectedAddressId = addresses.isEmpty
            ? null
            : addresses
                  .firstWhere(
                    (address) => address.isDefault,
                    orElse: () => addresses.first,
                  )
                  .id;
      }
      cartItems = items;
      products = productList;
      isLoading = false;
    });
  }

  Future<void> _refreshPrices() async {
    try {
      final refreshed = await _productRepository.getProductsByIds(
        cartItems.map((item) => item.productId).toSet().toList(),
      );
      if (mounted) setState(() => products = refreshed);
    } catch (_) {}
  }

  AddressModel? get _selectedAddress {
    for (final address in _addresses) {
      if (address.id == _selectedAddressId) return address;
    }
    return null;
  }

  Future<void> _addAddress() async {
    final userId = SessionService.userId;
    if (userId == null || isPlacingOrder) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddEditAddressScreen(userId: userId)),
    );
    if (added == true) await _loadCartData();
  }

  Widget _deliveryAddressPicker() {
    if (_addresses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A delivery address is required before you can place an order.',
              style: TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isPlacingOrder ? null : _addAddress,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add delivery address'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        DropdownButtonFormField<int>(
          initialValue: _selectedAddressId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Deliver to',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          items: [
            for (final address in _addresses)
              DropdownMenuItem(
                value: address.id,
                child: Text(
                  '${address.label} • ${address.fullName} — ${address.shortAddress}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: isPlacingOrder
              ? null
              : (id) => setState(() => _selectedAddressId = id),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: isPlacingOrder ? null : _addAddress,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another address'),
          ),
        ),
      ],
    );
  }

  ProductModel? _getProduct(int productId) {
    try {
      return products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  double _itemPrice(CartItemModel item, ProductModel product) {
    final basePrice = product.optionById(item.optionId)?.price ?? product.price;
    return product.discountedPriceFor(basePrice);
  }

  double get _total {
    double result = 0;
    for (final item in cartItems) {
      final product = _getProduct(item.productId);
      if (product != null) {
        result += _itemPrice(item, product) * item.quantity;
      }
    }
    return result;
  }

  Map<int, double> get _sellerTotals {
    final result = <int, double>{};
    for (final item in cartItems) {
      final p = _getProduct(item.productId);
      if (p != null) {
        result[p.sellerId] =
            (result[p.sellerId] ?? 0) + _itemPrice(item, p) * item.quantity;
      }
    }
    return result;
  }

  double get _discount => _vouchers
      .where((v) => _selectedVouchers[v.sellerId] == v.id)
      .fold(
        0,
        (sum, v) =>
            sum + v.discount(_sellerTotals[v.sellerId] ?? 0, DateTime.now()),
      );
  Widget _voucherPicker() => Column(
    children: [
      ..._sellerTotals.entries.map((entry) {
        final eligible = _vouchers
            .where(
              (v) =>
                  v.sellerId == entry.key &&
                  v.discount(entry.value, DateTime.now()) > 0,
            )
            .toList();
        if (eligible.isEmpty) return const SizedBox.shrink();
        final selected = _selectedVouchers[entry.key];
        final current = eligible.any((v) => v.id == selected) ? selected : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: ValueKey('${entry.key}_$current'),
            initialValue: current,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '${eligible.first.sellerName} voucher',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('No voucher'),
              ),
              ...eligible.map(
                (v) => DropdownMenuItem(
                  value: v.id,
                  child: Text(
                    '${v.label} • Save ₱${v.discount(entry.value, DateTime.now()).toStringAsFixed(2)}',
                  ),
                ),
              ),
            ],
            onChanged: isPlacingOrder
                ? null
                : (id) => setState(() {
                    if (id == null || id.isEmpty) {
                      _selectedVouchers.remove(entry.key);
                    } else {
                      _selectedVouchers[entry.key] = id;
                    }
                  }),
          ),
        );
      }),
      if (_discount > 0)
        Text('Voucher discount: −₱${_discount.toStringAsFixed(2)}'),
    ],
  );

  Widget _paymentPicker() {
    const methods = [
      (
        value: 'Cash on Delivery',
        subtitle: 'Pay in cash when your order arrives',
        icon: Icons.local_shipping_outlined,
      ),
      (
        value: 'GCash',
        subtitle: 'Pay using your GCash account',
        icon: Icons.account_balance_wallet_outlined,
      ),
      (
        value: 'Maya',
        subtitle: 'Pay using your Maya account',
        icon: Icons.phone_android_outlined,
      ),
      (
        value: 'Bank Account',
        subtitle: 'Pay through a bank transfer',
        icon: Icons.account_balance_outlined,
      ),
    ];

    return Column(
      children: [
        for (final method in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: isPlacingOrder
                  ? null
                  : () => setState(() => _paymentMethod = method.value),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _paymentMethod == method.value
                        ? AppColors.primary
                        : AppColors.lightGrey,
                    width: _paymentMethod == method.value ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(method.icon, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            method.value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            method.subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _paymentMethod == method.value
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: _paymentMethod == method.value
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_paymentMethod != 'Cash on Delivery')
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Payment instructions and confirmation will be provided after the order is placed.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  Future<void> _placeOrder() async {
    final userId = SessionService.userId;
    if (userId == null || cartItems.isEmpty) return;

    final selectedAddressId = _selectedAddressId;
    if (selectedAddressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a delivery address first.')),
      );
      return;
    }
    final currentAddressRows = await DatabaseHelper.instance
        .getAddressesForUser(userId);
    AddressModel? deliveryAddress;
    for (final row in currentAddressRows) {
      final address = AddressModel.fromMap(row);
      if (address.id == selectedAddressId) {
        deliveryAddress = address;
        break;
      }
    }
    if (!mounted) return;
    if (deliveryAddress == null) {
      setState(() {
        _addresses = currentAddressRows.map(AddressModel.fromMap).toList();
        _selectedAddressId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That delivery address is no longer available.'),
        ),
      );
      return;
    }

    setState(() => isPlacingOrder = true);

    late final int orderId;
    try {
      orderId = await _orderFunctions.placeOrder(
        items: cartItems,
        voucherIds: _selectedVouchers,
        paymentMethod: _paymentMethod,
        deliveryAddress: deliveryAddress,
        flashSaleIds: {
          for (final product in products)
            if (product.id != null && product.liveFlashSale != null)
              product.id!: product.liveFlashSale!.id,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => isPlacingOrder = false);
      // A flash sale may have ended or sold out; show current prices.
      _refreshPrices();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'The order could not be placed. Please try again.',
          ),
        ),
      );
      return;
    }

    // Only remove the items that were actually part of this order —
    // any items the customer left unchecked stay in their cart.
    try {
      for (final item in cartItems) {
        if (item.id != null) {
          await DatabaseHelper.instance.removeFromCart(item.id!);
        }
      }
    } catch (_) {}

    // Seller notifications are created atomically by the checkout function.

    if (!mounted) return;

    setState(() {
      isPlacingOrder = false;
      placedOrderId = orderId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        actions: [
          if (placedOrderId == null)
            IconButton(
              tooltip: 'Refresh checkout',
              onPressed: isPlacingOrder || isLoading ? null : _loadCart,
              icon: const Icon(Icons.refresh),
            ),
        ],
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Checkout",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : placedOrderId != null
            ? _OrderSuccessView(
                orderId: placedOrderId!,
                paymentMethod: _paymentMethod,
              )
            : cartItems.isEmpty
            ? const _EmptyCheckoutView()
            : _CheckoutForm(
                cartItems: cartItems,
                getProduct: _getProduct,
                total: _total - _discount,
                subtotal: _total,
                voucherDiscounts: [
                  for (final voucher in _vouchers)
                    if (_selectedVouchers[voucher.sellerId] == voucher.id &&
                        voucher.discount(
                              _sellerTotals[voucher.sellerId] ?? 0,
                              DateTime.now(),
                            ) >
                            0)
                      (
                        sellerName: voucher.sellerName,
                        label: voucher.label,
                        amount: voucher.discount(
                          _sellerTotals[voucher.sellerId] ?? 0,
                          DateTime.now(),
                        ),
                      ),
                ],
                voucherPicker: _voucherPicker(),
                paymentPicker: _paymentPicker(),
                paymentMethod: _paymentMethod,
                deliveryAddressPicker: _deliveryAddressPicker(),
                deliveryAddress: _selectedAddress,
                isPlacingOrder: isPlacingOrder,
                onPlaceOrder: _placeOrder,
              ),
      ),
    );
  }
}

class _CheckoutForm extends StatelessWidget {
  final List<CartItemModel> cartItems;
  final ProductModel? Function(int) getProduct;
  final double total;
  final double subtotal;
  final List<({String sellerName, String label, double amount})>
  voucherDiscounts;
  final bool isPlacingOrder;
  final VoidCallback onPlaceOrder;
  final Widget voucherPicker;
  final Widget paymentPicker;
  final String paymentMethod;
  final Widget deliveryAddressPicker;
  final AddressModel? deliveryAddress;

  const _CheckoutForm({
    required this.cartItems,
    required this.getProduct,
    required this.total,
    required this.subtotal,
    required this.voucherDiscounts,
    required this.isPlacingOrder,
    required this.onPlaceOrder,
    required this.voucherPicker,
    required this.paymentPicker,
    required this.paymentMethod,
    required this.deliveryAddressPicker,
    required this.deliveryAddress,
  });

  double _itemPrice(CartItemModel item, ProductModel product) {
    final basePrice = product.optionById(item.optionId)?.price ?? product.price;
    return product.discountedPriceFor(basePrice);
  }

  Widget _receiptRow(String label, String amount, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            amount,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _receipt() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Receipt Preview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Review your purchase before placing your order.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Divider(height: 24),
        for (final item in cartItems)
          if (getProduct(item.productId) case final ProductModel product)
            _receiptRow(
              '${product.productName}${(item.optionName ?? '').isEmpty ? '' : ' • ${item.optionName}'}\n${item.quantity} × ₱${_itemPrice(item, product).toStringAsFixed(2)}',
              '₱${(_itemPrice(item, product) * item.quantity).toStringAsFixed(2)}',
            ),
        const Divider(height: 24),
        _receiptRow('Subtotal', '₱${subtotal.toStringAsFixed(2)}'),
        if (voucherDiscounts.isEmpty) _receiptRow('Voucher discount', '₱0.00'),
        for (final discount in voucherDiscounts)
          _receiptRow(
            '${discount.sellerName} • ${discount.label}',
            '−₱${discount.amount.toStringAsFixed(2)}',
          ),
        const Divider(height: 24),
        _receiptRow(
          'Total to pay',
          '₱${total.toStringAsFixed(2)}',
          emphasize: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Payment: $paymentMethod',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (deliveryAddress != null) ...[
          const SizedBox(height: 4),
          Text(
            'Deliver to: ${deliveryAddress!.fullName} • ${deliveryAddress!.phone}\n${deliveryAddress!.shortAddress}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              voucherPicker,
              const Text(
                'Delivery Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              deliveryAddressPicker,
              const SizedBox(height: 20),
              const Text(
                "Order Summary",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              ...cartItems.map((item) {
                final product = getProduct(item.productId);
                if (product == null) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: AppColors.lightGrey,
                          child: ProductImage(
                            path: item.optionImage ?? product.image,
                            fit: BoxFit.cover,
                            placeholder: const Icon(
                              Icons.image_outlined,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if ((item.optionName ?? '').isNotEmpty)
                              Text(
                                item.optionName!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            Text(
                              "Qty ${item.quantity} × ₱${_itemPrice(item, product).toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "₱${(_itemPrice(item, product) * item.quantity).toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),

              const Text(
                "Payment Method",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              paymentPicker,
              const SizedBox(height: 20),
              _receipt(),
            ],
          ),
        ),

        // ---------- Total + place order ----------
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Total",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "₱${total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              isPlacingOrder
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : CustomButton(
                      text: deliveryAddress == null
                          ? 'ADD DELIVERY ADDRESS TO CONTINUE'
                          : 'PLACE ORDER',
                      onPressed: deliveryAddress == null ? null : onPlaceOrder,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderSuccessView extends StatelessWidget {
  final int orderId;
  final String paymentMethod;
  const _OrderSuccessView({required this.orderId, required this.paymentMethod});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Order Placed!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Order #$orderId has been placed and is now pending confirmation from the seller.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              paymentMethod == 'Cash on Delivery'
                  ? 'Payment method: Cash on Delivery'
                  : 'Payment method: $paymentMethod • Awaiting payment confirmation',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            CustomButton(
              text: "CONTINUE SHOPPING",
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.home,
                  (route) => false,
                );
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.orders,
                  (route) => false,
                );
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text(
                "View My Orders",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCheckoutView extends StatelessWidget {
  const _EmptyCheckoutView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.remove_shopping_cart_outlined,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              "Your cart is empty",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Add something to your cart before checking out.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text(
                "Go Back",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
