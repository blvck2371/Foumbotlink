import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// Bandeau « A republié la publication de … » sur une republication.
class RepostBanner extends StatelessWidget {
  const RepostBanner({
    super.key,
    required this.originalAuthorName,
    this.originalAuthorUid,
    this.originalAuthorPhotoUrl,
    required this.isDark,
  });

  final String originalAuthorName;
  final String? originalAuthorUid;
  final String? originalAuthorPhotoUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final canOpenProfile =
        originalAuthorUid != null && originalAuthorUid!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: canOpenProfile
            ? () => Get.toNamed(
                  AppRoutes.userProfile,
                  arguments: originalAuthorUid,
                  preventDuplicates: false,
                )
            : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            const Icon(Icons.repeat_rounded, size: 16, color: AppColors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                  children: [
                    const TextSpan(
                      text: 'A republié la publication de ',
                    ),
                    TextSpan(
                      text: originalAuthorName,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (originalAuthorName.isNotEmpty) ...[
              const SizedBox(width: 8),
              UserAvatar(
                name: originalAuthorName,
                photoUrl: originalAuthorPhotoUrl,
                radius: 12,
                fontSize: 10,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
