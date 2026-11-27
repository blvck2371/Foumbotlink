import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/directory_controller.dart';
import '../../models/pro_listing.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import 'directory_widgets.dart';

/// Annuaire des professionnels de la commune : on cherche un métier
/// (frigoriste, électricien…), les mieux notés et les plus recommandés
/// apparaissent en premier.
class DirectoryScreen extends GetView<DirectoryController> {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final loading = controller.isLoading.value;
      final error = controller.error.value;
      final items = controller.visible;
      final hasMine = controller.myListing != null;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Annuaire'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: controller.openEditor,
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.white,
          icon: Icon(hasMine ? Icons.edit_outlined : Icons.add_business),
          label: Text(
            hasMine ? 'Ma fiche pro' : 'Je suis un pro',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
        body: RefreshIndicator(
          color: AppColors.orange,
          onRefresh: controller.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMMUNE DE FOUMBOT',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.orange,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Trouver un professionnel',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Les mieux notés par les habitants apparaissent en '
                        'premier.',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SearchField(isDark: isDark, ink: ink, muted: muted),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _CategoryChips(isDark: isDark)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: FoumbotLoader()),
                )
              else if (error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: Icons.cloud_off,
                    title: 'Annuaire indisponible',
                    body: error,
                    ink: ink,
                    muted: muted,
                  ),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: Icons.search_off,
                    title: controller.listings.isEmpty
                        ? 'L’annuaire est encore vide'
                        : 'Aucun professionnel trouvé',
                    body: controller.listings.isEmpty
                        ? 'Vous exercez un métier ? Créez votre fiche pour '
                            'être trouvé par les habitants.'
                        : 'Essayez un autre métier ou d’autres mots.',
                    ink: ink,
                    muted: muted,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ProCard(
                      listing: items[i],
                      // Le podium n'a de sens que pour des notes réelles.
                      rank: i < 3 && items[i].hasRating ? i + 1 : null,
                      isMine: items[i].id == controller.myUid,
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                      onTap: () => controller.openDetail(items[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _SearchField extends GetView<DirectoryController> {
  const _SearchField({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller.searchCtrl,
              onChanged: controller.setQuery,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.manrope(color: ink, fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Frigoriste, électricien, quartier…',
                hintStyle: GoogleFonts.manrope(color: muted),
              ),
            ),
          ),
          Obx(
            () => controller.query.value.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Effacer',
                    onPressed: controller.clearQuery,
                    icon: Icon(Icons.close, color: muted, size: 20),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Puces de métiers. Ceux qui ont des fiches passent devant, avec leur
/// nombre ; les autres restent sélectionnables (« aucun frigoriste
/// inscrit » est aussi une réponse).
class _CategoryChips extends GetView<DirectoryController> {
  const _CategoryChips({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.category.value;
      final counts = controller.countsByCategory;
      final cats = [...ProCategory.values]
        ..sort((a, b) {
          final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          return byCount != 0 ? byCount : a.index.compareTo(b.index);
        });
      return SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: cats.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _chip(
                label: 'Tous',
                icon: Icons.apps,
                selected: selected == null,
                onTap: () => controller.category.value = null,
              );
            }
            final c = cats[i - 1];
            final n = counts[c] ?? 0;
            return _chip(
              label: n > 0 ? '${c.label} ($n)' : c.label,
              icon: c.icon,
              selected: selected == c,
              onTap: () => controller.toggleCategory(c),
            );
          },
        ),
      );
    });
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final fg = selected
        ? AppColors.white
        : (isDark ? AppColors.white : AppColors.black);
    return Material(
      color: selected
          ? AppColors.orangeReadable
          : (isDark ? AppColors.blackElevated : AppColors.whiteSoft),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({
    required this.listing,
    required this.rank,
    required this.isMine,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.onTap,
  });

  final ProListing listing;
  final int? rank;
  final bool isMine;
  final bool isDark;
  final Color ink;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackSoft : AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? AppColors.blackElevated
                  : AppColors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProAvatar(listing: listing, isDark: isDark),
                  if (rank != null)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orangeReadable,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'N°$rank',
                          style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· Vous',
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        listing.categoryLabel,
                        if (listing.quartier.isNotEmpty) listing.quartier,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontSize: 13, color: muted),
                    ),
                    const SizedBox(height: 6),
                    RatingLine(listing: listing, ink: ink, muted: muted),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    required this.ink,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: muted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 14, height: 1.4, color: muted),
          ),
        ],
      ),
    );
  }
}
