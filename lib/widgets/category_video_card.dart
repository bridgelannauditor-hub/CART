import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/app_colors.dart';

/// A tappable "frame" that plays a muted, looping preview video with
/// the category title overlaid at the bottom. Falls back to a plain
/// gradient tile with an icon if the video can't load (e.g. offline,
/// or the host returns 403/404).
class CategoryVideoCard extends StatefulWidget {
  final String title;
  final String videoUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const CategoryVideoCard({
    super.key,
    required this.title,
    required this.videoUrl,
    required this.fallbackIcon,
    required this.onTap,
  });

  @override
  State<CategoryVideoCard> createState() => _CategoryVideoCardState();
}

class _CategoryVideoCardState extends State<CategoryVideoCard> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );

    // Playback errors that happen after initialization surface here
    // as `hasError`, not as a thrown exception.
    void onChange() {
      if (_disposed || !mounted) return;
      if (controller.value.hasError && !_failed) {
        setState(() => _failed = true);
      }
    }

    controller.addListener(onChange);

    try {
      // Don't let a stalled connection keep a native player alive forever.
      await controller.initialize().timeout(const Duration(seconds: 12));

      if (_disposed || !mounted) {
        controller.removeListener(onChange);
        await controller.dispose();
        return;
      }

      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();

      setState(() => _controller = controller);
    } catch (_) {
      // A failed load (403, offline, timeout) still holds a native
      // ExoPlayer. Release it, otherwise every failure leaks one.
      controller.removeListener(onChange);
      await controller.dispose();

      if (_disposed || !mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready =
        !_failed &&
        controller != null &&
        controller.value.isInitialized &&
        !controller.value.hasError;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              else if (_failed)
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.darkGrey],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.fallbackIcon,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 42,
                  ),
                )
              else
                Container(
                  color: AppColors.lightGrey,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),

              // Bottom gradient scrim so the title stays readable.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 28, 14, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.2,
                    ),
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
