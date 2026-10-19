import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../data/craft_categories.dart';
import '../../models/seller_onboarding_model.dart';
import '../../repositories/seller_application_repository.dart';

/// Step 5: shop details. The server accepts this only after identity
/// verification has succeeded; submitting sends the shop for final approval.
class SellerShopSetupScreen extends StatefulWidget {
  final SellerApplicationState application;

  const SellerShopSetupScreen({super.key, required this.application});

  @override
  State<SellerShopSetupScreen> createState() => _SellerShopSetupScreenState();
}

class _SellerShopSetupScreenState extends State<SellerShopSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.application.shopName);
  late final _description = TextEditingController(
    text: widget.application.shopDescription,
  );
  late final _city = TextEditingController(text: widget.application.shopCity);
  late String? _category = widget.application.shopCategory;
  bool _saving = false;

  static final _shopNamePattern = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 &'.,-]*$");

  List<String> get _categories => [
    for (final group in craftCategoryGroups) group.title,
  ];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save({required bool submit}) async {
    if (submit && !_formKey.currentState!.validate()) return;
    if (!submit && _name.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a shop name to save a draft.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SellerApplicationRepository().saveShop({
        'shopName': _name.text.trim(),
        'shopDescription': _description.text.trim(),
        'shopCategory': _category,
        'shopCity': _city.text.trim(),
      }, submit: submit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submit ? 'Shop submitted for final approval.' : 'Draft saved.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == '23505'
                ? 'That shop name is already taken.'
                : 'The shop could not be saved. Check the details and retry.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The shop could not be saved. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Set Up Your Shop')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Your shop is reviewed before it goes live. Handmade items only; prohibited items lead to rejection.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Shop name'),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.length < 3) return 'Use at least 3 characters.';
                if (!_shopNamePattern.hasMatch(name)) {
                  return 'Use letters, numbers, and simple punctuation only.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categories.contains(_category) ? _category : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Main craft'),
              items: [
                for (final name in _categories)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) => setState(() => _category = value),
              validator: (value) =>
                  value == null ? 'Choose your main craft.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'What do you make?',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 20
                  ? 'Describe your crafts in at least 20 characters.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'City / municipality',
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter where you ship from.'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : () => _save(submit: true),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SUBMIT FOR APPROVAL'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : () => _save(submit: false),
              child: const Text('SAVE DRAFT'),
            ),
          ],
        ),
      ),
    );
  }
}
