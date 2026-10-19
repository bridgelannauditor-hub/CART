import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class CustomButton extends StatelessWidget {
  final String text;

  final VoidCallback? onPressed;

  /// Shows a spinner and blocks taps while an async action is running.
  final bool loading;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,

      height: 55,

      child: ElevatedButton(
        onPressed: loading ? null : onPressed,

        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.lightGrey,
          disabledForegroundColor: AppColors.textSecondary,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),

        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              )
            : Text(
                text,

                style: TextStyle(
                  color: onPressed == null
                      ? AppColors.textSecondary
                      : Colors.white,

                  fontSize: 18,

                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
