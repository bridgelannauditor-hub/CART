import 'dart:io';

import 'package:flutter/material.dart';

/// Renders a product image whether it's a remote URL (older products
/// that used the paste-a-link flow) or a local device file path (from
/// the on-device photo/video picker). Falls back to [placeholder] if
/// the path is empty or fails to load.
///
/// Images are decoded at a capped width ([maxDecodeWidth]) to keep memory low
/// in scrolling grids, and fade in once loaded instead of popping in.
class ProductImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget placeholder;

  /// Upper bound, in logical pixels, for the decoded image width.
  final int maxDecodeWidth;

  const ProductImage({
    super.key,
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.maxDecodeWidth = 800,
  });

  bool get _isNetwork =>
      path.startsWith('http://') || path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return placeholder;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (maxDecodeWidth * pixelRatio).round();

    Widget fadeIn(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) {
      if (wasSynchronouslyLoaded) return child;
      return AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: child,
      );
    }

    if (_isNetwork) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Visible behind the image while it loads (and if it fails).
          placeholder,
          Image.network(
            path,
            fit: fit,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            frameBuilder: fadeIn,
            errorBuilder: (context, error, stackTrace) => placeholder,
          ),
        ],
      );
    }

    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: fadeIn,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
