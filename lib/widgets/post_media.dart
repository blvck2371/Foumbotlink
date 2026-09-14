import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feed_image.dart';
import 'post_image_viewer.dart';

/// Les photos d'une publication, avec les deux gestes qu'on attend d'elles
/// partout ailleurs : un tap ouvre la visionneuse plein écran, un double
/// tap ajoute le « j'aime » avec le cœur qui pulse.
///
/// Regroupés ici plutôt que dans chaque écran parce que les deux gestes
/// doivent vivre sur le **même** `GestureDetector` (voir
/// [FeedImageCarousel.onImageTap]) et que le cœur a besoin d'un état
/// d'animation — ce que ni la carte du fil ni l'écran de détail, tous deux
/// sans état, ne peuvent porter.
class PostMedia extends StatefulWidget {
  const PostMedia({
    super.key,
    required this.imageUrls,
    required this.isDark,
    required this.heroPrefix,
    this.borderRadius = 16,
    this.onLike,
    this.alreadyLiked = false,
  });

  final List<String> imageUrls;
  final bool isDark;

  /// Voir [openPostImageViewer] — doit être propre à l'écran appelant.
  final String heroPrefix;

  final double borderRadius;

  /// `null` = pas de double tap (publication d'un tiers non connecté,
  /// aperçu…). Le tap pour agrandir reste actif dans tous les cas.
  final VoidCallback? onLike;

  /// Un double tap sur une publication déjà aimée rejoue le cœur sans
  /// retirer le like — même comportement qu'Instagram : le geste veut
  /// dire « j'aime », jamais « je n'aime plus ».
  final bool alreadyLiked;

  @override
  State<PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<PostMedia>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart;

  @override
  void initState() {
    super.initState();
    _heart = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _onDoubleTap(int _) {
    HapticFeedback.lightImpact();
    _heart.forward(from: 0);
    if (!widget.alreadyLiked) widget.onLike?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        FeedImageCarousel(
          imageUrls: widget.imageUrls,
          isDark: widget.isDark,
          // Dans le fil, les photos d'une publication se montrent toutes
          // en même temps — comme sur Facebook — plutôt que cachées
          // derrière un geste de balayage.
          layout: FeedImageLayout.mosaic,
          borderRadius: widget.borderRadius,
          heroPrefix: widget.heroPrefix,
          onImageTap: (index) => openPostImageViewer(
            context,
            imageUrls: widget.imageUrls,
            initialIndex: index,
            heroPrefix: widget.heroPrefix,
          ),
          onImageDoubleTap: widget.onLike == null ? null : _onDoubleTap,
        ),
        // `IgnorePointer` : le cœur ne doit jamais intercepter le geste
        // suivant pendant qu'il s'efface.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _heart,
            builder: (context, _) {
              final t = _heart.value;
              if (t == 0) return const SizedBox.shrink();
              // Apparition élastique sur le premier tiers, puis fondu :
              // le cœur doit être parti avant qu'on ait envie de retoucher
              // la photo.
              final scale = t < 0.35
                  ? Curves.elasticOut.transform(t / 0.35)
                  : 1.0;
              final opacity = t < 0.6
                  ? 1.0
                  : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: const Icon(
                    Icons.favorite,
                    size: 96,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 24),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
