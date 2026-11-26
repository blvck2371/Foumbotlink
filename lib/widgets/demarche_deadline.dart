import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/demarche.dart';
import '../services/demarche_companion.dart';
import '../theme/app_colors.dart';

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Délai fixé par la structure pour une démarche : invite à saisir la date
/// de l'événement, puis compte à rebours avec rappels. Rien ici n'est
/// codé en dur : jours et libellé viennent de la fiche publiée.
class DemarcheDeadlineBlock extends StatelessWidget {
  const DemarcheDeadlineBlock({
    super.key,
    required this.demarche,
    required this.isDark,
  });

  final Demarche demarche;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (!demarche.hasEcheance) return const SizedBox.shrink();
    final companion = Get.find<DemarcheCompanion>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final since = demarche.echeanceDepuis!.trim();

    return Obx(() {
      final saved = companion.deadlineFor(demarche);
      if (saved != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeadlineCard(deadline: saved, isDark: isDark),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pick(context, saved.date),
                  child: Text(
                    'Modifier la date',
                    style: GoogleFonts.manrope(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => companion.removeDeadline(demarche.id),
                  child: Text(
                    'Ne plus suivre',
                    style: GoogleFonts.manrope(color: muted),
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: isDark ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⏳ À faire dans les ${demarche.echeanceJours} jours suivant '
              '$since',
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              kIsWeb
                  ? 'Délai fixé par ${demarche.structureName}. Indiquez la '
                        'date : l’app calcule le dernier jour et l’affiche '
                        'dans « Mes échéances ».'
                  : 'Délai fixé par ${demarche.structureName}. Indiquez la '
                        'date : l’app calcule le dernier jour et vous le '
                        'rappelle avant qu’il ne soit trop tard.',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.4,
                color: muted,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _pick(context, null),
              icon: const Icon(Icons.event_rounded, size: 19),
              label: const Text('Indiquer la date'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: AppColors.white,
                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final days = demarche.echeanceJours!;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      // Assez loin pour couvrir un délai déjà dépassé, sans plus.
      firstDate: now.subtract(Duration(days: days * 3)),
      lastDate: now,
      helpText: 'Date de ${demarche.echeanceDepuis!.trim()}',
      confirmText: 'Valider',
      cancelText: 'Annuler',
    );
    if (picked == null) return;
    await Get.find<DemarcheCompanion>().setDeadline(demarche, picked);
  }
}

/// Une échéance : jours restants, date limite, couleur selon l'urgence.
class DeadlineCard extends StatelessWidget {
  const DeadlineCard({
    super.key,
    required this.deadline,
    required this.isDark,
    this.onTap,
  });

  final SavedDeadline deadline;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final left = deadline.daysLeft();
    final color = left < 0
        ? muted
        : left <= 7
        ? AppColors.danger
        : left <= 30
        ? AppColors.orange
        : AppColors.success;
    final big = left < 0
        ? 'Passé'
        : left == 0
        ? 'Auj.'
        : '$left j';

    return Material(
      color: color.withValues(alpha: isDark ? 0.14 : 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  big,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deadline.title,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      left < 0
                          ? 'Le délai fixé par ${deadline.structureName} est '
                                'passé depuis le ${_date(deadline.dueDate)}. '
                                'Renseignez-vous auprès de la structure.'
                          : 'Jusqu’au ${_date(deadline.dueDate)} inclus · '
                                '${deadline.structureName}',
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
