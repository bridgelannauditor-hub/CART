import 'package:flutter/material.dart';

/// Read-only star display for an average rating (supports half stars).
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  final Color color;

  const RatingStars({
    super.key,
    required this.rating,
    this.size = 16,
    this.color = const Color(0xFFFFB800),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;

        IconData icon;
        if (rating >= starValue) {
          icon = Icons.star_rounded;
        } else if (rating >= starValue - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }

        return Icon(icon, size: size, color: color);
      }),
    );
  }
}

/// Tappable 1-5 star input used when a customer is rating a product.
class RatingStarsInput extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final double size;

  const RatingStarsInput({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final filled = rating >= starValue;

        return IconButton(
          onPressed: () => onChanged(starValue.toDouble()),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            color: const Color(0xFFFFB800),
            size: size,
          ),
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(36, 36),
          ),
        );
      }),
    );
  }
}
