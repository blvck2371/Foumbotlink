import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/market_controller.dart';
import '../../models/market_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/market_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import 'market_filters_sheet.dart';

class MarketScreen extends GetView<MarketController> {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final items = controller.items;
      final loading = controller.isLoading.value;
      final view = controller.view.value;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: switch (view) {
            MarketView.grille => 'Vente & Achat',
            MarketView.mesAnnonces => 'Mes annonces',
            MarketView.favoris => 'Mes favoris',
          },
          actions: [
            IconButton(
              tooltip: 'Mes alertes',
              onPressed: controller.openSavedSearches,
              icon: const Icon(
                Icons.notifications_active_outlined,
                color: AppColors.orange,
              ),
            ),
            IconButton(
              tooltip: 'Mes favoris',
              onPressed: controller.toggleFavoritesView,
              icon: Icon(
                view == MarketView.favoris
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: AppColors.orange,
              ),
            ),
            IconButton(
              tooltip: 'Mes annonces',
              onPressed: controller.toggleOnlyMine,
              icon: Icon(
                view == MarketView.mesAnnonces
                    ? Icons.sell
                    : Icons.sell_outlined,
                color: AppColors.orange,
              ),
            ),
            IconButton(
              tooltip: 'Thème',
              onPressed: themeController.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.orange,
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: controller.openCreateListing,
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.white,
          elevation: 4,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Publier',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
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
          child: RefreshIndicator(
            color: AppColors.orange,
            backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
            onRefresh: controller.refreshListings,
            child: CustomScrollView(
              controller: controller.scrollController,
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
                          switch (view) {
                            MarketView.grille => 'Marché local',
                            MarketView.mesAnnonces => 'Ce que j’ai publié',
                            MarketView.favoris => 'Ce que j’ai mis de côté',
                          },
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (view) {
                            MarketView.grille =>
                              'Vendez, achetez et proposez vos services entre '
                                  'habitants.',
                            MarketView.mesAnnonces =>
                              'Modifiez, relancez ou retirez vos annonces.',
                            MarketView.favoris =>
                              'Retrouvez les annonces qui vous intéressent.',
                          },
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SearchBar(isDark: isDark, ink: ink, muted: muted),
                        const SizedBox(height: 12),
                        _FilterRow(isDark: isDark),
                        const SizedBox(height: 10),
                        _CategoryFilter(isDark: isDark),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
                if (loading && items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: FoumbotLoader()),
                  )
                else if (!loading && items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(view: view, muted: muted, ink: ink),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    // Grille 2 colonnes façon Leboncoin. `mainAxisExtent`
                    // (hauteur fixe en pixels, pas un ratio) garantit que les
                    // deux colonnes restent alignées quelle que soit la
                    // largeur de l'écran — et que la carte ne peut jamais
                    // déborder, son contenu étant lui-même à hauteur bornée.
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 272,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return _MarketGridCard(
                          item: item,
                          isDark: isDark,
                          timeLabel: controller.timeAgo(item.bumpedAt),
                          isFavorite: controller.isFavorite(item.id),
                          showOwnerState: view == MarketView.mesAnnonces,
                          onTap: () => controller.openListing(item),
                          onFavorite: () => controller.toggleFavorite(item),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80, top: 4),
                    child: Center(
                      child: controller.isLoadingMore.value
                          ? const FoumbotLoader()
                          : (!controller.hasMore.value && items.isNotEmpty)
                          ? _EndOfGrid(
                              isDark: isDark,
                              muted: muted,
                              onReshuffle: controller.reshuffle,
                            )
                          : const SizedBox(height: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Bas de grille
//
// « Fin des annonces » était une impasse : dans une commune on fait vite
// le tour, et le message donnait l'impression d'un marché vide. Comme
// l'ordre est de toute façon tiré au sort, rebattre les cartes remet
// d'autres vendeurs devant — sans une seule requête de plus.
// ---------------------------------------------------------------------------

class _EndOfGrid extends StatelessWidget {
  const _EndOfGrid({
    required this.isDark,
    required this.muted,
    required this.onReshuffle,
  });

  final bool isDark;
  final Color muted;
  final VoidCallback onReshuffle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Vous avez vu toutes les annonces.',
          style: GoogleFonts.manrope(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onReshuffle,
          icon: const Icon(Icons.shuffle, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.orange,
            side: BorderSide(color: AppColors.orange.withValues(alpha: 0.5)),
          ),
          label: const Text('Rebattre les annonces'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// État vide
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.view,
    required this.muted,
    required this.ink,
  });

  final MarketView view;
  final Color muted;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketController>();
    final (icon, title, subtitle) = switch (view) {
      MarketView.favoris => (
        Icons.favorite_border,
        'Aucun favori pour l’instant.',
        'Touchez le cœur d’une annonce pour la retrouver ici.',
      ),
      MarketView.mesAnnonces => (
        Icons.sell_outlined,
        'Vous n’avez pas encore publié.',
        'Appuyez sur « Publier » pour proposer un article.',
      ),
      MarketView.grille => (
        Icons.storefront_outlined,
        'Aucune annonce trouvée.',
        'Essayez d’élargir vos filtres.',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: muted),
            ),
            if (view == MarketView.grille &&
                controller.filters.value.activeCount > 0) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: controller.clearFilters,
                child: Text(
                  'Effacer les filtres',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre de recherche
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketController>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller.searchCtrl,
              style: GoogleFonts.manrope(color: ink),
              textInputAction: TextInputAction.search,
              onSubmitted: controller.search,
              decoration: InputDecoration(
                hintText: 'Moto, terrain, maison, service…',
                hintStyle: GoogleFonts.manrope(color: muted),
                border: InputBorder.none,
              ),
            ),
          ),
          Obx(
            () => controller.filters.value.query.isNotEmpty
                ? GestureDetector(
                    onTap: controller.clearSearch,
                    child: Icon(Icons.close, size: 18, color: muted),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ligne « Filtrer · tri · alerte »
// ---------------------------------------------------------------------------

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketController>();
    return Obx(() {
      final filters = controller.filters.value;
      final count = filters.activeCount;
      final isRandom = filters.sort == MarketSort.aleatoire;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Action(
              icon: Icons.tune,
              label: count > 0 ? 'Filtrer ($count)' : 'Filtrer',
              highlighted: count > 0,
              isDark: isDark,
              onTap: showMarketFiltersSheet,
            ),
            const SizedBox(width: 8),
            _Action(
              icon: isRandom ? Icons.shuffle : Icons.swap_vert,
              label: filters.sort.label,
              highlighted: false,
              isDark: isDark,
              // Sur l'ordre aléatoire, l'appui rebat les cartes ; sur les
              // autres tris il n'y a rien à rebattre, on ouvre les
              // options.
              onTap: isRandom ? controller.reshuffle : showMarketFiltersSheet,
            ),
            const SizedBox(width: 8),
            _Action(
              icon: Icons.notification_add_outlined,
              label: 'Créer une alerte',
              highlighted: false,
              isDark: isDark,
              onTap: controller.saveCurrentSearch,
            ),
          ],
        ),
      );
    });
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.highlighted,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool highlighted;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final fg = highlighted ? AppColors.white : ink;
    return Material(
      color: highlighted ? AppColors.orange : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlighted
                  ? AppColors.orange
                  : ink.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
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

// ---------------------------------------------------------------------------
// Filtres catégories (scroll horizontal)
// ---------------------------------------------------------------------------

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketController>();
    return Obx(() {
      final selected = controller.filters.value.category;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              label: 'Toutes',
              selected: selected == null,
              isDark: isDark,
              onTap: () => controller.setCategory(null),
            ),
            const SizedBox(width: 8),
            for (final cat in MarketCategory.values) ...[
              _Chip(
                label: '${cat.icon} ${cat.label}',
                selected: selected == cat,
                isDark: isDark,
                onTap: () => controller.setCategory(cat),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    return Material(
      color: selected ? AppColors.orange : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.orange : ink.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte grille façon Leboncoin : photo (ou pastille catégorie) en haut, puis
// prix, titre sur 2 lignes et ligne « lieu · date ». Hauteur totale fixée par
// `mainAxisExtent` côté grille ; ici on répartit cette hauteur entre une zone
// photo extensible et un bloc texte de hauteur fixe, pour que les prix et les
// dates s'alignent proprement d'une carte à l'autre sur les deux colonnes.
// ---------------------------------------------------------------------------

class _MarketGridCard extends StatelessWidget {
  const _MarketGridCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.isFavorite,
    required this.showOwnerState,
    required this.onTap,
    required this.onFavorite,
  });

  final MarketItem item;
  final bool isDark;
  final String timeLabel;
  final bool isFavorite;

  /// Dans « Mes annonces » on affiche l'état réel (vendu, expirée) — ces
  /// annonces ne sont plus visibles nulle part ailleurs.
  final bool showOwnerState;

  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final accent = marketTypeColor(item.listingType);
    final surface = isDark ? AppColors.blackElevated : AppColors.white;
    final overlay = showOwnerState
        ? (item.sold
              ? item.closedLabel.toUpperCase()
              : (item.isExpired ? 'EXPIRÉE' : null))
        : null;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Zone photo — occupe la hauteur restante de la carte.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.hasImages)
                      FeedNetworkImage(
                        url: item.imageUrls.first,
                        isDark: isDark,
                      )
                    else
                      ColoredBox(
                        color: accent.withValues(alpha: 0.08),
                        child: Center(
                          child: Text(
                            item.category.icon,
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Tag(label: item.typeLabel, color: accent),
                    ),
                    if (item.imageUrls.length > 1)
                      Positioned(
                        top: 8,
                        right: 40,
                        child: _PhotoCount(count: item.imageUrls.length),
                      ),
                    if (!showOwnerState)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _FavoriteButton(
                          active: isFavorite,
                          onTap: onFavorite,
                        ),
                      ),
                    if (overlay != null)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                overlay,
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Bloc texte — hauteur fixe pour un alignement net entre cartes.
              SizedBox(
                height: 96,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.priceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            color: ink.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: muted,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              item.location.isEmpty ? 'Foumbot' : item.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                color: muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeLabel,
                            style: GoogleFonts.manrope(
                              fontSize: 10.5,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Petits composants posés sur la photo
// ---------------------------------------------------------------------------

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            active ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: active ? AppColors.orangeSoft : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.white,
        ),
      ),
    );
  }
}

class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 11,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
