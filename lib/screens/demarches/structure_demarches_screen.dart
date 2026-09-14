import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/structure_demarches_controller.dart';
import '../../models/demarche.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

/// « Mes démarches » — ce qu'une structure publie pour les habitants.
///
/// Chaque structure décrit ses propres guichets : ni les pièces, ni les
/// tarifs, ni les délais ne sont les mêmes d'une mairie à une préfecture,
/// et une liste unique livrée avec l'application donnait tort à tout le
/// monde sauf à une.
class StructureDemarchesScreen extends GetView<StructureDemarchesController> {
  const StructureDemarchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final items = controller.demarches;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Mes démarches'),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.white,
          onPressed: () => _openForm(context, isDark: isDark),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Nouvelle',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
        body: controller.isLoading.value
            ? const Center(child: FoumbotLoader())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                children: [
                  Text(
                    'Ce que vous publiez ici est ce que les habitants '
                    'voient dans « Démarches », et ce que vous retrouvez '
                    'au guichet à la réception d’un dossier.',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!controller.canPublish) ...[
                    _Notice(
                      icon: Icons.hourglass_top_rounded,
                      text: 'Votre compte structure doit être validé avant '
                          'de publier des démarches.',
                      isDark: isDark,
                      muted: muted,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (items.isEmpty)
                    _EmptyState(
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                      onImport: () => _import(context),
                    )
                  else ...[
                    for (final demarche in items) ...[
                      _DemarcheRow(
                        demarche: demarche,
                        isDark: isDark,
                        ink: ink,
                        muted: muted,
                        onEdit: () => _openForm(
                          context,
                          isDark: isDark,
                          demarche: demarche,
                        ),
                        onDelete: () => _delete(context, demarche),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (controller.modelesDisponibles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => _import(context),
                        icon: const Icon(
                          Icons.download_rounded,
                          color: AppColors.orange,
                        ),
                        label: Text(
                          'Reprendre ${controller.modelesDisponibles.length} '
                          'modèle(s) courant(s)',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      );
    });
  }

  Future<void> _import(BuildContext context) async {
    final confirmed = await confirmAction(
      title: 'Reprendre les modèles ?',
      message: 'Les démarches courantes seront ajoutées à votre liste. '
          'Corrigez ensuite vos lieux, tarifs et délais — les modèles ne '
          'les connaissent pas.',
      confirmLabel: 'Reprendre',
      destructive: false,
    );
    if (!confirmed) return;

    final error = await controller.importerModeles();
    if (error != null) {
      Get.snackbar('Import impossible', error, duration: const Duration(seconds: 4));
      return;
    }
    Get.snackbar(
      'Modèles repris',
      'Relisez chaque démarche : les tarifs et lieux sont à adapter.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _delete(BuildContext context, Demarche demarche) async {
    final confirmed = await confirmAction(
      title: 'Retirer cette démarche ?',
      message: '« ${demarche.title} » ne sera plus visible par les '
          'habitants. Les dossiers déjà reçus ne sont pas touchés.',
      confirmLabel: 'Retirer',
    );
    if (!confirmed) return;

    final error = await controller.remove(demarche);
    if (error != null) {
      Get.snackbar('Suppression impossible', error,
          duration: const Duration(seconds: 4));
    }
  }

  Future<void> _openForm(
    BuildContext context, {
    required bool isDark,
    Demarche? demarche,
    DemarcheModele? modele,
  }) async {
    controller.startEditing(demarche: demarche, modele: modele);
    await Get.bottomSheet<void>(
      _DemarcheForm(isDark: isDark),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.isDark,
    required this.muted,
  });

  final IconData icon;
  final String text;
  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.onImport,
  });

  final bool isDark;
  final Color ink;
  final Color muted;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aucune démarche publiée',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez vos démarches une par une, ou partez des modèles '
            'courants et adaptez-les à votre guichet.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.download_rounded, color: AppColors.orange),
            label: Text(
              'Partir des modèles courants',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemarcheRow extends StatelessWidget {
  const _DemarcheRow({
    required this.demarche,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.onEdit,
    required this.onDelete,
  });

  final Demarche demarche;
  final bool isDark;
  final Color ink;
  final Color muted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Text(demarche.category.icon,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demarche.title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${demarche.category.label} · ${demarche.cout}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Retirer',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le formulaire de création / modification.
class _DemarcheForm extends GetView<StructureDemarchesController> {
  const _DemarcheForm({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackSoft : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SingleChildScrollView(
          child: Obx(() {
            final isEdit = controller.editing.value != null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEdit ? 'Modifier la démarche' : 'Nouvelle démarche',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 16),
                _Label(text: 'Catégorie', muted: muted),
                DropdownButtonFormField<DemarcheCategory>(
                  initialValue: controller.category.value,
                  isExpanded: true,
                  dropdownColor:
                      isDark ? AppColors.blackElevated : AppColors.white,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor:
                        isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    for (final cat in DemarcheCategory.values)
                      DropdownMenuItem(
                        value: cat,
                        child: Text(
                          '${cat.icon}  ${cat.label}',
                          style:
                              GoogleFonts.manrope(fontSize: 14, color: ink),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setCategory(value);
                  },
                ),
                const SizedBox(height: 14),
                _Field(
                  label: 'Intitulé',
                  hint: 'Acte de naissance',
                  ctrl: controller.titleCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
                _Field(
                  label: 'Description',
                  hint: 'À quoi sert ce document ?',
                  ctrl: controller.descriptionCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  maxLines: 3,
                ),
                _Field(
                  label: 'Pièces à fournir — une par ligne',
                  hint: 'Certificat de naissance\nCNI du père',
                  ctrl: controller.documentsCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  maxLines: 5,
                ),
                _Field(
                  label: 'Lieu',
                  hint: 'Mairie de Foumbot — État civil',
                  ctrl: controller.lieuCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
                _Field(
                  label: 'Coût',
                  hint: 'Gratuit, ou 1 000 FCFA',
                  ctrl: controller.coutCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
                _Field(
                  label: 'Délai',
                  hint: '24 à 72 heures',
                  ctrl: controller.delaiCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
                _Field(
                  label: 'Étapes — une par ligne',
                  hint: 'Se présenter au guichet\nRemplir le formulaire',
                  ctrl: controller.etapesCtrl,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  maxLines: 5,
                ),
                if (controller.formError.value case final error?) ...[
                  const SizedBox(height: 6),
                  Text(
                    error,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: controller.isSaving.value
                      ? null
                      : () async {
                          if (await controller.save()) Get.back<void>();
                        },
                  child: controller.isSaving.value
                      ? const FoumbotLoader.button()
                      : Text(
                          isEdit ? 'Enregistrer' : 'Publier',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.muted});

  final String text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: muted,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.ctrl,
    required this.isDark,
    required this.ink,
    required this.muted,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final TextEditingController ctrl;
  final bool isDark;
  final Color ink;
  final Color muted;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(text: label, muted: muted),
        FormFieldBox(
          isDark: isDark,
          child: TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: GoogleFonts.manrope(fontSize: 14, height: 1.4, color: ink),
            decoration: InputDecoration.collapsed(
              hintText: hint,
              hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
