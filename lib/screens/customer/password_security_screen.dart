import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../utils/validators.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

/// Lets the customer change their account password. Also surfaces a
/// couple of simple, static account-security notes.
class PasswordSecurityScreen extends StatefulWidget {
  const PasswordSecurityScreen({super.key});

  @override
  State<PasswordSecurityScreen> createState() => _PasswordSecurityScreenState();
}

class _PasswordSecurityScreenState extends State<PasswordSecurityScreen> {
  final _formKey = GlobalKey<FormState>();

  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = SessionService.userId;
    if (userId == null) return;

    setState(() => _isSaving = true);

    final result = await AuthService().changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result != "success") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: AppColors.error),
      );
      return;
    }

    _currentController.clear();
    _newController.clear();
    _confirmController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Password updated"),
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
          "Password & Security",
          style: TextStyle(fontWeight: FontWeight.w700),
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
                const Text(
                  "CHANGE PASSWORD",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _currentController,
                  hintText: "Current Password",
                  icon: Icons.lock_outline,
                  obscureText: _hideCurrent,
                  validator: (v) =>
                      Validators.required(v, label: "Current password"),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideCurrent ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _hideCurrent = !_hideCurrent),
                  ),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _newController,
                  hintText: "New Password",
                  icon: Icons.lock_outline,
                  obscureText: _hideNew,
                  validator: Validators.password,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideNew ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _hideNew = !_hideNew),
                  ),
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  controller: _confirmController,
                  hintText: "Confirm New Password",
                  icon: Icons.lock_outline,
                  obscureText: _hideConfirm,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return "Please confirm your new password";
                    }
                    if (v != _newController.text) {
                      return "Passwords do not match";
                    }
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideConfirm ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _hideConfirm = !_hideConfirm),
                  ),
                ),

                const SizedBox(height: 22),

                CustomButton(
                  text: _isSaving ? "Updating..." : "Update Password",
                  onPressed: _isSaving ? () {} : _changePassword,
                ),

                const SizedBox(height: 32),

                const Text(
                  "SECURITY TIPS",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                _TipCard(
                  icon: Icons.password_rounded,
                  text:
                      "Use a password that's at least 8 characters and "
                      "not used on any other site.",
                ),
                const SizedBox(height: 10),
                _TipCard(
                  icon: Icons.visibility_off_outlined,
                  text:
                      "Never share your password with anyone, including "
                      "C+ART staff.",
                ),
                const SizedBox(height: 10),
                _TipCard(
                  icon: Icons.logout_rounded,
                  text:
                      "Log out of C+ART on shared or public devices when "
                      "you're done shopping.",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
