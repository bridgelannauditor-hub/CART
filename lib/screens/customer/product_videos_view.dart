import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../constants/app_colors.dart';
import '../../models/product_media_model.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../widgets/product_image.dart';
import 'product_details_screen.dart';

/// One playable video together with the product it was uploaded for.
class _ProductVideo {
  final ProductModel product;
  final String url;

  const _ProductVideo(this.product, this.url);

  /// Cloudinary can render a still frame of a video; this avoids loading
  /// any video bytes just to show a poster. Falls back to the product photo.
  String get posterUrl {
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.host.endsWith('cloudinary.com') &&
        url.contains('/video/upload/')) {
      final withFrame = url.replaceFirst(
        '/video/upload/',
        '/video/upload/so_0/',
      );
      final dot = withFrame.lastIndexOf('.');
      if (dot > withFrame.lastIndexOf('/')) {
        return '${withFrame.substring(0, dot)}.jpg';
      }
    }
    return product.image;
  }
}

/// "Videos" tab of the Watch screen: a TikTok-style vertical feed of the
/// product videos sellers have uploaded. Swipe up/down to move between
/// videos; the visible one autoplays, tap to pause.
class ProductVideosView extends StatefulWidget {
  /// Filters by product name when not empty.
  final String query;

  const ProductVideosView({super.key, this.query = ''});

  @override
  State<ProductVideosView> createState() => _ProductVideosViewState();
}

class _ProductVideosViewState extends State<ProductVideosView> {
  final ProductRepository _repository = ProductRepository();
  late Future<List<_ProductVideo>> _future;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(ProductVideosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _page = 0;
  }

  Future<List<_ProductVideo>> _load() async {
    final products = await _repository.getProductsWithVideos();
    return [
      for (final product in products)
        for (final media in product.media)
          if (media.type == ProductMediaType.video && media.path.isNotEmpty)
            _ProductVideo(product, media.path),
    ];
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
      _page = 0;
    });
    try {
      await future;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Widget _message(IconData icon, String title, String subtitle) {
    // ListView so pull-to-refresh keeps working.
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .25),
          Icon(icon, size: 64, color: AppColors.lightGrey),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ProductVideo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _message(
            Icons.error_outline,
            "Couldn't load videos",
            "Check your connection and pull down to try again",
          );
        }

        final query = widget.query.trim().toLowerCase();
        final videos = [
          for (final video in snapshot.data ?? const <_ProductVideo>[])
            if (query.isEmpty ||
                video.product.productName.toLowerCase().contains(query))
              video,
        ];

        if (videos.isEmpty) {
          return query.isEmpty
              ? _message(
                  Icons.video_library_outlined,
                  "No videos yet",
                  "Product videos from shops will show up here",
                )
              : _message(
                  Icons.search_off_rounded,
                  "No matching videos",
                  "Try a different search",
                );
        }

        return PageView.builder(
          // New key per result set so the feed restarts at the first video.
          key: ValueKey('$query-${videos.length}'),
          scrollDirection: Axis.vertical,
          itemCount: videos.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, index) => _ReelPage(
            key: ValueKey(videos[index].url),
            video: videos[index],
            active: index == _page,
          ),
        );
      },
    );
  }
}

/// A single full-screen video. Only the active page holds a player, so
/// swiping through the feed never keeps more than one decoder alive.
class _ReelPage extends StatefulWidget {
  final _ProductVideo video;
  final bool active;

  const _ReelPage({super.key, required this.video, required this.active});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (_controller != null) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.video.url),
    );
    _controller = controller;
    controller.addListener(_refresh);
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (_disposed || _controller != controller) return;
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (_disposed || _controller != controller) return;
      _stop();
      if (mounted) setState(() => _failed = true);
    }
  }

  void _stop() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_refresh);
    controller?.dispose();
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (mounted && (_controller?.value.isInitialized ?? false)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.removeListener(_refresh);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  Future<void> _openProduct() async {
    final controller = _controller;
    await controller?.pause();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(product: widget.video.product),
      ),
    );
    if (mounted && widget.active) await _controller?.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final playing = ready && controller.value.isPlaying;
    final product = widget.video.product;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster shows until the first frame is ready.
          if (!ready)
            ProductImage(
              path: widget.video.posterUrl,
              fit: BoxFit.contain,
              placeholder: const SizedBox.shrink(),
            ),
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),

          // Tap anywhere to pause / resume.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
            child: Center(
              child: _failed
                  ? const Text(
                      "This video couldn't be played",
                      style: TextStyle(color: Colors.white70),
                    )
                  : !ready
                  ? (widget.active
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const SizedBox.shrink())
                  : AnimatedOpacity(
                      opacity: playing ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 72,
                      ),
                    ),
            ),
          ),

          // Bottom info + call to action.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₱${product.effectivePrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _openProduct,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("View product"),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: AppColors.primary,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
