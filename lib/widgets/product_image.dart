import 'dart:io';

import 'package:flutter/material.dart';

/// Renders a product image whether it's a remote URL (older products
/// that used the paste-a-link flow) or a local device file path (from
/// the on-device photo/video picker). Falls back to [placeholder] if
/// the path is empty or fails to load.
class ProductImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget placeholder;

  const ProductImage({
    super.key,
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  bool get _isNetwork =>
      path.startsWith('http://') || path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return placeholder;

    if (_isNetwork) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
