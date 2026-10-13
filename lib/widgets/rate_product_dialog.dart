import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/review_model.dart';
import '../repositories/review_repository.dart';
import 'rating_stars.dart';

/// Opens a dialog letting the customer give a 1-5 star rating (with
/// an optional comment) for [productName]. Pre-fills with their
/// existing review if they've already rated this product. Returns
/// true if a review was submitted, so the caller can refresh.
Future<bool> showRateProductDialog(
  BuildContext context, {
  required int productId,
  required int customerId,
  required String productName,
}) async {
  final reviewRepository = ReviewRepository();

  final existing = await reviewRepository.getMyReview(productId, customerId);

  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _RateProductDialog(
      productId: productId,
      customerId: customerId,
      productName: productName,
      existingReview: existing,
    ),
  );

  return result ?? false;
}

class _RateProductDialog extends StatefulWidget {
  final int productId;
  final int customerId;
  final String productName;
  final ReviewModel? existingReview;

  const _RateProductDialog({
    required this.productId,
    required this.customerId,
    required this.productName,
    required this.existingReview,
  });

  @override
  State<_RateProductDialog> createState() => _RateProductDialogState();
}

class _RateProductDialogState extends State<_RateProductDialog> {
  final ReviewRepository _reviewRepository = ReviewRepository();
  late final TextEditingController _commentController;

  double _rating = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.existingReview?.rating ?? 0;
    _commentController = TextEditingController(
      text: widget.existingReview?.comment ?? '',
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a star rating.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _reviewRepository.submitReview(
        productId: widget.productId,
        customerId: widget.customerId,
        rating: _rating,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existingReview == null
                  ? "Rate this product"
                  : "Update your rating",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.productName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            RatingStarsInput(
              rating: _rating,
              onChanged: (value) => setState(() => _rating = value),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Share your experience (optional)",
                hintStyle: const TextStyle(fontSize: 13),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("Submit"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
