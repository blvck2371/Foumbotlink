import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_attachment.dart';
import '../models/video_compression_policy.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

/// Demande la qualité d'envoi d'une vidéo : Standard (par défaut) ou HD.
///
/// Chaque option annonce la taille probable du fichier : c'est ce qui
/// coûte sur un forfait mobile, et ce qui décide si l'envoi passera en 3G.
/// Renvoie `null` si la personne referme la feuille sans choisir — la
/// vidéo n'est alors pas envoyée.
Future<VideoSendQuality?> showVideoQualitySheet({
  required int durationMs,
  required int originalBytes,
}) {
  final isDark = Get.find<ThemeController>().isDarkMode;
  final ink = isDark ? AppColors.white : AppColors.black;
  final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

  String size(VideoSendQuality q) => '≈ ${ChatAttachment.sizeLabel(
        VideoCompressionPolicy.estimateBytes(
          quality: q,
          durationMs: durationMs,
          originalBytes: originalBytes,
        ),
      )}';

  Widget option({
    required VideoSendQuality value,
    required IconData icon,
    required String title,
    required String subtitle,
    String? tag,
  }) =>
      ListTile(
        onTap: () => Get.back(result: value),
        leading: Icon(icon, color: AppColors.orange),
        title: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ink,
              ),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
        ),
        trailing: Text(
          size(value),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      );

  return Get.bottomSheet<VideoSendQuality>(
    Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Qualité de la vidéo',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Original : ${ChatAttachment.sizeLabel(originalBytes)}',
                style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
              ),
            ),
            option(
              value: VideoSendQuality.standard,
              icon: Icons.sd_outlined,
              title: 'Standard',
              tag: 'Recommandé',
              subtitle: 'Envoi rapide, économise les données',
            ),
            option(
              value: VideoSendQuality.hd,
              icon: Icons.hd_outlined,
              title: 'HD',
              subtitle: 'Image plus fine, envoi plus long',
            ),
          ],
        ),
      ),
    ),
  );
}
