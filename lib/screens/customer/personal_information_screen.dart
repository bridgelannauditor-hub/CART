import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../utils/validators.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

/// Lets the customer view and edit their own account details —
/// name, email, and mobile number.
class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  UserModel? _user;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final userId = SessionService.userId;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final restored = await AuthService().restoreSession();
    final user = restored ?? await DatabaseHelper.instance.getUserById(userId);

    if (!mounted) return;

    if (restored != null) SessionService.loginUser(restored);

    setState(() {
      _user = user;
      _firstNameController.text = user?.firstName ?? "";
      _lastNameController.text = user?.lastName ?? "";
      _emailController.text = user?.email ?? "";
      _phoneController.text = user?.phone ?? "";
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = SessionService.userId;
    if (userId == null) return;

    setState(() => _isSaving = true);

    final result = await AuthService().updateProfile(
      userId: userId,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result != "success" && result != "email_verification_sent") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: AppColors.error),
      );
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final currentEmail = SessionService.email ?? _user?.email ?? '';
    SessionService.updateProfile(firstName: firstName, lastName: lastName);
    setState(() {
      _user = _user?.copyWith(
        firstName: firstName,
        lastName: lastName,
        email: currentEmail,
        phone: _phoneController.text.trim(),
      );
      _emailController.text = currentEmail;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == "email_verification_sent"
              ? "Profile updated. Check the new email address to verify the change."
              : "Profile updated",
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          "Personal Information",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _user == null
            ? const Center(
                child: Text(
                  "Unable to load your account.",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                          child: Text(
                            _firstNameController.text.isNotEmpty
                                ? _firstNameController.text[0].toUpperCase()
                                : "?",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      CustomTextField(
                        controller: _firstNameController,
                        hintText: "First Name",
                        icon: Icons.person_outline,
                        validator: (v) =>
                            Validators.name(v, label: "First name"),
                      ),
                      const SizedBox(height: 12),

                      CustomTextField(
                        controller: _lastNameController,
                        hintText: "Last Name",
                        icon: Icons.person_outline,
                        validator: (v) =>
                            Validators.name(v, label: "Last name"),
                      ),
                      const SizedBox(height: 12),

                      CustomTextField(
                        controller: _emailController,
                        hintText: "Email Address",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 12),

                      CustomTextField(
                        controller: _phoneController,
                        hintText: "Mobile Number",
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: Validators.optionalPhone,
                      ),

                      const SizedBox(height: 28),

                      CustomButton(
                        text: _isSaving ? "Saving..." : "Save Changes",
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
