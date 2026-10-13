import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class SearchBox extends StatelessWidget {
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;

  const SearchBox({super.key, this.controller, this.onTap, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: "Search handmade gifts...",
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
