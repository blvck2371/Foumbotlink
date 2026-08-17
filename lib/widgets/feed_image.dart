import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Image réseau façon Facebook : pas de roue de chargement — un fond
/// neutre qui s'efface en fondu doux dès que la photo est prête. Mise en
/// cache disque (`cached_network_image`) pour qu'une photo déjà vue
/// réapparaisse instantanément, sans re-téléchargement, y compris après
/// avoir quitté l'app.
class FeedNetworkImage extends StatelessWidget {
  const FeedNetworkImage({
    super.key,
    required this.url,
    required this.isDark,
    this.fit = BoxFit.cover,
  });

  final String url;
  final bool isDark;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = isDark ? AppColors.blackElevated : AppColors.whiteSoft;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeInCurve: Curves.easeOut,
      placeholder: (context, _) => ColoredBox(color: placeholder),
      errorWidget: (context, _, error) => ColoredBox(
        color: placeholder,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: isDark ? AppColors.whiteMuted : AppColors.gray,
        ),
      ),
    );
  }
}

/// Bloc photo(s) d'une publication.
///
/// - Une seule photo : le cadre épouse le vrai format de l'image (portrait,
///   paysage, carré…), dans une fourchette raisonnable, pour ne jamais
///   couper le sujet — comme fait X/Twitter.
/// - Plusieurs photos : carrousel swipeable dans un cadre de ratio fixe
///   (nécessaire pour que la hauteur ne saute pas d'une photo à l'autre),
///   avec indicateurs — comme le carrousel Instagram.
class FeedImageCarousel extends StatelessWidget {
  const FeedImageCarousel({
    super.key,
    required this.imageUrls,
    required this.isDark,
    this.borderRadius = 16,
    this.galleryAspectRatio = 4 / 5,
  });

  final List<String> imageUrls;
  final bool isDark;
  final double borderRadius;
  final double galleryAspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageUrls.length == 1
          ? _SingleFeedImage(url: imageUrls.first, isDark: isDark)
          : _FeedImageGallery(
              imageUrls: imageUrls,
              isDark: isDark,
              aspectRatio: galleryAspectRatio,
            ),
    );
  }
}

/// Cadre qui adopte le vrai ratio de l'image une fois connu, borné entre
/// portrait 3:4 et paysage 16:9 pour rester raisonnable dans un fil.
class _SingleFeedImage extends StatefulWidget {
  const _SingleFeedImage({required this.url, required this.isDark});

  final String url;
  final bool isDark;

  @override
  State<_SingleFeedImage> createState() => _SingleFeedImageState();
}

class _SingleFeedImageState extends State<_SingleFeedImage> {
  static const _minRatio = 3 / 4; // le plus haut toléré (portrait)
  static const _maxRatio = 16 / 9; // le plus large toléré (paysage)

  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _SingleFeedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _ratio = null;
      _resolve();
    }
  }

  void _resolve() {
    _stream?.removeListener(_listener!);
    // Même provider que `CachedNetworkImage` (mêmes clé et cache manager)
    // : mesurer le ratio ne déclenche pas un second téléchargement.
    final stream = CachedNetworkImageProvider(widget.url)
        .resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final raw = info.image.width / info.image.height;
      setState(() => _ratio = raw.clamp(_minRatio, _maxRatio).toDouble());
    });
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // Format 4:5 par défaut pendant la résolution du vrai ratio, pour
      // éviter un cadre trop plat qui sauterait ensuite en hauteur.
      aspectRatio: _ratio ?? 4 / 5,
      child: FeedNetworkImage(url: widget.url, isDark: widget.isDark),
    );
  }
}

class _FeedImageGallery extends StatefulWidget {
  const _FeedImageGallery({
    required this.imageUrls,
    required this.isDark,
    required this.aspectRatio,
  });

  final List<String> imageUrls;
  final bool isDark;
  final double aspectRatio;

  @override
  State<_FeedImageGallery> createState() => _FeedImageGalleryState();
}

class _FeedImageGalleryState extends State<_FeedImageGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls;

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            physics: const BouncingScrollPhysics(),
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => FeedNetworkImage(
              url: images[i],
              isDark: widget.isDark,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_page + 1}/${images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
