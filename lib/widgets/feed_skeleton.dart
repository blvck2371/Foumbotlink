import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Squelettes de chargement du fil : des cartes grises aux dimensions
/// réelles, parcourues d'un reflet, à la place d'une roue centrée.
///
/// À temps de chargement identique, la page paraît déjà là — c'est la
/// mise en page qui apparaît d'abord et le contenu qui la remplit, au lieu
/// d'un écran vide qui attend.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key, required this.isDark, this.hasImage = true});

  final bool isDark;
  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    final base = isDark ? AppColors.blackElevated : AppColors.white;
    final border = (isDark ? AppColors.white : AppColors.black).withValues(
      alpha: 0.06,
    );

    // Le fond et la bordure de la carte restent **hors** du `_Shimmer` :
    // son `ShaderMask` repeint tout ce qui est opaque en dessous de lui, et
    // engloberait sinon le fond de la carte, qui virerait au gris au lieu
    // de rester la carte sur laquelle les blocs se détachent.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: _Shimmer(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Block(width: 40, height: 40, radius: 20),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Block(width: 120, height: 12),
                    SizedBox(height: 6),
                    _Block(width: 80, height: 10),
                  ],
                ),
                const Spacer(),
                const _Block(width: 58, height: 18, radius: 20),
              ],
            ),
            const SizedBox(height: 16),
            const _Block(width: 220, height: 16),
            const SizedBox(height: 10),
            const _Block(width: double.infinity, height: 11),
            const SizedBox(height: 6),
            const _Block(width: double.infinity, height: 11),
            const SizedBox(height: 6),
            const _Block(width: 180, height: 11),
            if (hasImage) ...[
              const SizedBox(height: 12),
              const AspectRatio(
                aspectRatio: 4 / 5,
                child: _Block(width: double.infinity, height: double.infinity,
                    radius: 12),
              ),
            ],
            const SizedBox(height: 14),
            const _Block(width: 160, height: 10),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // La couleur exacte importe peu : le `ShaderMask` du parent repeint
        // entièrement ces blocs. Seule leur forme compte.
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Reflet qui balaie le squelette. Implémenté avec un `ShaderMask` plutôt
/// qu'avec un paquet externe : un dégradé animé sur trois arrêts suffit, et
/// ça évite une dépendance de plus pour une vingtaine de lignes.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child, required this.isDark});

  final Widget child;
  final bool isDark;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.isDark
        ? AppColors.white.withValues(alpha: 0.07)
        : AppColors.black.withValues(alpha: 0.07);
    final bright = widget.isDark
        ? AppColors.white.withValues(alpha: 0.15)
        : AppColors.black.withValues(alpha: 0.04);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Le reflet traverse de −1 à 2 pour entrer et sortir complètement
        // du cadre au lieu d'apparaître et disparaître sur les bords.
        final t = _controller.value * 3 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [dim, bright, dim],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
