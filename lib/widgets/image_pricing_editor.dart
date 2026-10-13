import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/product_media_model.dart';
import 'media_picker_grid.dart';
import 'product_image.dart';

class ImageOptionDraft {
  final String id;
  final String imagePath;
  final String name;
  final String priceText;
  final String stockText;
  final bool isDefault;

  const ImageOptionDraft({
    required this.id,
    required this.imagePath,
    required this.name,
    required this.priceText,
    required this.stockText,
    this.isDefault = false,
  });

  ImageOptionDraft copyWith({
    String? imagePath,
    String? name,
    String? priceText,
    String? stockText,
    bool? isDefault,
  }) {
    return ImageOptionDraft(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      name: name ?? this.name,
      priceText: priceText ?? this.priceText,
      stockText: stockText ?? this.stockText,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class ImagePricingEditor extends StatelessWidget {
  final bool useOnePrice;
  final List<PickedMediaItem> media;
  final List<ImageOptionDraft> options;
  final ValueChanged<bool> onUseOnePriceChanged;
  final ValueChanged<List<ImageOptionDraft>> onOptionsChanged;

  const ImagePricingEditor({
    super.key,
    required this.useOnePrice,
    required this.media,
    required this.options,
    required this.onUseOnePriceChanged,
    required this.onOptionsChanged,
  });

  void _update(int index, ImageOptionDraft value) {
    final updated = [...options];
    updated[index] = value;
    onOptionsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = media
        .where((item) => item.type == ProductMediaType.image)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Pricing setup',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.sell_outlined),
              label: Text('One price'),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.photo_library_outlined),
              label: Text('Price per picture'),
            ),
          ],
          selected: {useOnePrice},
          onSelectionChanged: (selection) {
            onUseOnePriceChanged(selection.first);
          },
        ),
        const SizedBox(height: 8),
        Text(
          useOnePrice
              ? 'All $imageCount pictures show the same product and use one price and stock value.'
              : 'Each picture is a product option with its own name, price, and stock.',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        if (!useOnePrice) ...[
          const SizedBox(height: 14),
          if (options.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Add at least one picture to create picture options.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (var index = 0; index < options.length; index++) ...[
            _OptionCard(
              key: ValueKey(options[index].id),
              option: options[index],
              index: index,
              onChanged: (value) => _update(index, value),
              onDefault: () {
                onOptionsChanged([
                  for (
                    var optionIndex = 0;
                    optionIndex < options.length;
                    optionIndex++
                  )
                    options[optionIndex].copyWith(
                      isDefault: optionIndex == index,
                    ),
                ]);
              },
            ),
            if (index != options.length - 1) const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final ImageOptionDraft option;
  final int index;
  final ValueChanged<ImageOptionDraft> onChanged;
  final VoidCallback onDefault;

  const _OptionCard({
    super.key,
    required this.option,
    required this.index,
    required this.onChanged,
    required this.onDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: option.isDefault ? AppColors.primary : AppColors.lightGrey,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ProductImage(
                    path: option.imagePath,
                    placeholder: const ColoredBox(
                      color: AppColors.lightGrey,
                      child: Icon(Icons.image_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: option.name,
                  decoration: InputDecoration(
                    labelText: 'Option name',
                    hintText: 'e.g. Small bouquet',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an option name';
                    }
                    return null;
                  },
                  onChanged: (value) => onChanged(option.copyWith(name: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: option.priceText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Price (₱)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    final price = double.tryParse(value?.trim() ?? '');
                    if (price == null || price <= 0) return 'Invalid price';
                    return null;
                  },
                  onChanged: (value) =>
                      onChanged(option.copyWith(priceText: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: option.stockText,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Stock',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    final stock = int.tryParse(value?.trim() ?? '');
                    if (stock == null || stock < 0) return 'Invalid stock';
                    return null;
                  },
                  onChanged: (value) =>
                      onChanged(option.copyWith(stockText: value)),
                ),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: onDefault,
            leading: Icon(
              option.isDefault
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: AppColors.primary,
            ),
            title: const Text('Default customer option'),
          ),
        ],
      ),
    );
  }
}
