import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feed_image.dart';

/// Ouvre les photos d'une publication en plein écran.
///
/// [heroPrefix] doit être **propre à l'écran appelant** (`feed_<id>` dans
/// le fil, `post_<id>` sur l'écran de détail) : deux écrans qui emploient
/// le même préfixe déclencheraient un vol de `Hero` entre eux à chaque
/// navigation, alors que la transition n'a de sens qu'entre la vignette et
/// la visionneuse.
Future<void> openPostImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  String? heroPrefix,
}) {
  if (imageUrls.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      // Route non opaque : pendant le glisser-pour-fermer, le fil reste
      // visible derrière la photo au lieu d'un trou noir.
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _PostImageViewer(
        imageUrls: imageUrls,
        initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
        heroPrefix: heroPrefix,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _PostImageViewer extends StatefulWidget {
  const _PostImageViewer({
    required this.imageUrls,
    required this.initialIndex,
    required this.heroPrefix,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final String? heroPrefix;

  @override
  State<_PostImageViewer> createState() => _PostImageViewerState();
}

class _PostImageViewerState extends State<_PostImageViewer>
    with SingleTickerProviderStateMixin {
  /// Au-delà de ce déplacement vertical, on ferme au relâchement.
  static const _dismissDistance = 110.0;

  /// … ou en dessous, si le geste part assez vite (fermeture « à la
  /// volée », sans avoir à traîner la photo jusqu'en bas).
  static const _dismissVelocity = 700.0;

  static const _maxScale = 4.0;

  late final PageController _pageController;
  late final TransformationController _zoom;
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;

  late int _index;
  double _dragY = 0;
  bool _dragging = false;
  TapDownDetails? _doubleTapAt;

  /// Le glisser-pour-fermer est désactivé dès que la photo est zoomée :
  /// le geste vertical appartient alors au déplacement dans l'image.
  bool get _isZoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _zoom = TransformationController();
    _zoomAnim =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 220),
          )
          ..addListener(() {
            if (_zoomTween != null) _zoom.value = _zoomTween!.value;
          });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _zoom.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _zoomTween = Matrix4Tween(
      begin: _zoom.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _resetZoom();
      setState(() {});
      return;
    }
    final position = _doubleTapAt?.localPosition;
    if (position == null) return;
    // Zoom centré sur le point touché : on translate d'abord le point vers
    // l'origine, puis on met à l'échelle.
    const scale = 2.5;
    final target = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic),
    );
    _zoomAnim.forward(from: 0);
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragging = true;
      _dragY += d.delta.dy;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_dragY.abs() > _dismissDistance || velocity.abs() > _dismissVelocity) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _dragging = false;
      _dragY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final progress = (_dragY.abs() / 320).clamp(0.0, 1.0);
    final images = widget.imageUrls;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Le fond s'éclaircit au fur et à mesure du glissement : le fil
          // qu'on retrouve derrière réapparaît progressivement.
          ColoredBox(color: Colors.black.withValues(alpha: 1 - progress * 0.9)),
          AnimatedSlide(
            offset: Offset(0, _dragY / size.height),
            duration: _dragging ? Duration.zero : const Duration(
              milliseconds: 220,
            ),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: 1 - progress * 0.15,
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                onDoubleTapDown: (d) => _doubleTapAt = d,
                onDoubleTap: _handleDoubleTap,
                // Handlers à `null` quand la photo est zoomée : sans ça, le
                // geste de fermeture volerait le déplacement dans l'image.
                onVerticalDragUpdate: _isZoomed ? null : _onDragUpdate,
                onVerticalDragEnd: _isZoomed ? null : _onDragEnd,
                child: PageView.builder(
                  controller: _pageController,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  itemCount: images.length,
                  onPageChanged: (i) {
                    // Chaque photo repart non zoomée : garder l'échelle de
                    // la précédente donnerait une image d'emblée recadrée
                    // sur une zone qui n'a rien à voir.
                    _zoom.value = Matrix4.identity();
                    setState(() => _index = i);
                  },
                  itemBuilder: (context, i) {
                    final image = Center(
                      child: FeedNetworkImage(
                        url: images[i],
                        isDark: true,
                        fit: BoxFit.contain,
                        fullResolution: true,
                      ),
                    );
                    return InteractiveViewer(
                      // Un seul contrôleur, réinitialisé au changement de
                      // page : seule la photo visible peut être zoomée.
                      transformationController: i == _index ? _zoom : null,
                      minScale: 1,
                      maxScale: _maxScale,
                      onInteractionEnd: (_) => setState(() {}),
                      child: widget.heroPrefix == null
                          ? image
                          : Hero(tag: '${widget.heroPrefix}_$i', child: image),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 4,
            right: 12,
            child: AnimatedOpacity(
              opacity: progress > 0.05 ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Fermer',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).maybePop();
                    },
                  ),
                  const Spacer(),
                  if (images.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1}/${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
