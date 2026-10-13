import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A tappable field that opens a bottom sheet listing plain string
/// options (Craft Type, Material, Occasion...) for a single pick.
/// Optional by design — [selected] can be cleared via the "None"
/// row, since these taxonomy fields aren't required to list a
/// product.
class SimpleOptionPickerField extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const SimpleOptionPickerField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Select $label",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      ListTile(
                        dense: true,
                        title: const Text(
                          "None",
                          style: TextStyle(
                            fontSize: 14.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: selected == null
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, ""),
                      ),
                      for (final option in options)
                        ListTile(
                          dense: true,
                          title: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 14.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          trailing: option == selected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.primary,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, option),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // "" from the None row means "clear the selection" — distinct
    // from a dismissed sheet (null), which changes nothing.
    if (result == "") {
      onChanged(null);
    } else if (result != null) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _openPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected ?? "Select $label (optional)",
                style: TextStyle(
                  color: selected == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontWeight: selected == null
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
