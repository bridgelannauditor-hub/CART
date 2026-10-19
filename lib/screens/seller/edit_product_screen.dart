import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/product_taxonomy.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/product_media_model.dart';
import '../../models/product_option_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/category_service.dart';
import '../../services/cloudinary_service.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';
import '../../widgets/category_picker_field.dart';
import '../../widgets/simple_option_picker_field.dart';
import '../../widgets/tag_selector_field.dart';
import '../../widgets/making_process_editor.dart';
import '../../widgets/media_picker_grid.dart';
import '../../widgets/image_pricing_editor.dart';

class EditProductScreen extends StatefulWidget {
  final ProductModel product;

  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryService _categoryService = CategoryService();
  final GlobalKey<MakingProcessEditorState> _makingProcessKey = GlobalKey();

  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  late final TextEditingController stockController;
  late final TextEditingController discountController;

  late Future<List<CategoryModel>> _categoriesFuture;
  int? selectedCategoryId;
  String? selectedCraftType;
  String? selectedMaterial;
  String? selectedOccasion;
  List<String> selectedTags = [];
  bool isFreeShipping = false;
  bool isCodAvailable = false;
  bool isSaving = false;
  List<PickedMediaItem> _media = [];
  List<ImageOptionDraft> _imageOptions = [];
  bool _useOnePrice = true;

  @override
  void initState() {
    super.initState();
    final p = widget.product;

    nameController = TextEditingController(text: p.productName);
    descriptionController = TextEditingController(text: p.description);
    priceController = TextEditingController(text: p.price.toString());
    stockController = TextEditingController(text: p.stock.toString());
    discountController = TextEditingController(
      text: p.discountPercent > 0 ? p.discountPercent.toString() : "",
    );
    selectedCategoryId = p.categoryId;
    selectedCraftType = p.craftType;
    selectedMaterial = p.material;
    selectedOccasion = p.occasion;
    isFreeShipping = p.freeShipping;
    isCodAvailable = p.codAvailable;
    _media = p.media.isNotEmpty
        ? p.media
              .map((item) => PickedMediaItem(type: item.type, path: item.path))
              .toList()
        : [PickedMediaItem(type: ProductMediaType.image, path: p.image)];
    _useOnePrice = !p.hasImageOptions;
    _imageOptions = p.options
        .map(
          (option) => ImageOptionDraft(
            id: option.id,
            imagePath: option.image,
            name: option.name,
            priceText: option.price.toStringAsFixed(2),
            stockText: option.stock.toString(),
            isDefault: option.isDefault,
          ),
        )
        .toList();
    if (!_useOnePrice && _imageOptions.isEmpty) _syncImageOptions(_media);

    _categoriesFuture = _categoryService.getCategories();
    _loadTags();
  }

  Future<void> _loadTags() async {
    if (widget.product.id == null) return;
    final tags = await _productRepository.getTagsForProduct(widget.product.id!);
    if (!mounted) return;
    setState(() => selectedTags = tags);
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    discountController.dispose();
    super.dispose();
  }

  void _syncImageOptions(List<PickedMediaItem> updated) {
    final existing = {
      for (final option in _imageOptions) option.imagePath: option,
    };
    final images = updated
        .where((item) => item.type == ProductMediaType.image)
        .toList();
    final synced = <ImageOptionDraft>[];
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      synced.add(
        existing[image.path] ??
            ImageOptionDraft(
              id: 'option_${DateTime.now().microsecondsSinceEpoch}_$index',
              imagePath: image.path,
              name: 'Option ${index + 1}',
              priceText: priceController.text,
              stockText: stockController.text,
              isDefault:
                  index == 0 &&
                  !_imageOptions.any((option) => option.isDefault),
            ),
      );
    }
    if (synced.isNotEmpty && !synced.any((option) => option.isDefault)) {
      synced[0] = synced[0].copyWith(isDefault: true);
    }
    setState(() {
      _media = updated;
      _imageOptions = synced;
    });
  }

  void _setPricingMode(bool useOnePrice) {
    if (!useOnePrice && _imageOptions.isEmpty) {
      _syncImageOptions(_media);
    }
    setState(() => _useOnePrice = useOnePrice);
  }

  Future<List<PickedMediaItem>> _uploadPendingMedia(
    List<PickedMediaItem> items,
  ) async {
    final uploaded = <PickedMediaItem>[];
    for (final item in items) {
      if (item.path.startsWith('http://') || item.path.startsWith('https://')) {
        uploaded.add(item);
        continue;
      }
      final url = await CloudinaryService.upload(
        File(item.path),
        resourceType: item.type == ProductMediaType.video ? 'video' : 'image',
      );
      uploaded.add(PickedMediaItem(type: item.type, path: url));
    }
    return uploaded;
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (!(_makingProcessKey.currentState?.validate() ?? true)) return;

    if (selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text("Please select a category."),
        ),
      );
      return;
    }

    final hasPhoto = _media.any((item) => item.type == ProductMediaType.image);
    if (!hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo.')),
      );
      return;
    }
    if (!_useOnePrice) {
      if (_imageOptions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one picture for picture pricing.'),
          ),
        );
        return;
      }
      final names = _imageOptions
          .map((option) => option.name.trim().toLowerCase())
          .toList();
      if (names.toSet().length != names.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Each picture option needs a unique name.'),
          ),
        );
        return;
      }
    }

    setState(() => isSaving = true);

    late final List<PickedMediaItem> uploadedMedia;
    try {
      uploadedMedia = await _uploadPendingMedia(_media);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't upload photos/videos: $error")),
      );
      return;
    }
    final uploadedByOriginalPath = <String, String>{};
    for (var index = 0; index < _media.length; index++) {
      uploadedByOriginalPath[_media[index].path] = uploadedMedia[index].path;
    }
    final options = _useOnePrice
        ? const <ProductOptionModel>[]
        : [
            for (final option in _imageOptions)
              ProductOptionModel(
                id: option.id,
                name: option.name.trim(),
                image:
                    uploadedByOriginalPath[option.imagePath] ??
                    option.imagePath,
                price: double.parse(option.priceText.trim()),
                stock: int.parse(option.stockText.trim()),
                isDefault: option.isDefault,
              ),
          ];
    final defaultOption = options.isEmpty
        ? null
        : options.firstWhere(
            (option) => option.isDefault,
            orElse: () => options.first,
          );
    final coverImage = uploadedMedia
        .firstWhere((item) => item.type == ProductMediaType.image)
        .path;
    final mediaRows = <ProductMediaModel>[
      for (var index = 0; index < uploadedMedia.length; index++)
        ProductMediaModel(
          productId: widget.product.id!,
          type: uploadedMedia[index].type,
          path: uploadedMedia[index].path,
          position: index,
        ),
    ];

    final updated = ProductModel(
      id: widget.product.id,
      sellerId: widget.product.sellerId,
      categoryId: selectedCategoryId!,
      productName: nameController.text.trim(),
      description: descriptionController.text.trim(),
      price: _useOnePrice
          ? double.parse(priceController.text.trim())
          : defaultOption!.price,
      stock: _useOnePrice
          ? int.parse(stockController.text.trim())
          : options.fold(0, (total, option) => total + option.stock),
      image: coverImage,
      rating: widget.product.rating,
      craftType: selectedCraftType,
      material: selectedMaterial,
      occasion: selectedOccasion,
      discountPercent: int.tryParse(discountController.text.trim()) ?? 0,
      freeShipping: isFreeShipping,
      codAvailable: isCodAvailable,
      // This screen doesn't have gallery-editing UI, so carry the
      // existing photo/video set through unchanged rather than wiping
      // it out (the whole Firestore doc gets overwritten on save).
      media: mediaRows,
      tags: selectedTags,
      reviewCount: widget.product.reviewCount,
      totalSold: widget.product.totalSold,
      makingProcess: _makingProcessKey.currentState?.value,
      pricingMode: _useOnePrice ? 'single' : 'per_image',
      options: options,
    );

    try {
      await _productRepository.updateProduct(widget.product.id!, updated);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          content: Text(
            error is StateError
                ? error.message
                : "Couldn't save changes: $error",
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text("\"${updated.productName}\" updated."),
      ),
    );

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Edit Product",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel('Photos & Videos'),
              const SizedBox(height: 8),
              MediaPickerGrid(items: _media, onChanged: _syncImageOptions),

              const SizedBox(height: 18),

              ImagePricingEditor(
                useOnePrice: _useOnePrice,
                media: _media,
                options: _imageOptions,
                onUseOnePriceChanged: _setPricingMode,
                onOptionsChanged: (value) {
                  setState(() => _imageOptions = value);
                },
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Product Name"),
              const SizedBox(height: 8),
              CustomTextField(
                controller: nameController,
                hintText: "e.g. Handwoven Rattan Basket",
                icon: Icons.label_outline_rounded,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Product name is required";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Description"),
              const SizedBox(height: 8),
              CustomTextField(
                controller: descriptionController,
                hintText: "Describe your craft — materials, size, care...",
                icon: Icons.notes_rounded,
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Description is required";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              if (_useOnePrice)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FieldLabel("Price (₱)"),
                          const SizedBox(height: 8),
                          CustomTextField(
                            controller: priceController,
                            hintText: "0.00",
                            icon: Icons.sell_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Required";
                              }
                              final parsed = double.tryParse(value.trim());
                              if (parsed == null || parsed <= 0) {
                                return "Enter a valid price";
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FieldLabel("Stock"),
                          const SizedBox(height: 8),
                          CustomTextField(
                            controller: stockController,
                            hintText: "0",
                            icon: Icons.inventory_2_outlined,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Required";
                              }
                              final parsed = int.tryParse(value.trim());
                              if (parsed == null || parsed < 0) {
                                return "Enter a valid amount";
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 18),

              const _FieldLabel("Discount (%)"),
              const SizedBox(height: 8),
              CustomTextField(
                controller: discountController,
                hintText: "0",
                icon: Icons.percent_rounded,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return null;
                  }
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null || parsed < 0 || parsed > 100) {
                    return "Enter a value between 0 and 100";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Category"),
              const SizedBox(height: 8),
              CategoryPickerField(
                categoriesFuture: _categoriesFuture,
                selectedCategoryId: selectedCategoryId,
                onChanged: (value) {
                  setState(() => selectedCategoryId = value);
                },
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Craft Type"),
              const SizedBox(height: 8),
              SimpleOptionPickerField(
                label: "Craft Type",
                options: craftTypes,
                selected: selectedCraftType,
                onChanged: (value) => setState(() => selectedCraftType = value),
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Material"),
              const SizedBox(height: 8),
              SimpleOptionPickerField(
                label: "Material",
                options: materials,
                selected: selectedMaterial,
                onChanged: (value) => setState(() => selectedMaterial = value),
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Occasion"),
              const SizedBox(height: 8),
              SimpleOptionPickerField(
                label: "Occasion",
                options: occasions,
                selected: selectedOccasion,
                onChanged: (value) => setState(() => selectedOccasion = value),
              ),

              const SizedBox(height: 18),

              const _FieldLabel("Tags"),
              const SizedBox(height: 8),
              TagSelectorField(
                options: productTagOptions,
                selected: selectedTags,
                onChanged: (value) => setState(() => selectedTags = value),
              ),

              const SizedBox(height: 18),

              MakingProcessEditor(
                key: _makingProcessKey,
                initialValue: widget.product.makingProcess,
              ),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.success,
                  title: const Text(
                    "Free Shipping",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    "Show a Free Shipping badge on this product.",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: isFreeShipping,
                  onChanged: (value) => setState(() => isFreeShipping = value),
                ),
              ),

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.secondary,
                  title: const Text(
                    "Cash on Delivery (COD)",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    "Let customers pay for this product on delivery.",
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: isCodAvailable,
                  onChanged: (value) => setState(() => isCodAvailable = value),
                ),
              ),

              const SizedBox(height: 32),

              isSaving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : CustomButton(
                      text: "SAVE CHANGES",
                      onPressed: _updateProduct,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    );
  }
}
