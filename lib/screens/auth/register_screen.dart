import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../data/seller_verification_requirements.dart';
import '../../models/seller_verification_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../utils/routes.dart';
import '../../utils/validators.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

class RegisterScreen extends StatefulWidget {
  final String initialAccountType;

  const RegisterScreen({super.key, required this.initialAccountType})
    : assert(
        initialAccountType == 'Customer' || initialAccountType == 'Seller',
      );

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final birthDateController = TextEditingController();
  final addressController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final shopNameController = TextEditingController();
  final schoolEmailController = TextEditingController();
  final organizationNameController = TextEditingController();
  final credentialExpiryController = TextEditingController();
  final businessRegistrationController = TextEditingController();
  final businessTaxIdController = TextEditingController();
  final businessAddressController = TextEditingController();
  final representativeRoleController = TextEditingController();
  final payoutAccountNameController = TextEditingController();

  int sellerStep = 0;
  String sellerType = 'student';
  String identityDocumentType = 'student_id';
  String payoutMethod = 'gcash';
  String businessType = 'sole_proprietorship';
  String? shopAccountMethod;
  XFile? idFront;
  XFile? idBack;
  XFile? facePhoto;
  bool faceConsent = false;
  bool businessDeclaration = false;
  bool agreeTerms = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool isSubmitting = false;

  bool get isSeller => widget.initialAccountType == 'Seller';
  SellerTypeRequirements get requirements =>
      sellerTypeRequirements[sellerType]!;

  @override
  void dispose() {
    for (final controller in [
      firstNameController,
      lastNameController,
      birthDateController,
      addressController,
      emailController,
      phoneController,
      passwordController,
      confirmPasswordController,
      shopNameController,
      schoolEmailController,
      organizationNameController,
      credentialExpiryController,
      businessRegistrationController,
      businessTaxIdController,
      businessAddressController,
      representativeRoleController,
      payoutAccountNameController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectSellerType(String value) {
    setState(() {
      sellerType = value;
      identityDocumentType =
          sellerTypeRequirements[value]!.identityDocuments.keys.first;
      idFront = null;
      idBack = null;
      facePhoto = null;
    });
  }

  Future<void> _captureId({required bool front}) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() => front ? idFront = image : idBack = image);
  }

  Future<void> _captureFace() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() => facePhoto = image);
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    required bool birthDate,
  }) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: birthDate ? DateTime(now.year - 120) : now,
      lastDate: birthDate
          ? DateTime(now.year - 18, now.month, now.day)
          : DateTime(now.year + 10),
      initialDate: birthDate
          ? DateTime(now.year - 18, now.month, now.day)
          : DateTime(now.year + 1),
    );
    if (selected == null) return;
    controller.text =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _continueSellerFlow() {
    if (sellerStep == 1 && (idFront == null || idBack == null)) {
      _showError('Take a clear photo of the front and back of your ID.');
      return;
    }
    if (sellerStep == 2 && (facePhoto == null || !faceConsent)) {
      _showError('Take a live face photo and accept the verification consent.');
      return;
    }
    if (sellerStep == 3 && !_validateIdentityDetails()) return;
    setState(() => sellerStep++);
  }

  bool _validateIdentityDetails() {
    if (firstNameController.text.trim().length < 2 ||
        lastNameController.text.trim().length < 2 ||
        birthDateController.text.isEmpty ||
        addressController.text.trim().length < 10) {
      _showError(
        'Complete your legal name, date of birth, and current address.',
      );
      return false;
    }
    if (sellerType == 'student' &&
        (organizationNameController.text.trim().isEmpty ||
            Validators.schoolEmail(schoolEmailController.text) != null ||
            credentialExpiryController.text.isEmpty)) {
      _showError('Complete your current student information.');
      return false;
    }
    if (sellerType == 'business' &&
        (organizationNameController.text.trim().isEmpty ||
            businessRegistrationController.text.trim().isEmpty ||
            businessTaxIdController.text.trim().isEmpty ||
            businessAddressController.text.trim().length < 10 ||
            representativeRoleController.text.trim().isEmpty ||
            !businessDeclaration)) {
      _showError(
        'Complete the business details and authorization declaration.',
      );
      return false;
    }
    payoutAccountNameController.text =
        '${firstNameController.text.trim()} ${lastNameController.text.trim()}';
    return true;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!agreeTerms) {
      _showError('Please accept the Terms & Conditions.');
      return;
    }
    if (isSeller && (idFront == null || idBack == null || facePhoto == null)) {
      _showError('Your ID and live face photos are required.');
      return;
    }
    setState(() => isSubmitting = true);
    final user = UserModel(
      firstName: firstNameController.text.trim(),
      lastName: lastNameController.text.trim(),
      email: emailController.text.trim(),
      phone: phoneController.text.trim(),
      accountType: widget.initialAccountType,
      shopName: isSeller ? shopNameController.text.trim() : null,
      sellerVerification: isSeller
          ? SellerVerificationModel(
              sellerType: sellerType,
              birthDate: birthDateController.text,
              address: addressController.text.trim(),
              identityDocumentType: identityDocumentType,
              payoutMethod: payoutMethod,
              payoutAccountName: payoutAccountNameController.text.trim(),
              organizationName: organizationNameController.text.trim().isEmpty
                  ? null
                  : organizationNameController.text.trim(),
              businessRegistrationNumber: sellerType == 'business'
                  ? businessRegistrationController.text.trim()
                  : null,
              schoolEmail: sellerType == 'student'
                  ? schoolEmailController.text.trim().toLowerCase()
                  : null,
              credentialExpiry: sellerType == 'student'
                  ? credentialExpiryController.text
                  : null,
              businessType: sellerType == 'business' ? businessType : null,
              businessTaxId: sellerType == 'business'
                  ? businessTaxIdController.text.trim()
                  : null,
              businessAddress: sellerType == 'business'
                  ? businessAddressController.text.trim()
                  : null,
              representativeRole: sellerType == 'business'
                  ? representativeRoleController.text.trim()
                  : null,
              identityCaptureCompleted: idFront != null && idBack != null,
              faceCaptureCompleted: facePhoto != null,
            )
          : null,
      createdAt: DateTime.now().toIso8601String(),
    );
    final result = await AuthService().register(
      user,
      password: passwordController.text,
    );
    if (!mounted) return;
    setState(() => isSubmitting = false);
    if (result != 'success') {
      _showError(result);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Customer account created. Check your email to verify it. You can apply to sell after signing in.',
        ),
      ),
    );
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          tooltip: isSeller && sellerStep > 0 ? 'Previous step' : 'Back',
          onPressed: () {
            if (isSeller && sellerStep == 4 && shopAccountMethod != null) {
              setState(() => shopAccountMethod = null);
            } else if (isSeller && sellerStep > 0) {
              setState(() => sellerStep--);
            } else {
              Navigator.maybePop(context);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(isSeller ? 'Seller application' : 'Create account'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: isSeller ? _buildSellerFlow() : _buildCustomerForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSellerFlow() {
    final content = switch (sellerStep) {
      0 => _sellerTypeStep(),
      1 => _identityDocumentStep(),
      2 => _faceVerificationStep(),
      3 => _identityDetailsStep(),
      _ => _accountDetailsStep(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(sellerStep), child: content),
        ),
        const SizedBox(height: 22),
        if (sellerStep < 4)
          FilledButton.icon(
            onPressed: _continueSellerFlow,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(sellerStep == 2 ? 'SUBMIT FOR REVIEW' : 'CONTINUE'),
          ),
      ],
    );
  }

  Widget _stepHeader() {
    const labels = ['Type', 'ID', 'Face', 'Details', 'Shop'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${sellerStep + 1} of 5',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(labels.length, (index) {
            final active = index <= sellerStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 4 ? 0 : 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 5,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(labels[index], style: const TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _sellerTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What type of seller are you?',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        const Text(
          'We only ask for documents that fit how you sell.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        for (final entry in sellerTypeRequirements.entries) ...[
          _selectionCard(entry.value),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _selectionCard(SellerTypeRequirements item) {
    final selected = item.key == sellerType;
    return InkWell(
      onTap: () => _selectSellerType(item.key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .06)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.lightGrey,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.key == 'student'
                  ? Icons.school_outlined
                  : item.key == 'business'
                  ? Icons.business_outlined
                  : Icons.person_outline,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  for (final requirement in item.requirements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '• $requirement',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityDocumentStep() {
    return _applicationCard(
      title: 'Verify your identity',
      subtitle:
          'Choose an accepted ID, then take new photos. Gallery uploads are disabled.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: identityDocumentType,
          decoration: _decoration('ID type', Icons.badge_outlined),
          items: requirements.identityDocuments.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (value) => setState(() => identityDocumentType = value!),
        ),
        const SizedBox(height: 14),
        _captureTile(
          title: 'Front of ID',
          subtitle: 'Show all four corners and avoid glare.',
          captured: idFront != null,
          onTap: () => _captureId(front: true),
        ),
        const SizedBox(height: 10),
        _captureTile(
          title: identityDocumentType == 'passport'
              ? 'Passport supporting page'
              : 'Back of ID',
          subtitle: 'Make every printed detail readable.',
          captured: idBack != null,
          onTap: () => _captureId(front: false),
        ),
      ],
    );
  }

  Widget _faceVerificationStep() {
    return _applicationCard(
      title: 'Live face verification',
      subtitle:
          'Take a live selfie. A verification service will compare it with your ID during review.',
      children: [
        _captureTile(
          title: 'Live face photo',
          subtitle: 'Face the camera in even lighting. Remove hats and masks.',
          captured: facePhoto != null,
          onTap: _captureFace,
          face: true,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: faceConsent,
          onChanged: (value) => setState(() => faceConsent = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I consent to using my ID and live face image only for identity verification and fraud prevention.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const _Notice(
          icon: Icons.schedule_outlined,
          text:
              'You can enter your details while the review is pending. Your shop cannot publish listings until approval.',
        ),
      ],
    );
  }

  Widget _identityDetailsStep() {
    return _applicationCard(
      title: 'Enter details exactly as shown',
      subtitle: 'The reviewer checks these details against your captured ID.',
      children: [
        _nameFields(readOnly: false),
        const SizedBox(height: 10),
        TextFormField(
          controller: birthDateController,
          readOnly: true,
          onTap: () => _pickDate(birthDateController, birthDate: true),
          decoration: _decoration('Date of birth', Icons.cake_outlined),
        ),
        const SizedBox(height: 10),
        CustomTextField(
          controller: addressController,
          hintText: 'Current residential address',
          icon: Icons.location_on_outlined,
          maxLines: 2,
        ),
        if (sellerType == 'student') ..._studentFields(),
        if (sellerType == 'business') ..._businessFields(),
      ],
    );
  }

  List<Widget> _studentFields() => [
    const SizedBox(height: 10),
    CustomTextField(
      controller: organizationNameController,
      hintText: 'School name',
      icon: Icons.school_outlined,
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: schoolEmailController,
      hintText: 'Official school email (.edu.ph)',
      icon: Icons.alternate_email_rounded,
      keyboardType: TextInputType.emailAddress,
    ),
    const SizedBox(height: 10),
    TextFormField(
      controller: credentialExpiryController,
      readOnly: true,
      onTap: () => _pickDate(credentialExpiryController, birthDate: false),
      decoration: _decoration(
        'Student credential expiry',
        Icons.event_available_outlined,
      ),
    ),
  ];

  List<Widget> _businessFields() => [
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(
      initialValue: businessType,
      decoration: _decoration('Business type', Icons.corporate_fare_outlined),
      items:
          const {
                'sole_proprietorship': 'Sole proprietorship',
                'partnership': 'Partnership',
                'corporation': 'Corporation',
                'cooperative': 'Cooperative',
              }.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
      onChanged: (value) => setState(() => businessType = value!),
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: organizationNameController,
      hintText: 'Registered business name',
      icon: Icons.business_outlined,
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: businessRegistrationController,
      hintText: 'DTI / SEC / CDA registration number',
      icon: Icons.numbers_outlined,
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: businessTaxIdController,
      hintText: 'Business tax ID (TIN)',
      icon: Icons.receipt_long_outlined,
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: businessAddressController,
      hintText: 'Registered business address',
      icon: Icons.location_city_outlined,
      maxLines: 2,
    ),
    const SizedBox(height: 10),
    CustomTextField(
      controller: representativeRoleController,
      hintText: 'Your role in the business',
      icon: Icons.work_outline,
    ),
    CheckboxListTile(
      value: businessDeclaration,
      onChanged: (value) =>
          setState(() => businessDeclaration = value ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text(
        'I am authorized to create and manage this seller account.',
        style: TextStyle(fontSize: 13),
      ),
    ),
  ];

  Widget _accountDetailsStep() {
    if (shopAccountMethod == null) return _shopAccountMethodStep();

    if (shopAccountMethod == 'google' || shopAccountMethod == 'facebook') {
      return _socialShopNameStep(shopAccountMethod!);
    }

    return Form(
      key: _formKey,
      child: _applicationCard(
        title: 'Create your shop account',
        subtitle: 'Your verified legal name is filled automatically.',
        children: [
          CustomTextField(
            controller: shopNameController,
            hintText: 'Shop name',
            icon: Icons.storefront_outlined,
            validator: (v) => v == null || v.trim().length < 2
                ? 'Shop name is required'
                : null,
          ),
          const SizedBox(height: 10),
          _nameFields(readOnly: true),
          const SizedBox(height: 10),
          _emailField(),
          const SizedBox(height: 10),
          _phoneField(),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: payoutMethod,
            decoration: _decoration(
              'Payout method',
              Icons.account_balance_wallet_outlined,
            ),
            items:
                const {'gcash': 'GCash', 'maya': 'Maya', 'bank': 'Bank account'}
                    .entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => payoutMethod = value!),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: payoutAccountNameController,
            readOnly: true,
            decoration: _decoration(
              'Payout account holder',
              Icons.person_search_outlined,
            ),
          ),
          const SizedBox(height: 10),
          _passwordFields(),
          _terms(),
          const SizedBox(height: 12),
          const _Notice(
            icon: Icons.mark_email_read_outlined,
            text:
                'We send email confirmation after account creation. A 4-digit mobile verification step is required before payouts are enabled.',
          ),
          const SizedBox(height: 16),
          CustomButton(
            text: isSubmitting ? 'SUBMITTING...' : 'CREATE SHOP ACCOUNT',
            onPressed: isSubmitting ? null : _register,
          ),
        ],
      ),
    );
  }

  Widget _shopAccountMethodStep() {
    return _applicationCard(
      title: 'How do you want to create your shop account?',
      subtitle:
          'Choose an email and password, or use an existing Google or Facebook account.',
      children: [
        _accountMethodCard(
          icon: Icons.storefront_outlined,
          title: 'Create shop account',
          subtitle: 'Enter your contact details, payout method, and password.',
          onTap: () => setState(() => shopAccountMethod = 'password'),
          emphasized: true,
        ),
        const SizedBox(height: 12),
        _accountMethodCard(
          icon: Icons.g_mobiledata_rounded,
          title: 'Continue with Google',
          subtitle: 'Use your Google name and verified email.',
          onTap: () => setState(() => shopAccountMethod = 'google'),
        ),
        const SizedBox(height: 12),
        _accountMethodCard(
          icon: Icons.facebook,
          title: 'Continue with Facebook',
          subtitle: 'Use your Facebook account details.',
          onTap: () => setState(() => shopAccountMethod = 'facebook'),
        ),
      ],
    );
  }

  Widget _accountMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    return Material(
      color: emphasized
          ? AppColors.primary.withValues(alpha: .055)
          : AppColors.background,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: emphasized
                  ? AppColors.primary.withValues(alpha: .45)
                  : AppColors.lightGrey,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 27),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialShopNameStep(String provider) {
    final providerLabel = provider == 'google' ? 'Google' : 'Facebook';
    final providerIcon = provider == 'google'
        ? Icons.g_mobiledata_rounded
        : Icons.facebook;

    return Form(
      key: _formKey,
      child: _applicationCard(
        title: 'Name your shop',
        subtitle:
            '$providerLabel will provide your verified name, email, and sign-in.',
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Icon(providerIcon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Continue with $providerLabel',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: shopNameController,
            hintText: 'Shop name',
            icon: Icons.storefront_outlined,
            validator: (v) => v == null || v.trim().length < 2
                ? 'Shop name is required'
                : null,
          ),
          const SizedBox(height: 18),
          CustomButton(
            text: 'CONTINUE WITH ${providerLabel.toUpperCase()}',
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              _showError(
                '$providerLabel connection will open when seller OAuth application handoff is configured.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create your buyer account',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          _nameFields(readOnly: false),
          const SizedBox(height: 10),
          _emailField(),
          const SizedBox(height: 10),
          _phoneField(),
          const SizedBox(height: 10),
          _passwordFields(),
          _terms(),
          const SizedBox(height: 14),
          CustomButton(
            text: isSubmitting ? 'CREATING...' : 'CREATE ACCOUNT',
            onPressed: isSubmitting ? null : _register,
          ),
        ],
      ),
    );
  }

  Widget _nameFields({required bool readOnly}) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: firstNameController,
            readOnly: readOnly,
            decoration: _decoration('First name', Icons.person_outline),
            validator: (v) =>
                v == null || v.trim().length < 2 ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: lastNameController,
            readOnly: readOnly,
            decoration: _decoration('Last name', Icons.person_outline),
            validator: (v) =>
                v == null || v.trim().length < 2 ? 'Required' : null,
          ),
        ),
      ],
    );
  }

  Widget _emailField() => CustomTextField(
    controller: emailController,
    hintText: 'Email address',
    icon: Icons.email_outlined,
    keyboardType: TextInputType.emailAddress,
    validator: (v) =>
        v == null || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())
        ? 'Enter a valid email'
        : null,
  );

  Widget _phoneField() => CustomTextField(
    controller: phoneController,
    hintText: 'Mobile number',
    icon: Icons.phone_outlined,
    keyboardType: TextInputType.phone,
    validator: (v) => v == null || !RegExp(r'^09\d{9}$').hasMatch(v.trim())
        ? 'Enter a valid PH mobile number'
        : null,
  );

  Widget _passwordFields() => Column(
    children: [
      CustomTextField(
        controller: passwordController,
        hintText: 'Password',
        icon: Icons.lock_outline,
        obscureText: hidePassword,
        validator: (v) =>
            v == null || v.length < 8 ? 'Use at least 8 characters' : null,
        suffixIcon: IconButton(
          onPressed: () => setState(() => hidePassword = !hidePassword),
          icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
        ),
      ),
      const SizedBox(height: 10),
      CustomTextField(
        controller: confirmPasswordController,
        hintText: 'Confirm password',
        icon: Icons.lock_outline,
        obscureText: hideConfirmPassword,
        validator: (v) =>
            v != passwordController.text ? 'Passwords do not match' : null,
        suffixIcon: IconButton(
          onPressed: () =>
              setState(() => hideConfirmPassword = !hideConfirmPassword),
          icon: Icon(
            hideConfirmPassword ? Icons.visibility_off : Icons.visibility,
          ),
        ),
      ),
    ],
  );

  Widget _terms() => CheckboxListTile(
    value: agreeTerms,
    onChanged: (value) => setState(() => agreeTerms = value ?? false),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: const Text(
      'I agree to the Terms & Conditions and Privacy Policy.',
      style: TextStyle(fontSize: 13),
    ),
  );

  Widget _captureTile({
    required String title,
    required String subtitle,
    required bool captured,
    required VoidCallback onTap,
    bool face = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: captured
                ? Colors.green.withValues(alpha: .12)
                : AppColors.primary.withValues(alpha: .1),
            child: Icon(
              captured
                  ? Icons.check_rounded
                  : face
                  ? Icons.face_outlined
                  : Icons.credit_card_outlined,
              color: captured ? Colors.green : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  captured ? 'Photo captured. Tap to retake.' : subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: Text(captured ? 'Retake' : 'Camera'),
          ),
        ],
      ),
    );
  }

  Widget _applicationCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.primary.withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(height: 1.4, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.primary),
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
