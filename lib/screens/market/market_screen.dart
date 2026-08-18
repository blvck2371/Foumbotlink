import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/market_controller.dart';
import '../../models/market_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

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
      final loadingMore = controller.isLoadingMore.value;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: 'Vente & Achat',
          actions: [
            IconButton(
              tooltip: 'Thème',
              onPressed: themeController.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: controller.openCreateListing,
          backgroundColor: AppColors.red,
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
                  : const [AppColors.white, AppColors.whiteSoft, AppColors.white],
            ),
          ),
          child: RefreshIndicator(
            color: AppColors.red,
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
                            color: AppColors.red,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Marché local',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vendez, achetez et proposez vos services entre habitants.',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SearchBar(isDark: isDark, ink: ink, muted: muted),
                        const SizedBox(height: 14),
                        _TypeFilter(isDark: isDark),
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
                    child: Center(
                      child: FoumbotLoader(),
                    ),
                  )
                else if (!loading && items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_outlined,
                                size: 48, color: muted),
                            const SizedBox(height: 14),
                            Text(
                              'Aucune annonce trouvée.',
                              style:
                                  GoogleFonts.manrope(fontSize: 16, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return _MarketCard(
                          item: item,
                          isDark: isDark,
                          timeLabel: controller.timeAgo(item.createdAt),
                          onTap: () => controller.openListing(item),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80, top: 4),
                    child: Center(
                      child: loadingMore
                          ? const FoumbotLoader()
                          : (!controller.hasMore.value && items.isNotEmpty)
                              ? Text(
                                  'Fin des annonces',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13, color: muted),
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
              onSubmitted: controller.search,
              decoration: InputDecoration(
                hintText: 'Moto, terrain, maison, service…',
                hintStyle: GoogleFonts.manrope(color: muted),
                border: InputBorder.none,
              ),
            ),
          ),
          Obx(() => controller.searchQuery.value.isNotEmpty
              ? GestureDetector(
                  onTap: controller.clearSearch,
                  child: Icon(Icons.close, size: 18, color: muted),
                )
              : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filtres type (Tout / Ventes / Recherches)
// ---------------------------------------------------------------------------

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketController>();
    return Obx(() {
      final selected = controller.selectedType.value;
      return Row(
        children: [
          _Chip(
            label: 'Tout',
            selected: selected == null,
            isDark: isDark,
            onTap: () => controller.setType(null),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Ventes',
            selected: selected == MarketListingType.vente,
            isDark: isDark,
            onTap: () => controller.setType(MarketListingType.vente),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Recherches',
            selected: selected == MarketListingType.achat,
            isDark: isDark,
            onTap: () => controller.setType(MarketListingType.achat),
          ),
        ],
      );
    });
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
      final selected = controller.selectedCategory.value;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
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
      color: selected ? AppColors.red : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.red : ink.withValues(alpha: 0.25),
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
// Card adaptative : texte seul, image + texte, image seule
// ---------------------------------------------------------------------------

class _MarketCard extends StatelessWidget {
  const _MarketCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.onTap,
  });

  final MarketItem item;
  final bool isDark;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (item.isTextOnly) {
      return _TextOnlyCard(
          item: item, isDark: isDark, timeLabel: timeLabel, onTap: onTap);
    }
    return _ImageCard(
        item: item, isDark: isDark, timeLabel: timeLabel, onTap: onTap);
  }
}

/// Card sans photo : emoji catégorie en grand à gauche, texte à droite.
class _TextOnlyCard extends StatelessWidget {
  const _TextOnlyCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.onTap,
  });

  final MarketItem item;
  final bool isDark;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final isVente = item.listingType == MarketListingType.vente;
    final accent = isVente ? AppColors.red : AppColors.blue;

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    item.category.icon,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeBadge(label: item.typeLabel, color: accent),
                        const SizedBox(width: 6),
                        if (item.condition != null) ...[
                          _ConditionBadge(
                              label: item.condition!.label, isDark: isDark),
                          const SizedBox(width: 6),
                        ],
                        const Spacer(),
                        Text(timeLabel,
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: muted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: ink,
                      ),
                    ),
                    if (item.hasDescription) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.35,
                          color: muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _PriceRow(item: item, accent: accent, muted: muted),
                    const SizedBox(height: 6),
                    _SellerRow(item: item, ink: ink, muted: muted),
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

/// Card avec photo(s) : grande image en haut, contenu en dessous.
class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.onTap,
  });

  final MarketItem item;
  final bool isDark;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final isVente = item.listingType == MarketListingType.vente;
    final accent = isVente ? AppColors.red : AppColors.blue;

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section image
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: item.imageUrls.length == 1 ? 16 / 10 : 4 / 3,
                      child: item.imageUrls.length == 1
                          ? FeedNetworkImage(
                              url: item.imageUrls.first, isDark: isDark)
                          : _MiniGallery(
                              urls: item.imageUrls, isDark: isDark),
                    ),
                    // Badges sur la photo
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Row(
                        children: [
                          _TypeBadgeSolid(
                              label: item.typeLabel, color: accent),
                          if (item.condition != null) ...[
                            const SizedBox(width: 6),
                            _TypeBadgeSolid(
                              label: item.condition!.label,
                              color: Colors.black87,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Prix sur la photo
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.priceLabel,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                    // Nombre de photos
                    if (item.imageUrls.length > 1)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_outlined,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                '${item.imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Section texte
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.category.icon,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.category.label,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                        if (item.negotiable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Négociable',
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(timeLabel,
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: muted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: ink,
                      ),
                    ),
                    if (item.hasDescription) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.35,
                          color: muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _SellerRow(item: item, ink: ink, muted: muted),
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

// ---------------------------------------------------------------------------
// Mini galerie de preview (montre la première photo, indicateur de nombre)
// ---------------------------------------------------------------------------

class _MiniGallery extends StatefulWidget {
  const _MiniGallery({required this.urls, required this.isDark});

  final List<String> urls;
  final bool isDark;

  @override
  State<_MiniGallery> createState() => _MiniGalleryState();
}

class _MiniGalleryState extends State<_MiniGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, i) =>
              FeedNetworkImage(url: widget.urls[i], isDark: widget.isDark),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.urls.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: i == _page ? 14 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Petits composants réutilisés dans les cards
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

class _TypeBadgeSolid extends StatelessWidget {
  const _TypeBadgeSolid({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: ink.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.item,
    required this.accent,
    required this.muted,
  });

  final MarketItem item;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          item.priceLabel,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        if (item.negotiable) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Négociable',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SellerRow extends StatelessWidget {
  const _SellerRow({
    required this.item,
    required this.ink,
    required this.muted,
  });

  final MarketItem item;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: AppColors.red.withValues(alpha: 0.12),
          child: Text(
            item.sellerName.isNotEmpty
                ? item.sellerName[0].toUpperCase()
                : '?',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            item.sellerName,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.location_on_outlined, size: 13, color: muted),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            item.location,
            style: GoogleFonts.manrope(fontSize: 12, color: muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
