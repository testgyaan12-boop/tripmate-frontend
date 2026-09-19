import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/place_photos.dart';

/// Swipeable photo carousel with dots + counter.
/// Empty URL list renders the local fallback asset.
class PhotoCarousel extends StatefulWidget {
  final List<String> urls;
  final String fallback;
  final double height;
  const PhotoCarousel({
    super.key,
    required this.urls,
    required this.fallback,
    required this.height,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Image.asset(
        widget.fallback,
        height: widget.height,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                color: const Color(0xFFE2E8F0),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, _, _) => Image.asset(
                widget.fallback,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var d = 0; d < widget.urls.length; d++)
                    Container(
                      width: 7,
                      height: 7,
                      margin:
                          const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d == _i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.urls.length > 1)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_i + 1}/${widget.urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Place photo area: live carousel when the backend has real photos,
/// otherwise the existing single image / local fallback. Caches per place.
class PlaceGallery extends ConsumerWidget {
  final int? placeId;
  final String? imageUrl;
  final String fallback;
  final double height;
  const PlaceGallery({
    super.key,
    required this.placeId,
    required this.imageUrl,
    required this.fallback,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (placeId == null) return _single();
    final photos = ref.watch(placePhotosProvider(placeId!));
    return photos.when(
      loading: () => _single(),
      error: (_, _) => _single(),
      data: (urls) => urls.isEmpty
          ? _single()
          : PhotoCarousel(
              urls: urls, fallback: fallback, height: height),
    );
  }

  Widget _single() {
    final url = (imageUrl ?? '').isNotEmpty ? imageUrl! : null;
    if (url == null) {
      return Image.asset(
        fallback,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        fallback,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}
