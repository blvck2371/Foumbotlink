import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Chargement animé spécifique à Foumbot Link : trois orbes qui pulsent
/// en séquence avec un halo lumineux — même langage visuel que les
/// GlowOrb de l'écran d'authentification, décliné en micro-animation.
class FoumbotLoader extends StatefulWidget {
  const FoumbotLoader({super.key, this.size = 10.0, this.color = AppColors.red});

  const FoumbotLoader.button({super.key})
      : size = 6.0,
        color = AppColors.white;

  final double size;
  final Color color;

  @override
  State<FoumbotLoader> createState() => _FoumbotLoaderState();
}

class _FoumbotLoaderState extends State<FoumbotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      height: s,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value + i * 0.2) % 1.0;
              final wave = sin(phase * pi * 2);
              final norm = (wave + 1) / 2;
              final scale = 0.5 + norm * 0.5;
              final a = 0.3 + norm * 0.7;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: s * 0.35),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: a),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: a * 0.3),
                          blurRadius: s,
                          spreadRadius: s * 0.15,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
