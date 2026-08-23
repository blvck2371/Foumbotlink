import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/home_controller.dart';
import '../../models/app_feature.dart';
import '../../models/feed_item.dart';
import '../../models/market_item.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/weather_badge.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final unread = controller.unreadNotifications.value;
      final items = controller.items;
      final loading = controller.isLoading.value;
      final loadingMore = controller.isLoadingMore.value;
      final filter = controller.filter.value;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: controller.openNotifications,
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(
                  '$unread',
                  style: GoogleFonts.manrope(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: AppColors.red,
                child: Icon(Icons.notifications_outlined, color: ink),
              ),
            ),
            IconButton(
              tooltip: 'Thème',
              onPressed: controller.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.red,
              ),
            ),
            WeatherBadge(isDark: isDark),
          ],
        ),
        drawer: _HomeDrawer(
          isDark: isDark,
          ink: ink,
          muted: muted,
          features: controller.features,
          onSelect: controller.openFeature,
          onToggleTheme: controller.toggleTheme,
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
            color: AppColors.red,
            backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
            onRefresh: controller.refreshFeed,
            child: CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
                        const SizedBox(height: 8),
                        Text(
                          'Fil d’actualité',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Infos, annonces et publications des habitants — likez et commentez.',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            height: 1.45,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ComposerEntry(
                          isDark: isDark,
                          onTap: controller.openCompose,
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'Tout',
                                selected: filter == FeedFilter.all,
                                isDark: isDark,
                                onTap: () =>
                                    controller.setFilter(FeedFilter.all),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Infos',
                                selected: filter == FeedFilter.infos,
                                isDark: isDark,
                                onTap: () =>
                                    controller.setFilter(FeedFilter.infos),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Annonces',
                                selected: filter == FeedFilter.annonces,
                                isDark: isDark,
                                onTap: () =>
                                    controller.setFilter(FeedFilter.annonces),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Population',
                                selected: filter == FeedFilter.population,
                                isDark: isDark,
                                onTap: () => controller
                                    .setFilter(FeedFilter.population),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Vente & Achats',
                                selected: filter == FeedFilter.venteAchat,
                                isDark: isDark,
                                onTap: () => controller
                                    .setFilter(FeedFilter.venteAchat),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.isMarketMode) ...[
                  ..._buildMarketSliver(
                    controller: controller,
                    isDark: isDark,
                    muted: muted,
                    loading: loading,
                    loadingMore: loadingMore,
                  ),
                ] else ...[
                  ..._buildFeedSliver(
                    controller: controller,
                    items: items,
                    isDark: isDark,
                    muted: muted,
                    loading: loading,
                    loadingMore: loadingMore,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

List<Widget> _buildFeedSliver({
  required HomeController controller,
  required RxList<FeedItem> items,
  required bool isDark,
  required Color muted,
  required bool loading,
  required bool loadingMore,
}) {
  return [
    if (loading && items.isEmpty)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: FoumbotLoader()),
      )
    else if (!loading && items.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'Aucune publication pour le moment.',
            style: GoogleFonts.manrope(fontSize: 16, color: muted),
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
            return _FeedCard(
              item: item,
              isDark: isDark,
              timeLabel: controller.timeAgo(item.publishedAt),
              onOpen: () => controller.openPost(item),
              onLike: () => controller.toggleLike(item.id),
              onComment: () => controller.openPost(item),
            );
          },
        ),
      ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28, top: 4),
        child: Center(
          child: loadingMore
              ? const FoumbotLoader()
              : (!controller.hasMore.value && items.isNotEmpty)
                  ? Text(
                      'Fin du fil d’actualité',
                      style: GoogleFonts.manrope(fontSize: 13, color: muted),
                    )
                  : const SizedBox(height: 12),
        ),
      ),
    ),
  ];
}

List<Widget> _buildMarketSliver({
  required HomeController controller,
  required bool isDark,
  required Color muted,
  required bool loading,
  required bool loadingMore,
}) {
  final items = controller.marketItems;
  return [
    if (loading && items.isEmpty)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: FoumbotLoader()),
      )
    else if (!loading && items.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: muted),
              const SizedBox(height: 14),
              Text(
                'Aucune annonce pour le moment.',
                style: GoogleFonts.manrope(fontSize: 16, color: muted),
              ),
            ],
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
            return _MarketFeedCard(
              item: item,
              isDark: isDark,
              timeLabel: controller.timeAgo(item.createdAt),
              onTap: () => controller.openMarketItem(item),
            );
          },
        ),
      ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28, top: 4),
        child: Center(
          child: loadingMore
              ? const FoumbotLoader()
              : (!controller.hasMore.value && items.isNotEmpty)
                  ? Text(
                      'Fin des annonces',
                      style: GoogleFonts.manrope(fontSize: 13, color: muted),
                    )
                  : const SizedBox(height: 12),
        ),
      ),
    ),
  ];
}

/// Point d'entrée pour publier, façon "Quoi de neuf ?" de Facebook — en
/// haut du fil, avant les filtres.
class _ComposerEntry extends StatelessWidget {
  const _ComposerEntry({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: muted.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.red.withValues(alpha: 0.15),
                child: Icon(Icons.person_outline, color: AppColors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.blackSoft : AppColors.whiteSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Quoi de neuf à Foumbot ?',
                    style: GoogleFonts.manrope(fontSize: 14, color: muted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.add_circle, color: AppColors.red, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
              color: selected
                  ? AppColors.red
                  : ink.withValues(alpha: 0.25),
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

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.onOpen,
    required this.onLike,
    required this.onComment,
  });

  final FeedItem item;
  final bool isDark;
  final String timeLabel;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final badgeColor = switch (item.type) {
      FeedType.annonce => AppColors.red,
      FeedType.info => AppColors.blue,
      FeedType.post => AppColors.blue,
    };

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: item.authorUid.isEmpty
                        ? null
                        : () => Get.toNamed(
                              AppRoutes.userProfile,
                              arguments: item.authorUid,
                              preventDuplicates: false,
                            ),
                    behavior: HitTestBehavior.opaque,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: badgeColor.withValues(alpha: 0.15),
                      child: Text(
                        item.authorName.isNotEmpty
                            ? item.authorName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: item.authorUid.isEmpty
                          ? null
                          : () => Get.toNamed(
                                AppRoutes.userProfile,
                                arguments: item.authorUid,
                                preventDuplicates: false,
                              ),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.authorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                              ),
                              if (item.authorVerified) ...[
                                const SizedBox(width: 5),
                                const VerifiedBadge.small(),
                              ],
                            ],
                          ),
                          Text(
                            '${item.authorSubtitle} · $timeLabel',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.typeLabel.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.4,
                  color: muted,
                ),
              ),
              if (item.hasImages) ...[
                const SizedBox(height: 10),
                FeedImageCarousel(
                  imageUrls: item.imageUrls,
                  isDark: isDark,
                  borderRadius: 12,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '${item.likesCount} J’aime · ${item.commentsCount} commentaires',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: muted,
                ),
              ),
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _FeedAction(
                      icon: item.likedByMe
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: 'J’aime',
                      color: item.likedByMe
                          ? AppColors.red
                          : ink,
                      onTap: onLike,
                    ),
                  ),
                  Expanded(
                    child: _FeedAction(
                      icon: Icons.chat_bubble_outline,
                      label: 'Commenter',
                      color: ink,
                      onTap: onComment,
                    ),
                  ),
                  Expanded(
                    child: _FeedAction(
                      icon: Icons.menu_book_outlined,
                      label: 'Lire',
                      color: item.type == FeedType.annonce
                          ? AppColors.red
                          : AppColors.blue,
                      onTap: onOpen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedAction extends StatelessWidget {
  const _FeedAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketFeedCard extends StatelessWidget {
  const _MarketFeedCard({
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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(item.category.icon,
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.sellerName,
                          style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800, color: ink),
                        ),
                        Text(
                          '${item.location} · $timeLabel',
                          style: GoogleFonts.manrope(
                              fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.typeLabel.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                const SizedBox(height: 6),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.manrope(fontSize: 14, height: 1.4, color: muted),
                ),
              ],
              if (item.hasImages) ...[
                const SizedBox(height: 10),
                FeedImageCarousel(
                  imageUrls: item.imageUrls,
                  isDark: isDark,
                  borderRadius: 12,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    item.priceLabel,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  if (item.negotiable) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Négociable',
                      style: GoogleFonts.manrope(fontSize: 12, color: muted),
                    ),
                  ],
                  if (item.condition != null) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.condition!.label,
                        style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: muted),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.features,
    required this.onSelect,
    required this.onToggleTheme,
  });

  final bool isDark;
  final Color ink;
  final Color muted;
  final List<AppFeature> features;
  final ValueChanged<AppFeature> onSelect;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: isDark ? AppColors.blackSoft : AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Foumbot',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Thème',
                    onPressed: onToggleTheme,
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _AccountSection(isDark: isDark, ink: ink, muted: muted),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  for (final section in AppFeatureSection.values)
                    _DrawerSection(
                      title: _sectionTitles[section]!,
                      // Les notifications ont déjà leur propre icône dans
                      // l'AppBar — pas besoin de les dupliquer ici.
                      features: features.where(
                        (f) => f.section == section && f.id != AppFeatureId.notifications,
                      ),
                      ink: ink,
                      muted: muted,
                      onSelect: onSelect,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _sectionTitles = {
    AppFeatureSection.community: 'Fil & communauté',
    AppFeatureSection.municipalServices: 'Services municipaux',
    AppFeatureSection.account: 'Votre compte',
  };
}

/// Un groupe du tiroir : en-tête + ses modules — rend la hiérarchie du
/// menu explicite au lieu d'une liste plate mélangeant fil, services
/// municipaux et compte.
class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.title,
    required this.features,
    required this.ink,
    required this.muted,
    required this.onSelect,
  });

  final String title;
  final Iterable<AppFeature> features;
  final Color ink;
  final Color muted;
  final ValueChanged<AppFeature> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = features.toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: muted,
              ),
            ),
          ),
          for (final f in items)
            ListTile(
              leading: Icon(f.icon, color: AppColors.red),
              title: Text(
                f.title,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: ink),
              ),
              subtitle: Text(
                f.subtitle,
                style: GoogleFonts.manrope(fontSize: 12, color: muted),
              ),
              onTap: () {
                Get.back();
                onSelect(f);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Identité connectée (nom, type de compte) + déconnexion, ou invitation
/// à se connecter si aucune session active.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    final profiles = Get.find<UserProfileService>();

    return Obx(() {
      final profile = profiles.profile.value;
      final signedIn = auth.isSignedIn && profile != null;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: signedIn
            ? Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.red.withValues(alpha: 0.15),
                    child: Text(
                      profile.displayName.isNotEmpty
                          ? profile.displayName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        Text(
                          profile.authorSubtitle,
                          style: GoogleFonts.manrope(fontSize: 12, color: muted),
                        ),
                        if (!profile.canPublish) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.hourglass_top_rounded,
                                size: 11,
                                color: AppColors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'En attente de validation',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Se déconnecter',
                    onPressed: () {
                      Get.back();
                      Get.find<HomeController>().signOut();
                    },
                    icon: Icon(Icons.logout_rounded, color: muted),
                  ),
                ],
              )
            : InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Get.back();
                  Get.toNamed(AppRoutes.auth);
                },
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: AppColors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Se connecter',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: muted),
                  ],
                ),
              ),
      );
    });
  }
}
