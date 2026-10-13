import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../models/product_media_model.dart';
import '../services/cloudinary_service.dart';

/// A single photo/video the seller has picked for this product,
/// before it's been saved to the database.
class PickedMediaItem {
  final ProductMediaType type;
  final String path;

  const PickedMediaItem({required this.type, required this.path});
}

/// Lets a seller pick up to [maxImages] photos and [maxVideos] videos
/// from their device for a product listing. Fully controlled — the
/// parent screen owns the list and receives updates via [onChanged].
class MediaPickerGrid extends StatelessWidget {
  static const int maxImages = 20;
  static const int maxVideos = 5;

  final List<PickedMediaItem> items;
  final ValueChanged<List<PickedMediaItem>> onChanged;

  const MediaPickerGrid({
    super.key,
    required this.items,
    required this.onChanged,
  });

  int get _imageCount =>
      items.where((e) => e.type == ProductMediaType.image).length;
  int get _videoCount =>
      items.where((e) => e.type == ProductMediaType.video).length;

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  Future<void> _pickPhotos(BuildContext context) async {
    final remaining = maxImages - _imageCount;
    if (remaining <= 0) {
      _showMessage(context, "You can add up to $maxImages photos.");
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);
    if (!context.mounted) return;
    if (picked.isEmpty) return;

    final toAdd = <PickedMediaItem>[];
    var rejected = 0;
    for (final image in picked.take(remaining)) {
      try {
        await CloudinaryService.validateFile(
          File(image.path),
          resourceType: 'image',
        );
        toAdd.add(
          PickedMediaItem(type: ProductMediaType.image, path: image.path),
        );
      } on MediaUploadException {
        rejected++;
      }
    }
    if (!context.mounted) return;

    final notices = <String>[];
    if (rejected > 0) {
      notices.add(
        '$rejected photo(s) skipped. Use JPG, PNG, WebP, HEIC, or HEIF files up to 10 MB.',
      );
    }
    if (picked.length > remaining) {
      notices.add('Only $remaining slot(s) were available — $maxImages max.');
    }
    if (notices.isNotEmpty) _showMessage(context, notices.join(' '));

    if (toAdd.isNotEmpty) onChanged([...items, ...toAdd]);
  }

  Future<void> _pickVideo(BuildContext context) async {
    if (_videoCount >= maxVideos) {
      _showMessage(context, "You can add up to $maxVideos videos.");
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (!context.mounted) return;
    if (picked == null) return;

    try {
      await CloudinaryService.validateFile(
        File(picked.path),
        resourceType: 'video',
      );
    } on MediaUploadException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
      return;
    }
    if (!context.mounted) return;

    onChanged([
      ...items,
      PickedMediaItem(type: ProductMediaType.video, path: picked.path),
    ]);
  }

  void _remove(int index) {
    final updated = [...items]..removeAt(index);
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < items.length; i++)
              _MediaThumb(item: items[i], onRemove: () => _remove(i)),
            _AddTile(
              icon: Icons.add_photo_alternate_outlined,
              label: "Photo\n$_imageCount/$maxImages",
              onTap: () => _pickPhotos(context),
            ),
            _AddTile(
              icon: Icons.videocam_outlined,
              label: "Video\n$_videoCount/$maxVideos",
              onTap: () => _pickVideo(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          "First photo is used as the cover image.",
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final PickedMediaItem item;
  final VoidCallback onRemove;

  const _MediaThumb({required this.item, required this.onRemove});

  bool get _isNetwork =>
      item.path.startsWith('http://') || item.path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 84,
            height: 84,
            color: AppColors.lightGrey,
            child: item.type == ProductMediaType.video
                ? const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: AppColors.primary,
                      size: 30,
                    ),
                  )
                : _isNetwork
                ? Image.network(
                    item.path,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Image.file(
                    File(item.path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
          color: AppColors.primary.withValues(alpha: 0.05),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
