import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/dossier.dart';
import '../../services/dossier_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import 'dossier_tracking_screen.dart';

/// Le détail d'un dossier : ce qu'il en est, ce que la personne doit
/// faire, et tout ce qui s'est passé depuis le dépôt.
///
/// L'écran répond d'abord à « et maintenant ? », ensuite seulement à
/// « que s'est-il passé ? » — l'historique est utile, mais il ne doit pas
/// s'interposer devant la consigne du moment.
class DossierDetailScreen extends StatelessWidget {
  const DossierDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    // Deux entrées possibles : depuis la liste, où le dossier est déjà
    // chargé et s'affiche sans attente ; depuis une notification, où l'on
    // n'a que son identifiant.
    final argument = Get.arguments;
    final initial = argument is Dossier ? argument : null;
    final id = initial?.id ?? argument as String;

    return StreamBuilder<Dossier?>(
      stream: Get.find<DossierService>().watchOne(id),
      initialData: initial,
      builder: (context, snapshot) {
        final dossier = snapshot.data;
        if (dossier == null) {
          return Obx(() {
            final isDark = theme.isDarkMode;
            return Scaffold(
              backgroundColor: isDark ? AppColors.black : AppColors.white,
              appBar: FoumbotAppBar(isDark: isDark, title: 'Mon dossier'),
              body: Center(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const FoumbotLoader()
                    : Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Ce dossier n’est plus accessible.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.whiteMuted
                                : AppColors.gray,
                          ),
                        ),
                      ),
              ),
            );
          });
        }
        return _DetailBody(dossier: dossier, theme: theme);
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.dossier, required this.theme});

  final Dossier dossier;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final color = dossierColor(dossier);

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Mon dossier'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              dossier.title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Déposé auprès de ${dossier.structureName}',
              style: GoogleFonts.manrope(fontSize: 13.5, color: muted),
            ),
            const SizedBox(height: 22),

            // Ce qu'il faut comprendre maintenant, avant tout le reste.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.14 : 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        dossierStatusIcon(dossier.status),
                        color: color,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          dossier.currentLabel,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _hint(dossier),
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                  if (dossier.currentNote case final note?
                      when note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.black : AppColors.white)
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        note,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
            DossierTimeline(dossier: dossier, muted: muted),
            const SizedBox(height: 28),

            _InfoRow(
              label: 'Code de suivi',
              value: dossier.trackingCode.split('').join(' '),
              ink: ink,
              muted: muted,
            ),
            if (dossier.reference case final reference?
                when reference.isNotEmpty)
              _InfoRow(
                label: 'Référence du service',
                value: reference,
                ink: ink,
                muted: muted,
              ),
            _InfoRow(
              label: 'Déposé',
              value: formatDossierDate(dossier.createdAt),
              ink: ink,
              muted: muted,
            ),

            const SizedBox(height: 26),
            Text(
              'HISTORIQUE',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: muted,
              ),
            ),
            const SizedBox(height: 14),
            // Du plus récent au plus ancien : ce qui vient d'arriver est
            // ce qu'on cherche en ouvrant l'historique.
            for (final (index, event) in dossier.events.reversed.indexed)
              _HistoryTile(
                event: event,
                isLast: index == dossier.events.length - 1,
                ink: ink,
                muted: muted,
              ),
          ],
        ),
      );
    });
  }
}

/// Ce que la personne doit comprendre à l'étape où elle en est.
String _hint(Dossier d) {
  if (d.status.isBranch || d.status.isClosed) return d.status.citizenHint;
  final n = d.steps.length;
  final i = d.currentStep;
  if (i == n - 1) {
    return 'Dernière étape atteinte chez ${d.structureName}. Si un '
        'document est à retirer, vous pouvez vous présenter au guichet.';
  }
  return 'Étape ${i + 1} sur $n. Prochaine étape : « ${d.steps[i + 1]} ». '
      'Vous serez prévenu dès que le dossier avance.';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.ink,
    required this.muted,
  });

  final String label;
  final String value;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.manrope(fontSize: 13, color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne d'historique, avec le fil vertical qui relie les étapes.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.event,
    required this.isLast,
    required this.ink,
    required this.muted,
  });

  final DossierEvent event;
  final bool isLast;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final color = dossierStatusColor(event.status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  dossierStatusIcon(event.status),
                  size: 13,
                  color: color,
                ),
              ),
              // Pas de fil sous la dernière étape : il pendrait dans le
              // vide sous le dépôt initial.
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: muted.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDossierDate(event.at),
                    style: GoogleFonts.manrope(fontSize: 12, color: muted),
                  ),
                  if (event.note case final note? when note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      note,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.4,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
