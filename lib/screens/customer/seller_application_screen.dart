import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../constants/app_colors.dart';
import '../../repositories/seller_application_repository.dart';
import '../../services/session_service.dart';
import '../../utils/validators.dart';

class SellerApplicationScreen extends StatefulWidget {
  /// Terms version the applicant accepts; supplied by the server.
  final String termsVersion;

  const SellerApplicationScreen({super.key, required this.termsVersion});

  @override
  State<SellerApplicationScreen> createState() =>
      _SellerApplicationScreenState();
}

class _SellerApplicationScreenState extends State<SellerApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController(text: SessionService.firstName);
  final _lastName = TextEditingController(text: SessionService.lastName);
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
  bool _submitting = false;
  bool _termsAccepted = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
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
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accept the Seller terms to continue.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final status = await SellerApplicationRepository().submit({
        'acceptedTermsVersion': widget.termsVersion,
        'sellerType': _sellerType,
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'birthDate': _birthDate.text,
        'address': _address.text.trim(),
        'identityDocumentType': _identityDocumentType,
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
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      // Server validation messages are written for applicants.
      final reason = error is PostgrestException && error.message.isNotEmpty
          ? error.message
          : 'The application could not be submitted. Your account was not '
                'upgraded. Please review the form and retry.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Become a Seller')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'Your Buyer account stays active while this application is reviewed. Submitting this form does not grant Seller access.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            const _SellerRequirementsCard(),
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
            const _SectionLabel(
              'Personal information',
              hint:
                  'Enter these exactly as they appear on your ID. An '
                  'administrator will compare them with your ID photos.',
            ),
            TextFormField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (value) => Validators.name(value, label: 'First name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.familyName],
              decoration: const InputDecoration(labelText: 'Last name'),
              validator: (value) => Validators.name(value, label: 'Last name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _birthDate,
              readOnly: true,
              onTap: _pickBirthDate,
              decoration: const InputDecoration(
                labelText: 'Birthdate',
                hintText: 'Tap to choose',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              validator: (value) =>
                  Validators.required(value, label: 'Birthdate'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.fullStreetAddress],
              decoration: const InputDecoration(
                labelText: 'Complete address',
                hintText: 'House no., street, barangay, city, province',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Complete address is required';
                if (text.length < 10) {
                  return 'Include the street, barangay, city and province';
                }
                return null;
              },
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
            TextFormField(
              controller: _payoutName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Payout Account Name',
                helperText: 'The name your earnings will be paid to',
              ),
              validator: (value) =>
                  Validators.name(value, label: 'Payout Account Name'),
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
              'Next, you will take photos of your ID and a selfie with your camera. They are stored privately, and an administrator checks that your details match your ID before approving you.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _termsAccepted,
              onChanged: (value) =>
                  setState(() => _termsAccepted = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'I accept the Cart Seller terms (version ${widget.termsVersion}), '
                'including identity verification and shop review.',
              ),
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

class _SectionLabel extends StatelessWidget {
  final String title;
  final String? hint;

  const _SectionLabel(this.title, {this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SellerRequirementsCard extends StatelessWidget {
  const _SellerRequirementsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seller requirements',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          _Requirement(
            icon: Icons.badge_outlined,
            text: 'A valid, unexpired government or school ID',
          ),
          _Requirement(
            icon: Icons.camera_alt_outlined,
            text: 'Camera access to photograph your ID and take a selfie',
          ),
          _Requirement(
            icon: Icons.storefront_outlined,
            text: 'Accurate applicant and shop information',
          ),
          _Requirement(
            icon: Icons.fact_check_outlined,
            text:
                'Acceptance of the current Seller terms and final administrator approval',
          ),
        ],
      ),
    );
  }
}

class _Requirement extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Requirement({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
