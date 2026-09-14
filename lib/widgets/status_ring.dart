import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Anneau autour d'un avatar quand la personne a des statuts en cours.
///
/// Orange plein tant qu'il reste quelque chose à découvrir, gris une fois
/// tout vu — la même convention que partout ailleurs, qui permet de savoir
/// d'un coup d'œil s'il y a du neuf sans rien lire.
class StatusRing extends StatelessWidget {
  const StatusRing({
    super.key,
    required this.child,
    required this.radius,
    this.hasStatuses = false,
    this.hasUnseen = false,
    this.thickness = 3,
    this.gap = 3,
    this.backgroundColor,
    this.onTap,
  });

  /// L'avatar à entourer.
  final Widget child;

  /// Rayon de l'avatar — l'anneau se dessine autour.
  final double radius;

  final bool hasStatuses;
  final bool hasUnseen;
  final double thickness;

  /// Respiration entre l'anneau et l'avatar, peinte à la couleur du fond
  /// pour que l'anneau ne colle pas à la photo.
  final double gap;

  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Sans statut, pas d'anneau : un cercle gris permanent laisserait
    // croire à un contenu qui n'existe pas.
    if (!hasStatuses) {
      return onTap == null
          ? child
          : GestureDetector(onTap: onTap, child: child);
    }

    final ringColors = hasUnseen
        ? const [AppColors.orange, AppColors.orangeSoft, AppColors.orangeDeep]
        : [
            AppColors.gray.withValues(alpha: 0.45),
            AppColors.gray.withValues(alpha: 0.3),
          ];

    final size = (radius + gap + thickness) * 2;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [...ringColors, ringColors.first]),
        ),
        child: Padding(
          padding: EdgeInsets.all(thickness),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Padding(padding: EdgeInsets.all(gap), child: child),
          ),
        ),
      ),
    );
  }
}
