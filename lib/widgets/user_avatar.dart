import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../utils/image_url.dart';

/// Avatar utilisateur : photo réseau légère (cache + décodage borné) ou
/// initiales en secours — utilisé sur le fil, le profil, la composition, etc.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.fontSize,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? fontSize;

  /// Initiales affichées quand il n'y a pas de photo — une lettre pour un
  /// prénom seul, deux pour un nom composé ou une structure (« Mairie Foumbot»
  /// → « MF »).
  static String initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.orange.withValues(alpha: 0.12);
    final fg = foregroundColor ?? AppColors.orange;
    final label = initials(name);
    final textSize = fontSize ?? radius * 0.9;
    final url = photoUrl?.trim();

    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: textSize,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      );
    }

    final diameter = (radius * 2).ceil();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Décodage 2× la taille affichée, plafonné à 256 px — largement
    // suffisant pour un avatar et évite de charger des photos profil en
    // pleine résolution dans le fil.
    final cachePx = (diameter * dpr * 2).ceil().clamp(64, 256);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: displayImageUrl(url),
          width: diameter.toDouble(),
          height: diameter.toDouble(),
          fit: BoxFit.cover,
          memCacheWidth: cachePx,
          memCacheHeight: cachePx,
          maxWidthDiskCache: 512,
          maxHeightDiskCache: 512,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => _InitialsLabel(
            label: label,
            backgroundColor: bg,
            foregroundColor: fg,
            fontSize: textSize,
          ),
          errorWidget: (_, _, _) => _InitialsLabel(
            label: label,
            backgroundColor: bg,
            foregroundColor: fg,
            fontSize: textSize,
          ),
        ),
      ),
    );
  }
}

class _InitialsLabel extends StatelessWidget {
  const _InitialsLabel({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.fontSize,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: foregroundColor,
          ),
        ),
      ),
    );
  }
}
