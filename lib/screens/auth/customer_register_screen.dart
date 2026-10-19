import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../utils/routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

/// The only public registration screen. Every new account is a Customer.
class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _acceptedTerms = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  bool _submitting = false;
  String? _socialProvider;

  bool get _busy => _submitting || _socialProvider != null;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showMessage('Please accept the Terms & Conditions.');
      return;
    }

    setState(() => _submitting = true);
    final result = await AuthService().register(
      UserModel(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        accountType: 'Customer',
        createdAt: DateTime.now().toIso8601String(),
      ),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result != 'success') {
      _showMessage(result);
      return;
    }
    _showMessage(
      'Account created. Check your email to verify it, then sign in.',
      error: false,
    );
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  Future<void> _continueWith(String provider) async {
    if (_busy) return;
    setState(() => _socialProvider = provider);
    final auth = AuthService();
    final result = provider == 'Google'
        ? await auth.signInWithGoogle()
        : await auth.signInWithFacebook();
    if (!mounted) return;
    setState(() => _socialProvider = null);

    if (result.error != null) {
      _showMessage(result.error!);
    } else if (result.isPending) {
      _showMessage(
        'Complete $provider sign-in, then return to C+ART.',
        error: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _busy ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Create account'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Every new account starts as a customer. You can apply to become a seller after signing in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _nameFields(),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: _email,
                      hintText: 'Email address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null ||
                              !RegExp(
                                r'^[^@]+@[^@]+\.[^@]+$',
                              ).hasMatch(value.trim())
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: _phone,
                      hintText: 'Mobile number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^09\d{9}$').hasMatch(value.trim())
                          ? 'Enter a valid PH mobile number'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _passwordFields(),
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _acceptedTerms = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I agree to the Terms & Conditions and Privacy Policy.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 14),
                    CustomButton(
                      text: _submitting ? 'CREATING...' : 'CREATE ACCOUNT',
                      onPressed: _busy ? null : _createAccount,
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _continueWith('Google'),
                            child: Text(
                              _socialProvider == 'Google'
                                  ? 'OPENING...'
                                  : 'GOOGLE',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _continueWith('Facebook'),
                            child: Text(
                              _socialProvider == 'Facebook'
                                  ? 'OPENING...'
                                  : 'FACEBOOK',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Google and Facebook also create customer accounts. Seller access requires a separate in-app application, identity verification, and approval.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstName,
            decoration: _decoration('First name', Icons.person_outline),
            validator: (value) =>
                value == null || value.trim().length < 2 ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _lastName,
            decoration: _decoration('Last name', Icons.person_outline),
            validator: (value) =>
                value == null || value.trim().length < 2 ? 'Required' : null,
          ),
        ),
      ],
    );
  }

  Widget _passwordFields() {
    return Column(
      children: [
        CustomTextField(
          controller: _password,
          hintText: 'Password',
          icon: Icons.lock_outline,
          obscureText: _hidePassword,
          validator: (value) => value == null || value.length < 8
              ? 'Use at least 8 characters'
              : null,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _hidePassword = !_hidePassword),
            icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
          ),
        ),
        const SizedBox(height: 10),
        CustomTextField(
          controller: _confirmPassword,
          hintText: 'Confirm password',
          icon: Icons.lock_outline,
          obscureText: _hideConfirmation,
          validator: (value) =>
              value != _password.text ? 'Passwords do not match' : null,
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _hideConfirmation = !_hideConfirmation),
            icon: Icon(
              _hideConfirmation ? Icons.visibility_off : Icons.visibility,
            ),
          ),
        ),
      ],
    );
  }

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
