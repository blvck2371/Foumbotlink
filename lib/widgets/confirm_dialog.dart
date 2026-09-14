import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

/// Confirmation d'une action irréversible (suppression d'une publication,
/// d'un commentaire, blocage d'un compte). Renvoie `true` seulement si
/// l'utilisateur a explicitement confirmé — un retour arrière ou un tap
/// hors de la boîte annule.
Future<bool> confirmAction({
  required String title,
  required String message,
  String confirmLabel = 'Supprimer',
  String cancelLabel = 'Annuler',
  bool destructive = true,
}) async {
  final isDark = Get.find<ThemeController>().isDarkMode;
  final ink = isDark ? AppColors.white : AppColors.black;
  final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

  final result = await Get.dialog<bool>(
    AlertDialog(
      backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.manrope(color: muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text(
            cancelLabel,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: destructive ? AppColors.orange : AppColors.blue,
            ),
          ),
        ),
      ],
    ),
    barrierDismissible: true,
  );

  return result ?? false;
}
