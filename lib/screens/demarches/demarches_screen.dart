import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/account_type.dart';
import '../../controllers/demarches_controller.dart';
import '../../models/demarche.dart';
import '../../services/user_profile_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

class DemarchesScreen extends StatelessWidget {
  const DemarchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final catalogue = Get.find<DemarchesController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: 'Démarches',
          actions: [
            IconButton(
              tooltip: 'Thème',
              onPressed: theme.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.orange,
              ),
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      AppColors.black,
                      AppColors.blackSoft,
                      AppColors.blackElevated,
                    ]
                  : const [
                      AppColors.white,
                      AppColors.whiteSoft,
                      AppColors.white,
                    ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Services et formalités',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Retrouvez toutes les démarches administratives de la commune de Foumbot : '
                'documents requis, lieux, coûts et étapes.',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.45,
                  color: muted,
                ),
              ),
              const SizedBox(height: 22),

              // Le suivi passe **avant** le catalogue : c'est ce que la
              // plupart des gens viennent faire ici, une fois leur
              // dossier déposé. Le guide, lui, se consulte une fois.
              const _TrackingEntry(),
              const SizedBox(height: 26),

              if (catalogue.isLoading.value)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: FoumbotLoader()),
                )
              else if (catalogue.loadError.value case final error?)
                _CatalogueNotice(
                  icon: Icons.wifi_off_rounded,
                  title: 'Démarches indisponibles',
                  message: error,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                )
              else if (catalogue.isEmpty)
                _CatalogueNotice(
                  icon: Icons.assignment_outlined,
                  title: 'Aucune démarche publiée',
                  message: 'Les structures de la commune n’ont pas encore '
                      'décrit leurs démarches. Chacune publie les siennes, '
                      'avec ses propres pièces, tarifs et délais.',
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                )
              else
                // `byCategory` est lu **ici**, dans la closure de l'`Obx` :
                // une lecture faite dans le `build` de la section enfant
                // se ferait hors du champ réactif, et la liste resterait
                // vide à l'arrivée des données.
                for (final cat in DemarcheCategory.values) ...[
                  _CategorySection(
                    items: catalogue.byCategory(cat),
                    category: cat,
                    isDark: isDark,
                    ink: ink,
                    muted: muted,
                  ),
                  const SizedBox(height: 20),
                ],
            ],
          ),
        ),
      );
    });
  }
}

/// Porte d'entrée vers le suivi des dossiers, et vers le guichet pour
/// les structures validées.
///
/// Un compte structure voit les deux : il dépose ses propres dossiers
/// comme tout le monde, et reçoit ceux des autres.
class _TrackingEntry extends StatelessWidget {
  const _TrackingEntry();

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final profile = Get.find<UserProfileService>().profile.value;
    final isDesk =
        profile != null &&
        profile.accountType == AccountType.structure &&
        profile.verified;

    return Column(
      children: [
        _EntryCard(
          isDark: isDark,
          icon: Icons.pending_actions_rounded,
          title: 'Suivre mes dossiers',
          subtitle:
              'Votre code de suivi et l’avancement de vos démarches, en '
              'temps réel.',
          highlighted: true,
          onTap: () => Get.toNamed(AppRoutes.dossiers),
        ),
        if (isDesk) ...[
          const SizedBox(height: 12),
          _EntryCard(
            isDark: isDark,
            icon: Icons.desk_rounded,
            title: 'Guichet',
            subtitle:
                'Réceptionner un dossier et faire avancer ceux du service.',
            onTap: () => Get.toNamed(AppRoutes.structureDesk),
          ),
          const SizedBox(height: 10),
          _EntryCard(
            isDark: isDark,
            icon: Icons.assignment_outlined,
            title: 'Mes démarches',
            subtitle:
                'Publier et tenir à jour les démarches de votre guichet.',
            onTap: () => Get.toNamed(AppRoutes.structureDemarches),
          ),
        ],
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Material(
      color: highlighted
          ? AppColors.orange.withValues(alpha: isDark ? 0.14 : 0.07)
          : (isDark ? AppColors.blackElevated : AppColors.whiteSoft),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted
                  ? AppColors.orange
                  : ink.withValues(alpha: 0.08),
              width: highlighted ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.orange.withValues(alpha: 0.13),
                ),
                child: Icon(icon, color: AppColors.orange, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.items,
    required this.category,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final List<Demarche> items;
  final DemarcheCategory category;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(category.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(
              category.label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _DemarcheCard(
            demarche: items[i],
            isDark: isDark,
            ink: ink,
            muted: muted,
          ),
        ],
      ],
    );
  }
}

class _DemarcheCard extends StatelessWidget {
  const _DemarcheCard({
    required this.demarche,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final Demarche demarche;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Get.toNamed(AppRoutes.demarcheDetail, arguments: demarche),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppColors.orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
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
                      demarche.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Text(
                          demarche.delai,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(Icons.payments_outlined, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            demarche.cout,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message pleine largeur quand le catalogue ne montre rien — vide, ou
/// injoignable. Distinguer les deux évite de laisser croire que la
/// commune n'a aucune démarche alors que c'est le réseau qui manque.
class _CatalogueNotice extends StatelessWidget {
  const _CatalogueNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isDark;
  final Color ink;
  final Color muted;

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
          Icon(icon, size: 30, color: AppColors.orange),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
