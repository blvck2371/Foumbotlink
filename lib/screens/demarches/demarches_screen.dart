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
import '../../widgets/verified_badge.dart';
import '../../widgets/demarche_deadline.dart';
import '../../services/demarche_companion.dart';

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
                'Les démarches publiées par les structures de Foumbot — '
                'mairie, services publics, entreprises, associations : '
                'pièces à fournir, lieux, tarifs et étapes.',
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
              const SizedBox(height: 22),
              _SearchField(controller: catalogue, isDark: isDark),
              const SizedBox(height: 22),

              // Échéances suivies (naissance à déclarer, décès…) : ce qui
              // presse passe avant tout le reste.
              _DeadlinesSection(isDark: isDark, ink: ink, muted: muted),

              if (catalogue.isLoading.value)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: FoumbotLoader()),
                )
              else ...[
                if (catalogue.loadError.value case final error?) ...[
                  _CatalogueNotice(
                    icon: Icons.wifi_off_rounded,
                    title: 'Connexion difficile',
                    message: error,
                    isDark: isDark,
                    ink: ink,
                    muted: muted,
                  ),
                  const SizedBox(height: 20),
                ],
                if (catalogue.isEmpty)
                  _CatalogueNotice(
                    icon: Icons.storefront_outlined,
                    title: 'Aucune démarche publiée pour l’instant',
                    message:
                        'Chaque structure — mairie, tribunal, entreprise, '
                        'association… — publie ici ses propres démarches, '
                        'avec ses pièces, ses tarifs et ses délais, et les '
                        'tient à jour.',
                    isDark: isDark,
                    ink: ink,
                    muted: muted,
                  )
                else ...[
                  Text(
                    'Démarches par structure',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Lu **ici**, dans la closure de l'`Obx`, pour que la
                  // liste suive les données et le filtre.
                  _StructureFilter(
                    structures: catalogue.structures,
                    selected: catalogue.selectedStructure.value,
                    onSelect: (uid) => catalogue.selectedStructure.value = uid,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  for (final st in catalogue.visibleStructures) ...[
                    _StructureSection(
                      structure: st,
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (catalogue.visibleStructures.isEmpty)
                    _CatalogueNotice(
                      icon: Icons.search_off_rounded,
                      title: 'Aucune démarche trouvée',
                      message: catalogue.selectedStructure.value == null
                          ? 'Essayez un autre mot : « naissance », '
                                '« terrain », « abonnement »…'
                          : 'Cette structure ne propose pas de démarche '
                                'correspondante. Essayez « Toutes ».',
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                    ),
                ],
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
    // `Obx` propre : le profil arrive souvent après le premier rendu
    // (surtout sur le web), et sans lui les entrées de la structure
    // resteraient masquées.
    return Obx(() {
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
                  'Scanner le QR code d’un habitant, réceptionner son dossier '
                  'et le faire avancer d’étape en étape.',
              onTap: () => Get.toNamed(AppRoutes.structureDesk),
            ),
            const SizedBox(height: 10),
            _EntryCard(
              isDark: isDark,
              icon: Icons.assignment_outlined,
              title: 'Mes démarches (structure)',
              subtitle:
                  'Créer vos démarches, leurs pièces et leurs étapes de suivi, '
                  'et les tenir à jour.',
              onTap: () => Get.toNamed(AppRoutes.structureDemarches),
            ),
          ],
        ],
      );
    });
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

/// Les démarches d'une structure : son nom (qui mène à son profil) puis
/// ses démarches.
class _StructureSection extends StatelessWidget {
  const _StructureSection({
    required this.structure,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final DemarcheStructure structure;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final n = structure.demarches.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Get.toNamed(
            AppRoutes.userProfile,
            arguments: structure.uid,
            preventDuplicates: false,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange.withValues(alpha: 0.13),
                  ),
                  child: const Icon(
                    Icons.account_balance_rounded,
                    color: AppColors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              structure.name,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          // Seule une structure validée peut publier.
                          const VerifiedBadge(size: 15),
                        ],
                      ),
                      Text(
                        '$n démarche${n > 1 ? 's' : ''} · voir le profil',
                        style: GoogleFonts.manrope(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _DemarcheCard(
            demarche: structure.demarches[i],
            isDark: isDark,
            ink: ink,
            muted: muted,
          ),
        ],
      ],
    );
  }
}

/// Filtre par structure : « Toutes », puis chaque structure qui publie.
class _StructureFilter extends StatelessWidget {
  const _StructureFilter({
    required this.structures,
    required this.selected,
    required this.onSelect,
    required this.isDark,
  });

  final List<DemarcheStructure> structures;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (structures.length < 2) return const SizedBox.shrink();
    Widget chip(String label, String? uid) {
      final on = selected == uid;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          onSelected: (_) => onSelect(uid),
          showCheckmark: false,
          selectedColor: AppColors.orange,
          backgroundColor: isDark
              ? AppColors.blackElevated
              : AppColors.whiteSoft,
          side: BorderSide(
            color: on
                ? AppColors.orange
                : AppColors.orange.withValues(alpha: 0.2),
          ),
          labelStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            color: on
                ? AppColors.white
                : (isDark ? AppColors.white : AppColors.black),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('Toutes', null),
          for (final st in structures) chip(st.name, st.uid),
        ],
      ),
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
                    _CardBadges(demarche: demarche, muted: muted),
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

/// Recherche dans les démarches : titre, description, pièces, lieu.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.isDark});

  final DemarchesController controller;
  final bool isDark;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _text = TextEditingController(text: widget.controller.query.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return TextField(
      controller: _text,
      onChanged: (v) => widget.controller.query.value = v,
      textInputAction: TextInputAction.search,
      style: GoogleFonts.manrope(fontSize: 15, color: ink),
      cursorColor: AppColors.orange,
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        prefixIcon: Icon(Icons.search_rounded, color: muted),
        suffixIcon: Obx(
          () => widget.controller.query.value.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Effacer',
                  icon: Icon(Icons.cancel_rounded, color: muted, size: 20),
                  onPressed: () {
                    _text.clear();
                    widget.controller.query.value = '';
                  },
                ),
        ),
        hintText: 'Quelle démarche ? Naissance, abonnement, terrain…',
        hintStyle: GoogleFonts.manrope(fontSize: 14.5, color: muted),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Catégorie et progression de la checklist (« 3/5 pièces »).
class _CardBadges extends StatelessWidget {
  const _CardBadges({required this.demarche, required this.muted});

  final Demarche demarche;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = Get.find<DemarcheCompanion>().progress(demarche);
      final started = p.done > 0;
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (started)
              _Pill(
                text: p.done == p.total
                    ? 'Dossier complet'
                    : '${p.done}/${p.total} pièces prêtes',
                color: p.done == p.total ? AppColors.success : AppColors.orange,
                icon: p.done == p.total
                    ? Icons.check_circle_rounded
                    : Icons.checklist_rounded,
              ),
            _Pill(
              text: '${demarche.category.icon} ${demarche.category.label}',
              color: muted,
            ),
          ],
        ),
      );
    });
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Échéances suivies, la plus proche d'abord.
class _DeadlinesSection extends StatelessWidget {
  const _DeadlinesSection({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = Get.find<DemarcheCompanion>().deadlines.toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mes échéances',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 12),
            for (final d in list) ...[
              DeadlineCard(
                deadline: d,
                isDark: isDark,
                onTap: () {
                  final live = Get.find<DemarchesController>().demarches
                      .firstWhereOrNull((e) => e.id == d.demarcheId);
                  if (live != null) {
                    Get.toNamed(AppRoutes.demarcheDetail, arguments: live);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    });
  }
}
