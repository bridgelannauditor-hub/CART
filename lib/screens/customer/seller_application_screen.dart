import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../repositories/seller_application_repository.dart';
import '../../utils/validators.dart';

class SellerApplicationScreen extends StatefulWidget {
  const SellerApplicationScreen({super.key});

  @override
  State<SellerApplicationScreen> createState() =>
      _SellerApplicationScreenState();
}

class _SellerApplicationScreenState extends State<SellerApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _birthDate = TextEditingController();
  final _address = TextEditingController();
  final _payoutName = TextEditingController();
  final _schoolEmail = TextEditingController();
  final _organization = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _businessType = TextEditingController();
  final _businessTaxId = TextEditingController();
  final _businessAddress = TextEditingController();
  final _representativeRole = TextEditingController();

  String _sellerType = 'individual';
  String _identityDocumentType = 'national_id';
  String _payoutMethod = 'gcash';
  bool _submitting = false;

  @override
  void dispose() {
    for (final controller in [
      _birthDate,
      _address,
      _payoutName,
      _schoolEmail,
      _organization,
      _registrationNumber,
      _businessType,
      _businessTaxId,
      _businessAddress,
      _representativeRole,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(DateTime.now().year - 18),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected == null) return;
    _birthDate.text = selected.toIso8601String().split('T').first;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final status = await SellerApplicationRepository().submit({
        'sellerType': _sellerType,
        'birthDate': _birthDate.text,
        'address': _address.text.trim(),
        'identityDocumentType': _identityDocumentType,
        'payoutMethod': _payoutMethod,
        'payoutAccountName': _payoutName.text.trim(),
        'schoolEmail': _sellerType == 'student'
            ? _schoolEmail.text.trim().toLowerCase()
            : null,
        'organizationName': _sellerType == 'business'
            ? _organization.text.trim()
            : null,
        'businessRegistrationNumber': _sellerType == 'business'
            ? _registrationNumber.text.trim()
            : null,
        'businessType': _sellerType == 'business'
            ? _businessType.text.trim()
            : null,
        'businessTaxId': _sellerType == 'business'
            ? _businessTaxId.text.trim()
            : null,
        'businessAddress': _sellerType == 'business'
            ? _businessAddress.text.trim()
            : null,
        'representativeRole': _sellerType == 'business'
            ? _representativeRole.text.trim()
            : null,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'under_review'
                ? 'Application submitted for review.'
                : 'Application saved with status: $status.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The application could not be submitted. Your account was not upgraded. Please review the form and retry.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Apply to Sell')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Your Buyer account stays active while this application is reviewed. Submitting this form does not grant Seller access.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _sellerType,
              decoration: const InputDecoration(labelText: 'Applicant type'),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('Student')),
                DropdownMenuItem(
                  value: 'individual',
                  child: Text('Individual'),
                ),
                DropdownMenuItem(value: 'business', child: Text('Business')),
              ],
              onChanged: (value) => setState(() => _sellerType = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _birthDate,
              readOnly: true,
              onTap: _pickBirthDate,
              decoration: const InputDecoration(
                labelText: 'Birth date',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              validator: (value) =>
                  Validators.required(value, label: 'Birth date'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: (value) =>
                  Validators.required(value, label: 'Address'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _identityDocumentType,
              decoration: const InputDecoration(
                labelText: 'Government ID type',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'national_id',
                  child: Text('National ID'),
                ),
                DropdownMenuItem(value: 'passport', child: Text('Passport')),
                DropdownMenuItem(
                  value: 'drivers_license',
                  child: Text("Driver's license"),
                ),
                DropdownMenuItem(
                  value: 'student_id',
                  child: Text('Student ID'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _identityDocumentType = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _payoutMethod,
              decoration: const InputDecoration(
                labelText: 'Preferred payout method',
              ),
              items: const [
                DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                DropdownMenuItem(value: 'maya', child: Text('Maya')),
                DropdownMenuItem(value: 'bank', child: Text('Bank account')),
              ],
              onChanged: (value) => setState(() => _payoutMethod = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _payoutName,
              decoration: const InputDecoration(
                labelText: 'Payout account name',
              ),
              validator: (value) =>
                  Validators.required(value, label: 'Payout account name'),
            ),
            if (_sellerType == 'student') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _schoolEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'School email'),
                validator: Validators.schoolEmail,
              ),
            ],
            if (_sellerType == 'business') ...[
              const SizedBox(height: 12),
              _requiredField(_organization, 'Organization name'),
              const SizedBox(height: 12),
              _requiredField(_registrationNumber, 'Registration number'),
              const SizedBox(height: 12),
              _requiredField(_businessType, 'Business type'),
              const SizedBox(height: 12),
              _requiredField(_businessTaxId, 'Business tax ID'),
              const SizedBox(height: 12),
              _requiredField(_businessAddress, 'Business address', maxLines: 2),
              const SizedBox(height: 12),
              _requiredField(_representativeRole, 'Representative role'),
            ],
            const SizedBox(height: 20),
            const Text(
              'Identity images, liveness, face matching, and final approval require the secure verification service and are not completed by this form.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SUBMIT APPLICATION'),
            ),
          ],
        ),
      ),
    );
  }

  TextFormField _requiredField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (value) => Validators.required(value, label: label),
    );
  }
}
