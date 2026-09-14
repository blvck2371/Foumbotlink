import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/scam_guard.dart';
import '../theme/app_colors.dart';

/// Rappel de prudence affiché sur une annonce et en tête de discussion.
///
/// L'app ne gère aucun paiement : elle ne peut pas empêcher une arnaque,
/// seulement rappeler les trois réflexes qui la rendent presque
/// impossible. Court exprès — un pavé de conditions ne se lit pas.
class SafetyNotice extends StatelessWidget {
  const SafetyNotice({super.key, required this.isDark, this.compact = false});

  final bool isDark;

  /// Version repliée sur une ligne, pour un en-tête de discussion.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: compact ? 16 : 20,
            color: AppColors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: compact
                ? Text(
                    kSafetyTips.first,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.9),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Avant de conclure',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final tip in kSafetyTips)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '• $tip',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              height: 1.4,
                              color: muted,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Alerte déclenchée par un message précis — plus forte que le rappel
/// permanent, parce qu'elle vise ce qui vient d'être écrit.
class ScamAlertBanner extends StatelessWidget {
  const ScamAlertBanner({
    super.key,
    required this.warning,
    required this.isDark,
    this.onDismiss,
  });

  final String warning;
  final bool isDark;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    const danger = AppColors.danger;
    final ink = isDark ? AppColors.white : AppColors.black;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attention',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  warning,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.45,
                    color: ink.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                size: 18,
                color: ink.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}
