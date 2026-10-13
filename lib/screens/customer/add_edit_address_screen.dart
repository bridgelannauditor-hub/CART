import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/address_model.dart';
import '../../utils/validators.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

/// Add-new or edit-existing delivery address form. Pass an existing
/// [address] to edit it; leave it null to add a new one for
/// [userId].
class AddEditAddressScreen extends StatefulWidget {
  final int userId;
  final AddressModel? address;

  const AddEditAddressScreen({super.key, required this.userId, this.address});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _line1Controller;
  late final TextEditingController _line2Controller;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalController;

  late String _label;
  bool _isDefault = false;
  bool _isSaving = false;

  bool get _isEditing => widget.address != null;

  static const _labels = ["Home", "Work", "Other"];

  @override
  void initState() {
    super.initState();
    final a = widget.address;

    _fullNameController = TextEditingController(text: a?.fullName ?? "");
    _phoneController = TextEditingController(text: a?.phone ?? "");
    _line1Controller = TextEditingController(text: a?.line1 ?? "");
    _line2Controller = TextEditingController(text: a?.line2 ?? "");
    _cityController = TextEditingController(text: a?.city ?? "");
    _provinceController = TextEditingController(text: a?.province ?? "");
    _postalController = TextEditingController(text: a?.postalCode ?? "");
    _label = a?.label ?? "Home";
    _isDefault = a?.isDefault ?? false;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _line1Controller.dispose();
    _line2Controller.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final model = AddressModel(
      id: widget.address?.id,
      userId: widget.userId,
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.trim(),
      label: _label,
      line1: _line1Controller.text.trim(),
      line2: _line2Controller.text.trim().isEmpty
          ? null
          : _line2Controller.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      postalCode: _postalController.text.trim().isEmpty
          ? null
          : _postalController.text.trim(),
      isDefault: _isDefault,
    );

    if (_isEditing) {
      await DatabaseHelper.instance.updateAddress(model.id!, model.toMap());
    } else {
      await DatabaseHelper.instance.insertAddress(model.toMap());
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isEditing ? "Edit Address" : "Add New Address",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  controller: _fullNameController,
                  hintText: "Recipient Full Name",
                  icon: Icons.person_outline,
                  validator: (v) => Validators.name(v, label: "Recipient name"),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _phoneController,
                  hintText: "Mobile Number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _line1Controller,
                  hintText: "Street, Building, House No.",
                  icon: Icons.location_on_outlined,
                  validator: (v) =>
                      Validators.required(v, label: "Street address"),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _line2Controller,
                  hintText: "Barangay / Apartment / Unit (optional)",
                  icon: Icons.apartment_outlined,
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _cityController,
                  hintText: "City / Municipality",
                  icon: Icons.location_city_outlined,
                  validator: (v) => Validators.required(v, label: "City"),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _provinceController,
                  hintText: "Province",
                  icon: Icons.map_outlined,
                  validator: (v) => Validators.required(v, label: "Province"),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _postalController,
                  hintText: "Postal Code (optional)",
                  icon: Icons.markunread_mailbox_outlined,
                  keyboardType: TextInputType.number,
                ),

                const SizedBox(height: 18),

                const Text(
                  "LABEL AS",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  children: _labels.map((label) {
                    final selected = _label == label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => setState(() => _label = label),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : AppColors.lightGrey,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Set as default address",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    value: _isDefault,
                    activeThumbColor: AppColors.primary,
                    onChanged: (value) => setState(() => _isDefault = value),
                  ),
                ),

                const SizedBox(height: 26),

                CustomButton(
                  text: _isSaving ? "Saving..." : "Save Address",
                  onPressed: _isSaving ? () {} : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
