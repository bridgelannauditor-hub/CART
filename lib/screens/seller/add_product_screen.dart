import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../data/product_taxonomy.dart';
import '../../models/category_model.dart';
import '../../models/product_media_model.dart';
import '../../models/product_model.dart';
import '../../models/product_option_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/category_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/session_service.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';
import '../../widgets/media_picker_grid.dart';
import '../../widgets/category_picker_field.dart';
import '../../widgets/simple_option_picker_field.dart';
import '../../widgets/tag_selector_field.dart';
import '../../widgets/making_process_editor.dart';
import '../../widgets/image_pricing_editor.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ProductRepository _productRepository = ProductRepository();
  final CategoryService _categoryService = CategoryService();
  final GlobalKey<MakingProcessEditorState> _makingProcessKey = GlobalKey();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  final TextEditingController discountController = TextEditingController();

  List<PickedMediaItem> _media = [];
  List<ImageOptionDraft> _imageOptions = [];
  bool _useOnePrice = true;

  late Future<List<CategoryModel>> _categoriesFuture;
  int? selectedCategoryId;
  String? selectedCraftType;
  String? selectedMaterial;
  String? selectedOccasion;
  List<String> selectedTags = [];
  bool isFreeShipping = false;
  bool isCodAvailable = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _categoryService.getCategories();
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

  /// Uploads any locally-picked photos/videos to Cloudinary and returns
  /// the same list with their paths swapped for permanent URLs. Items
  /// that are already network URLs (e.g. unchanged items when editing)
  /// are passed through untouched.
  Future<List<PickedMediaItem>> _uploadPendingMedia(
    List<PickedMediaItem> items,
  ) async {
    final uploaded = <PickedMediaItem>[];

    for (final item in items) {
      final isAlreadyUploaded =
          item.path.startsWith('http://') || item.path.startsWith('https://');

      if (isAlreadyUploaded) {
        uploaded.add(item);
        continue;
      }

      final url = await CloudinaryService.upload(
        File(item.path),
        resourceType: item.type == ProductMediaType.video ? "video" : "image",
      );

      uploaded.add(PickedMediaItem(type: item.type, path: url));
    }

    return uploaded;
  }

  void _setMedia(List<PickedMediaItem> updated) {
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
      _setMedia(_media);
    }
    setState(() => _useOnePrice = useOnePrice);
  }

  Future<void> _saveProduct() async {
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

    final hasPhoto = _media.any((m) => m.type == ProductMediaType.image);
    if (!hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text("Please add at least one photo."),
        ),
      );
      return;
    }

    final sellerId = SessionService.userId;
    if (sellerId == null) return;

    if (!_useOnePrice) {
      if (_imageOptions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one picture for picture pricing.'),
          ),
        );
        return;
      }
      final normalizedNames = _imageOptions
          .map((option) => option.name.trim().toLowerCase())
          .toList();
      if (normalizedNames.toSet().length != normalizedNames.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Each picture option needs a unique name.'),
          ),
        );
        return;
      }
    }

    setState(() => isSaving = true);

    List<PickedMediaItem> uploadedMedia;
    try {
      uploadedMedia = await _uploadPendingMedia(_media);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text("Couldn't upload photos/videos: $e"),
        ),
      );
      return;
    }

    final coverImage = uploadedMedia
        .firstWhere((m) => m.type == ProductMediaType.image)
        .path;

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
    final mediaRows = <ProductMediaModel>[
      for (int i = 0; i < uploadedMedia.length; i++)
        ProductMediaModel(
          productId: 0,
          type: uploadedMedia[i].type,
          path: uploadedMedia[i].path,
          position: i,
        ),
    ];

    final product = ProductModel(
      sellerId: sellerId,
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
      craftType: selectedCraftType,
      material: selectedMaterial,
      occasion: selectedOccasion,
      discountPercent: int.tryParse(discountController.text.trim()) ?? 0,
      freeShipping: isFreeShipping,
      codAvailable: isCodAvailable,
      makingProcess: _makingProcessKey.currentState?.value,
      media: mediaRows,
      tags: selectedTags.toList(),
      pricingMode: _useOnePrice ? 'single' : 'per_image',
      options: options,
    );

    try {
      await _productRepository.insertProduct(product);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          content: Text(error.message),
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
        content: Text("\"${product.productName}\" added to your shop."),
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
          "Add Product",
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
              // ---------- Photos & videos ----------
              const _FieldLabel("Photos & Videos"),
              const SizedBox(height: 8),
              MediaPickerGrid(items: _media, onChanged: _setMedia),

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

              MakingProcessEditor(key: _makingProcessKey),

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
                  : CustomButton(text: "SAVE PRODUCT", onPressed: _saveProduct),
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
