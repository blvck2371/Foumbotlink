import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Surface d'attente d'une photo, façon Facebook : un reflet lent qui
/// traverse le cadre. Un fond immobile laisse croire que rien ne charge ;
/// celui-ci dit « ça arrive » sans roue ni texte.
///
/// « Réduire les animations » activé : fond fixe.
class ImageShimmer extends StatefulWidget {
  const ImageShimmer({super.key, required this.isDark});

  final bool isDark;

  @override
  State<ImageShimmer> createState() => _ImageShimmerState();
}

class _ImageShimmerState extends State<ImageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark ? AppColors.blackElevated : AppColors.whiteSoft;
    final glow = widget.isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFFFFFFF);
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        // Le reflet part hors cadre à gauche et ressort à droite.
        final t = _sweep.value * 3 - 1;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.3),
              end: Alignment(t + 1, 0.3),
              colors: [base, glow, base],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
