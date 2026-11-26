import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/dossier_controller.dart';
import '../../models/dossier.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

/// Côté habitant : « où en est mon dossier ? ».
///
/// L'écran répond dans cet ordre, qui est celui de l'usage : le code à
/// recopier sur la chemise **avant** d'aller au guichet, puis l'état des
/// dossiers déjà déposés.
class DossierTrackingScreen extends GetView<DossierController> {
  const DossierTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Suivi de mes dossiers'),
        body: !controller.isSignedIn
            ? _SignedOutNotice(ink: ink, muted: muted)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _TrackingCodeCard(isDark: isDark, ink: ink, muted: muted),
                  const SizedBox(height: 26),
                  if (controller.isLoading.value)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: FoumbotLoader()),
                    )
                  else if (controller.dossiers.isEmpty)
                    _EmptyState(ink: ink, muted: muted)
                  else ...[
                    if (controller.active.isNotEmpty) ...[
                      _SectionLabel('EN COURS', muted: muted),
                      const SizedBox(height: 10),
                      for (final dossier in controller.active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DossierCard(
                            dossier: dossier,
                            isDark: isDark,
                            ink: ink,
                            muted: muted,
                          ),
                        ),
                    ],
                    if (controller.closed.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionLabel('TERMINÉS', muted: muted),
                      const SizedBox(height: 10),
                      for (final dossier in controller.closed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DossierCard(
                            dossier: dossier,
                            isDark: isDark,
                            ink: ink,
                            muted: muted,
                          ),
                        ),
                    ],
                  ],
                ],
              ),
      );
    });
  }
}

/// Le code de suivi, en grand. C'est l'objet principal de l'écran : il
/// doit se lire d'un coup d'œil et se recopier sans hésitation sur une
/// chemise cartonnée.
class _TrackingCodeCard extends GetView<DossierController> {
  const _TrackingCodeCard({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final code = controller.trackingCode.value;
    final error = controller.codeError.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.orangeDeep, AppColors.orange],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VOTRE CODE DE SUIVI',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: AppColors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          if (error != null)
            Text(
              error,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: AppColors.white,
              ),
            )
          else if (code.isEmpty)
            const SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FoumbotLoader.button(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    // Espacé : sept caractères collés se recopient mal,
                    // et c'est exactement ce qu'on demande de faire.
                    code.split('').join(' '),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: controller.copyCode,
                  tooltip: 'Copier le code',
                  icon: const Icon(Icons.copy_rounded, color: AppColors.white),
                ),
              ],
            ),
          if (code.isNotEmpty && error == null) ...[
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: TrackingCode.qrPayload(code),
                  size: 170,
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.white,
                  semanticsLabel: 'QR code de suivi',
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Au guichet, montrez ce QR code : la structure le scanne et '
            'votre dossier apparaît ici, étape par étape. Vous pouvez aussi '
            'écrire le code sur la chemise de votre dossier.',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'un dossier : l'essentiel visible sans ouvrir, la frise en
/// miniature, et le détail d'un tap.
class _DossierCard extends StatelessWidget {
  const _DossierCard({
    required this.dossier,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final Dossier dossier;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final color = dossierColor(dossier);

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Get.toNamed(
          AppRoutes.dossierDetail,
          arguments: dossier,
          preventDuplicates: false,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      dossier.title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DossierStatusChip(dossier: dossier),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dossier.structureName,
                style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
              ),
              const SizedBox(height: 14),
              DossierTimeline(dossier: dossier, muted: muted),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mis à jour ${formatDossierDate(dossier.updatedAt)}',
                      style: GoogleFonts.manrope(fontSize: 12, color: muted),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Briques partagées avec l'écran de détail et le guichet
// ---------------------------------------------------------------------------

/// Couleur d'un état. Le vert et le rouge ne sont employés qu'aux deux
/// issues réellement définitives ; tout ce qui est en mouvement reste
/// dans l'orange de la marque, pour ne pas transformer une étape normale
/// en alerte.
Color dossierStatusColor(DossierStatus status) => switch (status) {
  DossierStatus.receptionne => AppColors.blue,
  DossierStatus.enCours => AppColors.orange,
  DossierStatus.complementRequis => AppColors.danger,
  DossierStatus.termine => AppColors.success,
  DossierStatus.retire => AppColors.gray,
  DossierStatus.rejete => AppColors.danger,
};

IconData dossierStatusIcon(DossierStatus status) => switch (status) {
  DossierStatus.receptionne => Icons.inbox_rounded,
  DossierStatus.enCours => Icons.autorenew_rounded,
  DossierStatus.complementRequis => Icons.report_problem_outlined,
  DossierStatus.termine => Icons.task_alt_rounded,
  DossierStatus.retire => Icons.check_circle_outline_rounded,
  DossierStatus.rejete => Icons.cancel_outlined,
};

String formatDossierDate(DateTime date) {
  final now = DateTime.now();
  final sameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  if (sameDay) return 'aujourd’hui à ${DateFormat('HH:mm').format(date)}';
  final yesterday = now.subtract(const Duration(days: 1));
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'hier à ${DateFormat('HH:mm').format(date)}';
  }
  return 'le ${DateFormat('d MMMM yyyy à HH:mm', 'fr_FR').format(date)}';
}

/// Couleur de l'état d'un dossier : celle de son embranchement ou de sa
/// clôture, sinon celle de l'étape atteinte (réception, traitement, fin).
Color dossierColor(Dossier d) =>
    d.status.isBranch || d.status == DossierStatus.retire
    ? dossierStatusColor(d.status)
    : dossierStatusColor(Dossier.statusForStep(d.currentStep, d.steps.length));

class DossierStatusChip extends StatelessWidget {
  const DossierStatusChip({super.key, required this.dossier});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final color = dossierColor(dossier);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(dossierStatusIcon(dossier.status), size: 13, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                dossier.currentLabel,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frise des étapes du dossier, telles que la structure les a définies.
///
/// Un embranchement (pièce manquante, rejet) n'ajoute pas de case : il
/// colore l'étape en cours en rouge — c'est une interruption, pas un
/// chemin plus long.
class DossierTimeline extends StatelessWidget {
  const DossierTimeline({
    super.key,
    required this.dossier,
    required this.muted,
  });

  final Dossier dossier;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final steps = dossier.steps;
    final status = dossier.status;
    final reached = dossier.currentStep;
    final branchColor = dossierStatusColor(status);
    final done = status == DossierStatus.retire;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i <= reached
                        ? (status.isBranch && i == reached
                              ? branchColor
                              : done
                              ? AppColors.success
                              : AppColors.orange)
                        : muted.withValues(alpha: 0.22),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i],
                  style: GoogleFonts.manrope(
                    fontSize: 9.5,
                    height: 1.25,
                    fontWeight: i == reached
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: i <= reached ? null : muted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (i != steps.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.muted});

  final String text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: muted,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.ink, required this.muted});

  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_outlined,
              size: 38,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Aucun dossier suivi',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Le suivi commence quand le service saisit votre code à la '
            'réception de votre dossier. Rien à faire ici avant votre '
            'passage au guichet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.45,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice({required this.ink, required this.muted});

  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: AppColors.orange,
            ),
            const SizedBox(height: 16),
            Text(
              'Connectez-vous pour suivre vos dossiers',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Votre code de suivi est rattaché à votre compte : c’est lui '
              'qui relie votre dossier au guichet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.45,
                color: muted,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: Get.find<DossierController>().signInAndLoad,
              child: const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
