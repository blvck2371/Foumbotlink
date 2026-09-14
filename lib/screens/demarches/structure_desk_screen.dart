import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/structure_desk_controller.dart';
import '../../models/demarche.dart';
import '../../models/dossier.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/form_field_box.dart';
import 'dossier_tracking_screen.dart';

/// Le guichet d'une structure : réceptionner un dossier, puis le faire
/// avancer.
///
/// L'écran est pensé pour quelqu'un debout derrière un comptoir, avec
/// une chemise cartonnée dans une main et le téléphone dans l'autre. La
/// réception tient en trois gestes — saisir le code, confirmer le nom,
/// choisir la démarche — et le reste de l'écran est la file des dossiers
/// en cours.
class StructureDeskScreen extends GetView<StructureDeskController> {
  const StructureDeskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Guichet'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _ReceptionCard(isDark: isDark, ink: ink, muted: muted),
            const SizedBox(height: 26),
            Row(
              children: [
                Text(
                  'DOSSIERS DU SERVICE',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: muted,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.showClosed.toggle,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    controller.showClosed.value
                        ? 'Masquer les clos'
                        : 'Afficher les clos',
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (controller.isLoading.value)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: FoumbotLoader()),
              )
            else if (controller.visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  controller.dossiers.isEmpty
                      ? 'Aucun dossier réceptionné pour l’instant. '
                            'Saisissez un code ci-dessus pour démarrer un '
                            'suivi.'
                      : 'Aucun dossier en cours. Tout est traité.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.45,
                    color: muted,
                  ),
                ),
              )
            else
              for (final dossier in controller.visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeskDossierCard(
                    dossier: dossier,
                    isDark: isDark,
                    ink: ink,
                    muted: muted,
                  ),
                ),
          ],
        ),
      );
    });
  }
}

/// Formulaire de réception. Il se déroule en deux temps : tant que le
/// code n'a pas désigné quelqu'un, rien d'autre ne s'affiche — inutile
/// de demander la démarche avant de savoir à qui elle appartient.
class _ReceptionCard extends GetView<StructureDeskController> {
  const _ReceptionCard({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final matched = controller.matchedName.value;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.orange),
              const SizedBox(width: 10),
              Text(
                'Réceptionner un dossier',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Saisissez le code de ${TrackingCode.length} caractères inscrit '
            'sur la chemise.',
            style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 14),
          FormFieldBox(
            isDark: isDark,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.codeCtrl,
                    // Volontairement pas désactivé pendant la recherche :
                    // celle-ci suit désormais la frappe, et couper le champ
                    // à chaque septième caractère empêcherait de corriger
                    // une lettre mal lue.
                    enabled: matched == null,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        // Un peu au-delà du strict nécessaire : on tolère
                        // les espaces et tirets que l'on ajoute
                        // spontanément en recopiant, `normalize` les
                        // retire.
                        TrackingCode.length + 4,
                      ),
                      _UpperCaseFormatter(),
                    ],
                    onSubmitted: (_) => controller.lookup(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      color: ink,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: 'A B C 2 3 4 5',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        letterSpacing: 6,
                        color: muted,
                      ),
                    ),
                  ),
                ),
                if (matched == null)
                  controller.isLooking.value
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: FoumbotLoader.button(),
                        )
                      : IconButton(
                          onPressed: controller.lookup,
                          tooltip: 'Rechercher',
                          icon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.orange,
                          ),
                        ),
              ],
            ),
          ),

          if (controller.lookupError.value case final error?) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    error,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Deuxième temps : l'habitant est identifié, on décrit le
          // dossier qu'on lui prend.
          if (matched != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matched,
                          style: GoogleFonts.manrope(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Le seul contrôle possible sur un code recopié à
                        // la main : l'agent a la personne devant lui.
                        Text(
                          'Vérifiez que c’est bien la personne devant vous.',
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: controller.cancelReception,
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Changer',
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Quelle démarche ?',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            // L'app suit l'avancement d'un dossier, elle ne décrit pas ce
            // qu'il contient. Le rappel est ici parce que c'est ici que
            // la faute se commet : la question « quelle démarche ? »
            // appelle spontanément « test VIH » plutôt que « analyse
            // médicale ».
            Text(
              'Nommez le type de démarche, jamais son contenu. Ce libellé '
              's’affiche dans l’application de l’habitant.',
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                height: 1.35,
                color: muted,
              ),
            ),
            const SizedBox(height: 8),
            _DemarchePicker(isDark: isDark, ink: ink, muted: muted),
            const SizedBox(height: 12),
            FormFieldBox(
              isDark: isDark,
              child: TextField(
                controller: controller.referenceCtrl,
                style: GoogleFonts.manrope(fontSize: 14, color: ink),
                decoration: InputDecoration.collapsed(
                  hintText: 'Référence interne (facultatif)',
                  hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: controller.canReceive && !controller.isSaving.value
                    ? () async {
                        final ok = await controller.receive();
                        if (ok) {
                          Get.snackbar(
                            'Dossier réceptionné',
                            'Le suivi est lancé, son propriétaire vient '
                                'd’être prévenu.',
                            duration: const Duration(seconds: 3),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: AppColors.white,
                ),
                child: controller.isSaving.value
                    ? const FoumbotLoader.button()
                    : const Text('Enregistrer la réception'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Choix de la démarche parmi celles **de cette structure**, la saisie
/// libre en dernier recours — un intitulé repris de sa propre liste reste
/// identique d'un dossier à l'autre, ce qui les rend comparables.
class _DemarchePicker extends GetView<StructureDeskController> {
  const _DemarchePicker({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    // `Obx` propre à ce bloc : la liste des démarches arrive d'une écoute
    // Firestore, donc après le premier rendu. Une lecture faite ici sans
    // `Obx` ne s'enregistrerait auprès d'aucun observateur — celui d'un
    // widget ancêtre ne suit que ce qui est lu dans *sa* closure — et le
    // menu resterait vide jusqu'à un rebuild venu d'ailleurs.
    return Obx(() {
      final selected = controller.selectedDemarche.value;
      final mine = controller.demarches;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Demarche?>(
            initialValue: selected,
            isExpanded: true,
            dropdownColor: isDark ? AppColors.blackElevated : AppColors.white,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            hint: Text(
              mine.isEmpty
                  ? 'Aucune démarche publiée'
                  : 'Choisir dans mes démarches',
              style: GoogleFonts.manrope(fontSize: 14, color: muted),
            ),
            items: [
              DropdownMenuItem<Demarche?>(
                value: null,
                child: Text(
                  'Autre (saisie libre)',
                  style: GoogleFonts.manrope(fontSize: 14, color: ink),
                ),
              ),
              for (final demarche in mine)
                DropdownMenuItem<Demarche?>(
                  value: demarche,
                  child: Text(
                    demarche.title,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 14, color: ink),
                  ),
                ),
            ],
            onChanged: controller.selectDemarche,
          ),
          if (mine.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Publiez vos démarches depuis « Mes démarches » pour les '
              'retrouver ici — en attendant, saisissez l’intitulé à la main.',
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.35,
                color: muted,
              ),
            ),
          ],
          if (selected == null) ...[
            const SizedBox(height: 10),
            FormFieldBox(
              isDark: isDark,
              child: TextField(
                controller: controller.titleCtrl,
                onChanged: (_) => controller.selectedDemarche.refresh(),
                style: GoogleFonts.manrope(fontSize: 14, color: ink),
                decoration: InputDecoration.collapsed(
                  hintText: 'Intitulé de la démarche',
                  hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Un dossier dans la file du guichet, avec le geste suivant à portée.
class _DeskDossierCard extends GetView<StructureDeskController> {
  const _DeskDossierCard({
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dossier.ownerName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dossier.title,
                      style: GoogleFonts.manrope(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DossierStatusChip(status: dossier.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.tag_rounded, size: 14, color: muted),
              const SizedBox(width: 5),
              Text(
                dossier.trackingCode,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: muted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  formatDossierDate(dossier.updatedAt),
                  style: GoogleFonts.manrope(fontSize: 12, color: muted),
                ),
              ),
            ],
          ),
          if (dossier.status.nextChoices.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final next in dossier.status.nextChoices)
                  _AdvanceButton(dossier: dossier, next: next, isDark: isDark),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AdvanceButton extends GetView<StructureDeskController> {
  const _AdvanceButton({
    required this.dossier,
    required this.next,
    required this.isDark,
  });

  final Dossier dossier;
  final DossierStatus next;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = dossierStatusColor(next);

    return OutlinedButton.icon(
      onPressed: () => _confirm(context),
      icon: Icon(dossierStatusIcon(next), size: 15, color: color),
      label: Text(
        next.label,
        style: GoogleFonts.manrope(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final noteCtrl = TextEditingController();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    final error = RxnString();

    final confirmed = await Get.dialog<bool>(
      Obx(
        () => AlertDialog(
          backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            next.label,
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dossier.ownerName} recevra une notification et verra '
                'ce changement dans son application.',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  color: muted,
                ),
              ),
              const SizedBox(height: 14),
              FormFieldBox(
                isDark: isDark,
                child: TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  minLines: 2,
                  style: GoogleFonts.manrope(fontSize: 14, color: ink),
                  decoration: InputDecoration.collapsed(
                    hintText: next.requiresNote
                        ? 'Ce qu’il manque, ou le motif du refus'
                        : 'Précision (facultatif)',
                    hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
                  ),
                ),
              ),
              if (error.value case final message?) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('Annuler', style: GoogleFonts.manrope(color: muted)),
            ),
            ElevatedButton(
              onPressed: () async {
                final problem = await controller.advance(
                  dossier,
                  next,
                  note: noteCtrl.text,
                );
                if (problem != null) {
                  error.value = problem;
                  return;
                }
                Get.back(result: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: dossierStatusColor(next),
                foregroundColor: AppColors.white,
              ),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );

    noteCtrl.dispose();
    if (confirmed ?? false) {
      Get.snackbar(
        'Dossier mis à jour',
        '${dossier.ownerName} vient d’être prévenu.',
        duration: const Duration(seconds: 3),
      );
    }
  }
}

/// Le code s'écrit en majuscules quoi qu'il arrive : le clavier d'un
/// téléphone repasse en minuscules après le premier caractère, et un
/// code à moitié minuscule se relit mal quand on le compare à la chemise.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
  );
}
