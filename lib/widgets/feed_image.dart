import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// `imageUrls` mélange des URLs réseau (photos de démo) et des chemins
/// de fichiers locaux (photos jointes par l'utilisateur via la galerie).
bool _isNetworkUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// Image d'une publication, réseau ou locale, façon Facebook : pas de
/// roue de chargement — un fond neutre qui s'efface en fondu doux dès que
/// la photo est prête. Les photos réseau passent par un cache disque
/// (`cached_network_image`) pour réapparaître instantanément une fois
/// vues, sans re-téléchargement, y compris après avoir quitté l'app.
class FeedNetworkImage extends StatelessWidget {
  const FeedNetworkImage({
    super.key,
    required this.url,
    required this.isDark,
    this.fit = BoxFit.cover,
    this.fullResolution = false,
    this.decodeWidth = 1080,
  });

  final String url;
  final bool isDark;
  final BoxFit fit;

  /// Lève le plafond de décodage — réservé à la visionneuse plein écran,
  /// où l'on peut zoomer jusqu'à 4× : à 1080 px la photo deviendrait
  /// floue dès le premier cran de zoom. Dans le fil, laisser `false`.
  final bool fullResolution;

  /// Largeur de décodage, en pixels. Une tuile de mosaïque occupe la
  /// moitié de l'écran : la décoder à 1080 px coûte quatre fois la mémoire
  /// nécessaire et autant de temps de décodage — donc autant d'images qui
  /// tardent à apparaître. Ignoré si [fullResolution].
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = isDark ? AppColors.blackElevated : AppColors.whiteSoft;
    final errorFallback = ColoredBox(
      color: placeholder,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: isDark ? AppColors.whiteMuted : AppColors.gray,
      ),
    );

    if (!_isNetworkUrl(url)) {
      return Image.file(
        File(url),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => errorFallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      // Décodage borné en mémoire : sans ça, une photo 3000×4000 uploadée
      // telle quelle occupe ~48 Mo de RAM une fois décodée — quelques-unes
      // dans le fil et l'app passe son temps en GC. 1080 px de large suffit
      // largement pour l'affichage.
      memCacheWidth: fullResolution ? null : decodeWidth,
      maxWidthDiskCache: fullResolution ? 2160 : 1440,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeInCurve: Curves.easeOut,
      placeholder: (context, _) => ColoredBox(color: placeholder),
      errorWidget: (context, _, error) => errorFallback,
    );
  }
}

/// Comment présenter plusieurs photos.
enum FeedImageLayout {
  /// Carrousel swipeable — les annonces du marché, où l'on regarde les
  /// photos d'un même objet l'une après l'autre.
  carousel,

  /// Mosaïque façon Facebook — les publications du fil : toutes les photos
  /// sont visibles d'un coup, sans geste à deviner, et la dernière tuile
  /// porte « +N » au-delà de quatre.
  mosaic,
}

/// Bloc photo(s) d'une publication.
///
/// - Une seule photo : le cadre épouse le vrai format de l'image (portrait,
///   paysage, carré…), dans une fourchette raisonnable, pour ne jamais
///   couper le sujet — comme fait X/Twitter.
/// - Plusieurs photos : mosaïque (par défaut dans le fil) ou carrousel
///   swipeable dans un cadre de ratio fixe, selon [layout].
class FeedImageCarousel extends StatelessWidget {
  const FeedImageCarousel({
    super.key,
    required this.imageUrls,
    required this.isDark,
    this.borderRadius = 16,
    this.galleryAspectRatio = 4 / 5,
    this.layout = FeedImageLayout.carousel,
    this.heroPrefix,
    this.onImageTap,
    this.onImageDoubleTap,
  });

  final List<String> imageUrls;
  final bool isDark;
  final double borderRadius;
  final double galleryAspectRatio;
  final FeedImageLayout layout;

  /// Préfixe des tags `Hero` des photos, pour la transition vers la
  /// visionneuse plein écran. Doit être propre à l'écran appelant — voir
  /// `openPostImageViewer`. `null` = pas de transition.
  final String? heroPrefix;

  /// Reçoivent l'index de la photo touchée. Les deux gestes sont posés sur
  /// un **même** `GestureDetector` : séparés, le simple tap gagnerait
  /// l'arène avant que le double tap ait pu se former, et le « j'aime »
  /// par double tap ne partirait jamais.
  final ValueChanged<int>? onImageTap;
  final ValueChanged<int>? onImageDoubleTap;

  @override
  Widget build(BuildContext context) {
    final single = imageUrls.length == 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: single
          ? _SingleFeedImage(
              url: imageUrls.first,
              isDark: isDark,
              child: _tappable(0, _hero(0, imageUrls.first)),
            )
          : layout == FeedImageLayout.mosaic
              ? _FeedImageMosaic(
                  count: imageUrls.length,
                  tileBuilder: (i) => _tappable(
                    i,
                    // Une tuile ne fait au mieux qu'une demi-largeur
                    // d'écran : la décoder plus finement ne se voit pas et
                    // retarde son apparition.
                    _hero(i, imageUrls[i], decodeWidth: 720),
                  ),
                )
              : _FeedImageGallery(
                  imageUrls: imageUrls,
                  isDark: isDark,
                  aspectRatio: galleryAspectRatio,
                  pageBuilder: (i) => _tappable(i, _hero(i, imageUrls[i])),
                ),
    );
  }

  Widget _hero(int index, String url, {int decodeWidth = 1080}) {
    final image = FeedNetworkImage(
      url: url,
      isDark: isDark,
      decodeWidth: decodeWidth,
    );
    if (heroPrefix == null) return image;
    return Hero(tag: '${heroPrefix}_$index', child: image);
  }

  Widget _tappable(int index, Widget child) {
    if (onImageTap == null && onImageDoubleTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onImageTap == null ? null : () => onImageTap!(index),
      onDoubleTap: onImageDoubleTap == null
          ? null
          : () => onImageDoubleTap!(index),
      child: child,
    );
  }
}

/// Mosaïque façon Facebook : deux photos côte à côte, trois avec une
/// grande à gauche, quatre en damier, et au-delà un damier dont la
/// dernière tuile annonce le reste par « +N ».
///
/// Le tout tient dans un `AspectRatio` : la hauteur du bloc est connue
/// avant même que les photos soient chargées, donc le fil ne sursaute pas
/// sous le doigt au fur et à mesure qu'elles arrivent.
class _FeedImageMosaic extends StatelessWidget {
  const _FeedImageMosaic({required this.count, required this.tileBuilder});

  /// Nombre de photos de la publication — peut dépasser [_maxTiles].
  final int count;

  final Widget Function(int index) tileBuilder;

  /// Au-delà, les photos ne sont plus montrées en vignette : la dernière
  /// tuile porte « +N » et la visionneuse plein écran donne accès au
  /// reste.
  static const _maxTiles = 4;

  /// Filet entre les tuiles : le fond de la carte transparaît, ce qui
  /// sépare deux photos aux couleurs proches sans peindre de bordure.
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    return switch (count) {
      2 => AspectRatio(
          aspectRatio: 2,
          child: Row(children: [_flex(0), const SizedBox(width: _gap), _flex(1)]),
        ),
      3 => AspectRatio(
          aspectRatio: 3 / 2,
          child: Row(
            children: [
              _flex(0),
              const SizedBox(width: _gap),
              Expanded(
                child: Column(
                  children: [
                    _flex(1),
                    const SizedBox(height: _gap),
                    _flex(2),
                  ],
                ),
              ),
            ],
          ),
        ),
      _ => AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _flex(0),
                    const SizedBox(width: _gap),
                    _flex(1),
                  ],
                ),
              ),
              const SizedBox(height: _gap),
              Expanded(
                child: Row(
                  children: [
                    _flex(2),
                    const SizedBox(width: _gap),
                    _flex(3),
                  ],
                ),
              ),
            ],
          ),
        ),
    };
  }

  Widget _flex(int index) => Expanded(child: _tile(index));

  Widget _tile(int index) {
    final tile = tileBuilder(index);
    final hidden = count - _maxTiles;
    if (index != _maxTiles - 1 || hidden <= 0) return tile;

    // « +N » posé par-dessus la quatrième photo, qui reste tapable : le
    // tap l'ouvre en plein écran, d'où l'on parcourt aussi les suivantes.
    // `IgnorePointer` pour que le voile ne mange pas ce geste.
    return Stack(
      fit: StackFit.expand,
      children: [
        tile,
        IgnorePointer(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.45),
            child: Center(
              child: Text(
                '+$hidden',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cadre qui adopte le vrai ratio de l'image une fois connu, borné entre
/// portrait 3:4 et paysage 16:9 pour rester raisonnable dans un fil.
class _SingleFeedImage extends StatefulWidget {
  const _SingleFeedImage({
    required this.url,
    required this.isDark,
    required this.child,
  });

  final String url;
  final bool isDark;

  /// L'image déjà habillée (Hero, gestes) par [FeedImageCarousel] — ce
  /// widget ne s'occupe plus que de lui donner le bon cadre.
  final Widget child;

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
    // Même provider que celui utilisé pour l'affichage (mêmes clé et
    // cache manager côté réseau) : mesurer le ratio ne déclenche pas un
    // second téléchargement. `ResizeImage` force un décodage minuscule —
    // le ratio est identique à toute résolution, inutile de décoder la
    // photo en pleine taille juste pour mesurer sa forme.
    final base = _isNetworkUrl(widget.url)
        ? CachedNetworkImageProvider(widget.url)
        : FileImage(File(widget.url)) as ImageProvider;
    final provider = ResizeImage(base, width: 100, allowUpscaling: true);
    final stream = provider.resolve(const ImageConfiguration());
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
      child: widget.child,
    );
  }
}

class _FeedImageGallery extends StatefulWidget {
  const _FeedImageGallery({
    required this.imageUrls,
    required this.isDark,
    required this.aspectRatio,
    required this.pageBuilder,
  });

  final List<String> imageUrls;
  final bool isDark;
  final double aspectRatio;
  final Widget Function(int index) pageBuilder;

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
            itemBuilder: (context, i) => widget.pageBuilder(i),
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
