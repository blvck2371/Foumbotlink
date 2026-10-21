import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/screen_guard.dart';
import '../theme/app_colors.dart';

/// Masque son enfant tant que l'écran est enregistré ou recopié ailleurs.
///
/// C'est la seule protection qu'iOS rende possible, et elle ne vaut que
/// pour l'enregistrement : `UIScreen.isCaptured` se sait **avant** que
/// rien soit capté, donc on peut retirer le contenu à temps. Une capture
/// d'écran, elle, ne s'annonce jamais — voir [ScreenGuard.onScreenshot].
///
/// Sur Android, où la fenêtre est verrouillée par `FLAG_SECURE`,
/// [ScreenGuard.isCaptured] reste faux et ce widget est transparent : le
/// système fait déjà le noir, inutile de le doubler.
class CaptureShield extends StatelessWidget {
  const CaptureShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenGuard.isCaptured,
      builder: (context, captured, child) {
        if (!captured) return child!;
        return const _Blanked();
      },
      child: child,
    );
  }
}

class _Blanked extends StatelessWidget {
  const _Blanked();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.black,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.screenshot_monitor_outlined,
            color: AppColors.orange,
            size: 44,
          ),
          const SizedBox(height: 16),
          Text(
            'Enregistrement d’écran détecté',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ce message ne se voit qu’une fois : il reste masqué tant que '
            'l’écran est enregistré ou recopié.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: AppColors.whiteMuted,
            ),
          ),
        ],
      ),
    );
  }
}
