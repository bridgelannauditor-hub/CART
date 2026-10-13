import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChanged;

  const SearchBarWidget({
    super.key,
    this.controller,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: onFocusChanged,
      child: TextField(
        controller: controller,
        readOnly: onTap != null,
        onTap: onTap,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: "Search handmade products...",
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 20,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
