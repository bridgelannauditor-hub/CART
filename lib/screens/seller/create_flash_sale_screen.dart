import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/flash_sale_model.dart';
import '../../models/product_model.dart';
import '../../repositories/flash_sale_repository.dart';
import '../../repositories/product_repository.dart';
import '../../services/session_service.dart';
import '../../widgets/product_image.dart';

const _durationChoices = [1, 2, 3, 6, 12, 24, 48, 72];

class CreateFlashSaleScreen extends StatefulWidget {
  const CreateFlashSaleScreen({super.key});

  @override
  State<CreateFlashSaleScreen> createState() => _CreateFlashSaleScreenState();
}

class _CreateFlashSaleScreenState extends State<CreateFlashSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _flashSaleRepository = FlashSaleRepository();
  final _productRepository = ProductRepository();
  final _discountController = TextEditingController();
  final _promoStockController = TextEditingController();
  final _limitController = TextEditingController(text: '2');

  List<ProductModel> _products = [];
  Map<int, FlashSaleEligibility> _eligibility = {};
  ProductModel? _selected;
  late DateTime _startsAt = _defaultStart();
  int _durationHours = 3;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _promoStockController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  /// The next full hour that is at least 1 hour away.
  static DateTime _defaultStart() {
    final earliest = DateTime.now().add(const Duration(hours: 1, minutes: 5));
    return DateTime(
      earliest.year,
      earliest.month,
      earliest.day,
      earliest.hour + 1,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _productRepository.getProductsBySeller(SessionService.userId!),
        _flashSaleRepository.myEligibility(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<ProductModel>;
        _eligibility = {
          for (final item in results[1] as List<FlashSaleEligibility>)
            item.productId: item,
        };
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is StateError
            ? error.message
            : "Couldn't load your products. Please retry.";
      });
    }
  }

  FlashSaleEligibility? get _selectedEligibility =>
      _selected == null ? null : _eligibility[_selected!.id];

  void _select(ProductModel product) {
    final eligibility = _eligibility[product.id]!;
    _discountController.text = '${max(eligibility.minDiscountPercent, 10)}';
    _promoStockController.text = '${min(eligibility.maxPromoStock, 10)}';
    setState(() => _selected = product);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
        content: Text(message),
      ),
    );
  }

  Future<void> _submit() async {
    final product = _selected;
    if (product == null || !_formKey.currentState!.validate()) return;
    if (_startsAt.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
      _showError('Start the flash sale at least 1 hour from now.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _flashSaleRepository.create(
        productId: product.id!,
        discountPercent: int.parse(_discountController.text.trim()),
        promoStock: int.parse(_promoStockController.text.trim()),
        perCustomerLimit: int.parse(_limitController.text.trim()),
        startsAt: _startsAt,
        endsAt: _startsAt.add(Duration(hours: _durationHours)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        error is StateError
            ? error.message
            : "Couldn't schedule the flash sale: $error",
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        content: Text('Flash sale for "${product.productName}" scheduled.'),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F5),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'New flash sale',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? Center(
              child: TextButton(onPressed: _load, child: Text(_error!)),
            )
          : _selected == null
          ? _buildProductPicker()
          : _buildForm(_selected!, _selectedEligibility!),
    );
  }

  Widget _buildProductPicker() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Choose a product',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'A product can join a flash sale once it has been listed for 7 '
          'days, has at least 1 delivered sale, and its price has not been '
          'raised in the last 7 days.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        if (_products.isEmpty) const Text('You have no products yet.'),
        for (final product in _products)
          _ProductChoice(
            product: product,
            eligibility: _eligibility[product.id],
            onTap: () => _select(product),
          ),
      ],
    );
  }

  Widget _buildForm(ProductModel product, FlashSaleEligibility eligibility) {
    final discount = int.tryParse(_discountController.text.trim());
    final endsAt = _startsAt.add(Duration(hours: _durationHours));
    final format = DateFormat.yMMMd().add_jm();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _ProductChoice(
            product: product,
            eligibility: eligibility,
            trailing: TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _selected = null),
              child: const Text('Change'),
            ),
          ),
          const SizedBox(height: 8),
          _numberField(
            controller: _discountController,
            label: 'Discount (%)',
            helper:
                'At least ${eligibility.minDiscountPercent}% so the flash '
                'price beats its lowest price in the last 30 days.',
            min: eligibility.minDiscountPercent,
            max: 90,
          ),
          _numberField(
            controller: _promoStockController,
            label: 'Flash stock',
            helper:
                'Units sold at the flash price, taken from your '
                '${eligibility.maxPromoStock} in stock.',
            min: 1,
            max: eligibility.maxPromoStock,
          ),
          _numberField(
            controller: _limitController,
            label: 'Limit per customer',
            helper: 'How many flash units one customer can buy (1 to 10).',
            min: 1,
            max: 10,
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Starts'),
              subtitle: Text(format.format(_startsAt)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _saving ? null : _pickStart,
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: _durationHours,
            decoration: const InputDecoration(
              labelText: 'Runs for',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: [
              for (final hours in _durationChoices)
                DropdownMenuItem(
                  value: hours,
                  child: Text(hours == 1 ? '1 hour' : '$hours hours'),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _durationHours = value!),
          ),
          const SizedBox(height: 6),
          Text(
            'Ends ${format.format(endsAt)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          if (discount != null &&
              discount >= eligibility.minDiscountPercent &&
              discount <= 90)
            _PricePreview(product: product, discountPercent: discount),
          const SizedBox(height: 24),
          _saving
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _submit,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Schedule flash sale'),
                ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required int min,
    required int max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (text) {
          final value = int.tryParse(text?.trim() ?? '');
          if (value == null || value < min || value > max) {
            return 'Enter a whole number from $min to $max';
          }
          return null;
        },
      ),
    );
  }
}

class _ProductChoice extends StatelessWidget {
  final ProductModel product;
  final FlashSaleEligibility? eligibility;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ProductChoice({
    required this.product,
    required this.eligibility,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final eligible = eligibility?.eligible ?? false;
    final subtitle = eligibility == null
        ? 'Eligibility unavailable'
        : eligible
        ? 'Eligible · at least ${eligibility!.minDiscountPercent}% off'
        : eligibility!.reasons.join('\n');

    return Opacity(
      opacity: eligible ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightGrey),
        ),
        child: ListTile(
          onTap: eligible ? onTap : null,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: ProductImage(
                path: product.image,
                maxDecodeWidth: 100,
                placeholder: Container(
                  color: AppColors.lightGrey,
                  child: const Icon(Icons.image_outlined),
                ),
              ),
            ),
          ),
          title: Text(
            product.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: eligible ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          trailing:
              trailing ??
              (eligible ? const Icon(Icons.chevron_right_rounded) : null),
        ),
      ),
    );
  }
}

class _PricePreview extends StatelessWidget {
  final ProductModel product;
  final int discountPercent;

  const _PricePreview({required this.product, required this.discountPercent});

  @override
  Widget build(BuildContext context) {
    final points = product.hasImageOptions
        ? [for (final option in product.options) (option.name, option.price)]
        : [('Price', product.price)];
    double flashPrice(double base) {
      final discounted = base * (100 - discountPercent) / 100;
      return (discounted * 100).roundToDouble() / 100;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Flash prices',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final (name, base) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(name)),
                  Text(
                    '₱${base.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${flashPrice(base).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (product.discountPercent > 0)
            Text(
              'Replaces your regular ${product.discountPercent}% discount '
              'while the sale is live.',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
