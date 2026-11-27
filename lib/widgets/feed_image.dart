
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../utils/feed_cache_manager.dart';
import '../utils/image_url.dart';
import '../utils/local_media.dart';
import 'image_shimmer.dart';

/// `imageUrls` mélange des URLs réseau (photos de démo) et des chemins
/// de fichiers locaux (photos jointes par l'utilisateur via la galerie).
bool _isNetworkUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// Image d'une publication, réseau ou locale, façon Facebook : pas de
/// roue de chargement — un reflet lent ([ImageShimmer]) puis la photo en
/// fondu. Les photos réseau passent par un cache disque
/// (`cached_network_image`) pour réapparaître instantanément une fois
/// vues, sans re-téléchargement, y compris après avoir quitté l'app.
///
/// Un échec (réseau qui flanche) est retenté tout seul, deux fois, sans
/// rien montrer d'autre que le reflet. Ce n'est qu'ensuite qu'un discret
/// bouton « recharger » apparaît — jamais une icône d'image cassée.
class FeedNetworkImage extends StatefulWidget {
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
  State<FeedNetworkImage> createState() => _FeedNetworkImageState();
}

class _FeedNetworkImageState extends State<FeedNetworkImage> {
  static const _autoRetries = 2;

  /// Sans le moindre octet reçu pendant ce délai, le chargement est
  /// considéré comme bloqué : on propose de recharger plutôt que de
  /// laisser le reflet tourner indéfiniment.
  static const _stallAfter = Duration(seconds: 25);

  int _attempt = 0;
  bool _retryScheduled = false;

  /// Échec définitif (après les tentatives automatiques) ou chargement
  /// bloqué : le bouton « Recharger » est affiché.
  bool _gaveUp = false;
  bool _loaded = false;
  DateTime _lastProgress = DateTime.now();
  Timer? _watchdog;
  StreamSubscription<bool>? _online;

  String get _baseSrc => displayImageUrl(widget.url);

  /// Adresse demandée. Sur le web, le navigateur garde l'échec en
  /// mémoire pour une même adresse : chaque nouvelle tentative en change
  /// donc la forme (paramètre ignoré par Storage).
  String get _src {
    if (_attempt == 0 || !kIsWeb) return _baseSrc;
    return _baseSrc.contains('?')
        ? '$_baseSrc&r=$_attempt'
        : '$_baseSrc?r=$_attempt';
  }

  /// Clé du téléchargement. Une nouvelle clé à chaque tentative : avec la
  /// même, la demande se raccrocherait au téléchargement bloqué au lieu
  /// d'en lancer un neuf — c'est ce qui rendait « Recharger » inopérant
  /// sur une connexion faible.
  String get _cacheKey => _attempt == 0 ? _baseSrc : '$_baseSrc#r$_attempt';

  @override
  void initState() {
    super.initState();
    _startWatchdog();
    if (Get.isRegistered<ConnectivityService>()) {
      // Le réseau revient : une photo restée en échec se recharge seule.
      _online = Get.find<ConnectivityService>().online.listen((online) {
        if (online && _gaveUp && mounted) _retry();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FeedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _retryScheduled = false;
      _gaveUp = false;
      _loaded = false;
      _startWatchdog();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _online?.cancel();
    super.dispose();
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _lastProgress = DateTime.now();
    // Web : le navigateur ne rapporte pas toujours la progression, un
    // chargement lent mais vivant serait pris pour un blocage. Il a ses
    // propres délais, et un échec y passe par le bouton comme ailleurs.
    if (!_isNetworkUrl(widget.url) || kIsWeb) return;
    _watchdog = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _loaded) {
        timer.cancel();
        return;
      }
      if (_gaveUp) return;
      if (DateTime.now().difference(_lastProgress) < _stallAfter) return;
      // Bloqué : une tentative neuve d'abord, le bouton ensuite.
      if (_attempt < _autoRetries) {
        _retry();
      } else {
        setState(() => _gaveUp = true);
      }
    });
  }

  void _retry() {
    if (!mounted) return;
    unawaited(_evict(_cacheKey));
    setState(() {
      _attempt++;
      _retryScheduled = false;
      _gaveUp = false;
      _loaded = false;
      _lastProgress = DateTime.now();
    });
  }

  /// Retire une tentative ratée des caches, sans jamais faire échouer
  /// l'appelant.
  Future<void> _evict(String key) async {
    try {
      await CachedNetworkImage.evictFromCache(
        _src,
        cacheKey: key,
        cacheManager: kIsWeb ? null : FeedCacheManager.instance,
      );
    } on Object catch (_) {}
  }

  /// Tap sur « Recharger » : repart de zéro, tentatives automatiques
  /// comprises.
  void _manualRetry() {
    _retry();
    _startWatchdog();
  }

  Widget _onError() {
    if (_attempt < _autoRetries) {
      if (!_retryScheduled) {
        _retryScheduled = true;
        // Délai croissant : un réseau qui vient de flancher a besoin d'un
        // instant pour revenir.
        Future<void>.delayed(
          Duration(milliseconds: 1200 * (_attempt + 1)),
          _retry,
        );
      }
      return ImageShimmer(isDark: widget.isDark);
    }
    if (!_gaveUp) {
      // Hors build : pas de setState pendant la construction.
      scheduleMicrotask(() {
        if (mounted && !_gaveUp) setState(() => _gaveUp = true);
      });
    }
    return _ReloadTile(isDark: widget.isDark, onTap: _manualRetry);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNetworkUrl(widget.url)) {
      return Image(
        image: LocalMedia.image(widget.url),
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            _ReloadTile(isDark: widget.isDark, onTap: null),
      );
    }

    // Chargement bloqué : le bouton passe devant le reflet.
    if (_gaveUp) {
      return _ReloadTile(isDark: widget.isDark, onTap: _manualRetry);
    }

    return CachedNetworkImage(
      key: ValueKey(_attempt),
      imageUrl: _src,
      cacheKey: _cacheKey,
      cacheManager: kIsWeb ? null : FeedCacheManager.instance,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      // Décodage borné en mémoire : sans ça, une photo 3000×4000 uploadée
      // telle quelle occupe ~48 Mo de RAM une fois décodée — quelques-unes
      // dans le fil et l'app passe son temps en GC. 1080 px de large suffit
      // largement pour l'affichage.
      memCacheWidth: widget.fullResolution ? null : widget.decodeWidth,
      maxWidthDiskCache: widget.fullResolution ? 2160 : 1440,
      fadeInDuration: const Duration(milliseconds: 280),
      fadeInCurve: Curves.easeOut,
      fadeOutDuration: const Duration(milliseconds: 180),
      // Chaque morceau reçu repousse le délai de blocage.
      progressIndicatorBuilder: (context, _, progress) {
        _lastProgress = DateTime.now();
        return ImageShimmer(isDark: widget.isDark);
      },
      imageBuilder: (context, provider) {
        _loaded = true;
        return Image(
          image: provider,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
        );
      },
      errorWidget: (context, _, error) => _onError(),
    );
  }
}

/// Dernier recours, après les tentatives automatiques : la surface reste
/// neutre, avec un bouton pour réessayer — pas d'image « cassée ».
///
/// Toute la surface est touchable (pas seulement l'icône) : sur un petit
/// écran, viser une icône de 24 px au milieu d'une mosaïque était
/// laborieux, et le tap tombait souvent sur la carte, qui ouvrait la
/// publication au lieu de recharger.
class _ReloadTile extends StatelessWidget {
  const _ReloadTile({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final surface = ColoredBox(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      child: Center(
        child: onTap == null
            ? Icon(Icons.image_outlined, color: muted.withValues(alpha: 0.5))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: muted, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    'Recharger',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
    if (onTap == null) return surface;
    return Semantics(
      button: true,
      label: 'Recharger la photo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: surface,
      ),
    );
  }
}

/// Précharge les photos des prochaines cartes du fil pendant qu'on lit
/// celle-ci, comme Facebook : quand on y arrive, elles sont déjà là.
/// Une même photo n'est demandée qu'une fois par session.
abstract final class FeedImagePrefetch {
  static final _done = <String>{};

  static void ahead(BuildContext context, Iterable<String> urls) {
    for (final url in urls) {
      if (!_isNetworkUrl(url) || !_done.add(url)) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(
            displayImageUrl(url),
            cacheManager: kIsWeb ? null : FeedCacheManager.instance,
          ),
          context,
          onError: (_, _) => _done.remove(url),
        ),
      );
    }
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

  /// Formes déjà mesurées : en remontant le fil, une carte revient
  /// directement au bon cadre au lieu de repartir du 4:5.
  static final _knownRatios = <String, double>{};

  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = _knownRatios[widget.url];
    if (_ratio == null) _resolve();
  }

  @override
  void didUpdateWidget(covariant _SingleFeedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _ratio = _knownRatios[widget.url];
      if (_ratio == null) _resolve();
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
        ? CachedNetworkImageProvider(displayImageUrl(widget.url))
        : LocalMedia.image(widget.url);
    final provider = ResizeImage(base, width: 100, allowUpscaling: true);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final raw = info.image.width / info.image.height;
      final ratio = raw.clamp(_minRatio, _maxRatio).toDouble();
      _knownRatios[widget.url] = ratio;
      setState(() => _ratio = ratio);
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
    // Format 4:5 par défaut pendant la résolution du vrai ratio, pour
    // éviter un cadre trop plat ; le passage au vrai format se fait en
    // douceur plutôt que d'un coup sec sous le doigt.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: _ratio ?? 4 / 5),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, ratio, child) =>
          AspectRatio(aspectRatio: ratio, child: child),
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
