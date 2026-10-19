import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'product_image.dart';

class ProductCard extends StatelessWidget {
  final String name;
  final String price;
  final String? originalPrice;
  final String image;
  final double? rating;
  final int? soldCount;
  final int discountPercent;
  final bool flashSale;
  final bool freeShipping;
  final bool codAvailable;
  final VoidCallback? onTap;

  const ProductCard({
    super.key,
    required this.name,
    required this.price,
    this.originalPrice,
    required this.image,
    this.rating,
    this.soldCount,
    this.discountPercent = 0,
    this.flashSale = false,
    this.freeShipping = false,
    this.codAvailable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      name,
      price,
      if (flashSale) 'flash sale',
      if (discountPercent > 0) '$discountPercent percent off',
      if (rating != null && rating! > 0)
        'rated ${rating!.toStringAsFixed(1)} stars',
      if (freeShipping) 'free shipping',
    ].join(', ');

    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: RepaintBoundary(child: _buildCard()),
    );
  }

  Widget _buildCard() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // =========================================
              // PRODUCT IMAGE
              // =========================================
              ProductImage(
                path: image,
                fit: BoxFit.cover,
                placeholder: Container(
                  color: AppColors.lightGrey,
                  child: const Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),

              // =========================================
              // BOTTOM INFORMATION
              // =========================================
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 35, 12, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // PRODUCT NAME
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // PRICE + SOLD
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // PRICE
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  price,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (originalPrice != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      originalPrice!,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white70,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // SOLD COUNT
                          if (soldCount != null && soldCount! > 0)
                            Text(
                              "$soldCount sold",
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),

                      // FREE SHIPPING / COD TAGS
                      if (freeShipping || codAvailable) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            if (freeShipping)
                              const _InfoTag(
                                label: "Free Shipping",
                                color: AppColors.success,
                              ),
                            if (codAvailable)
                              const _InfoTag(
                                label: "COD",
                                color: AppColors.secondary,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // =========================================
              // DISCOUNT PERCENTAGE
              // =========================================
              if (discountPercent > 0)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (flashSale)
                          const Icon(
                            Icons.bolt_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        Text(
                          "-$discountPercent%",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // =========================================
              // RATING
              // =========================================
              if (rating != null && rating! > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.60),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================
// SMALL INFO TAG (Free Shipping / COD)
// =========================================
class _InfoTag extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
