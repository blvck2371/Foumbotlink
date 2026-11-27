import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/pro_listing.dart';
import '../../theme/app_colors.dart';
import '../../widgets/user_avatar.dart';

/// Rangée d'étoiles avec demi-étoile, pour une moyenne (4,3 → ★★★★½).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.value, this.size = 16, this.muted});

  final double value;
  final double size;
  final Color? muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star_rounded
                : value >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: value >= i - 0.5
                ? AppColors.orange
                : (muted ?? AppColors.gray).withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

/// « ★★★★½ 4,3 · 12 avis », ou « Pas encore d'avis ».
class RatingLine extends StatelessWidget {
  const RatingLine({
    super.key,
    required this.listing,
    required this.ink,
    required this.muted,
    this.size = 15,
  });

  final ProListing listing;
  final Color ink;
  final Color muted;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!listing.hasRating) {
      return Text(
        'Pas encore d’avis',
        style: GoogleFonts.manrope(fontSize: size - 2, color: muted),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StarRow(value: listing.ratingAvg, size: size, muted: muted),
        const SizedBox(width: 6),
        Text(
          listing.ratingLabel,
          style: GoogleFonts.manrope(
            fontSize: size - 1,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        Text(
          ' · ${listing.ratingCount} avis',
          style: GoogleFonts.manrope(fontSize: size - 2, color: muted),
        ),
      ],
    );
  }
}

/// Avatar d'un professionnel : sa photo, sinon l'icône de son métier.
class ProAvatar extends StatelessWidget {
  const ProAvatar({
    super.key,
    required this.listing,
    required this.isDark,
    this.radius = 26,
  });

  final ProListing listing;
  final bool isDark;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = listing.thumbnail;
    if (url != null && url.isNotEmpty) {
      return UserAvatar(name: listing.name, photoUrl: url, radius: radius);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.orange.withValues(alpha: isDark ? 0.22 : 0.12),
      child: Icon(
        listing.category.icon,
        size: radius,
        color: isDark ? AppColors.orangeSoft : AppColors.orangeReadable,
      ),
    );
  }
}
