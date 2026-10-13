import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A wrap of tappable chips for picking any number of tags from a
/// curated list (Handmade, Customizable, Gift-Ready...).
class TagSelectorField extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const TagSelectorField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  void _toggle(String tag) {
    final updated = List<String>.from(selected);
    if (updated.contains(tag)) {
      updated.remove(tag);
    } else {
      updated.add(tag);
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _buildChip(option, selected.contains(option)),
      ],
    );
  }

  Widget _buildChip(String option, bool isSelected) {
    return InkWell(
      onTap: () => _toggle(option),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.lightGrey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              option,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
