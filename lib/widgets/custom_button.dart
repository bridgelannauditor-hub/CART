import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class CustomButton extends StatelessWidget {
  final String text;

  final VoidCallback? onPressed;

  const CustomButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,

      height: 55,

      child: ElevatedButton(
        onPressed: onPressed,

        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.lightGrey,
          disabledForegroundColor: AppColors.textSecondary,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),

        child: Text(
          text,

          style: TextStyle(
            color: onPressed == null ? AppColors.textSecondary : Colors.white,

            fontSize: 18,

            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
