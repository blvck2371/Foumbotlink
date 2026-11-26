import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/home_controller.dart';
import '../../models/app_feature.dart';
import '../../models/feed_item.dart';
import '../../models/market_item.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/live_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/feed_impression.dart';
import '../../widgets/feed_skeleton.dart';
import '../../widgets/post_media.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/status_bar.dart';
import '../../widgets/post_actions_menu.dart';
import '../../widgets/repost_banner.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/weather_badge.dart';
import '../../widgets/live_ring.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    // `Obx` volontairement resserré au thème seul : la coque (Scaffold,
    // AppBar, drawer, dégradé) ne se reconstruit que sur bascule de thème.
    // Le fil et le badge de notifications ont chacun leur propre `Obx` plus
    // bas — sans ça, chaque post/like/notif reconstruisait tout l'écran.
    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          actions: [
            IconButton(
              tooltip: 'Rechercher',
              visualDensity: VisualDensity.compact,
              onPressed: () => Get.toNamed(AppRoutes.search),
              icon: Icon(Icons.search_rounded, color: ink),
            ),
            // Lives : le point rouge et le nombre disent tout de suite
            // si quelqu'un est en direct.
            IconButton(
              tooltip: 'Lives',
              visualDensity: VisualDensity.compact,
              onPressed: controller.openLives,
              icon: Obx(() {
                final count = Get.find<LiveService>().lives.length;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(
                    '$count',
                    style: GoogleFonts.manrope(
                      color: AppColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: AppColors.live,
                  child: Icon(Icons.live_tv_outlined, color: ink),
                );
              }),
            ),
            IconButton(
              tooltip: 'Notifications',
              visualDensity: VisualDensity.compact,
              onPressed: controller.openNotifications,
              icon: Obx(() {
                final unread = controller.unreadNotifications.value;
                return Badge(
                  isLabelVisible: unread > 0,
                  label: Text(
                    '$unread',
                    style: GoogleFonts.manrope(
                      color: AppColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: AppColors.orange,
                  child: Icon(Icons.notifications_outlined, color: ink),
                );
              }),
            ),
            // Thème : dans le menu latéral — la barre garde la place pour
            // la recherche sans couper le titre sur les petits écrans.
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
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  color: AppColors.orange,
                  backgroundColor: isDark
                      ? AppColors.blackElevated
                      : AppColors.white,
                  onRefresh: controller.refreshFeed,
                  child: Obx(() {
                    final items = controller.items;
                    final loading = controller.isLoading.value;
                    final loadingMore = controller.isLoadingMore.value;
                    final filter = controller.filter.value;
                    return CustomScrollView(
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
                                    color: AppColors.orange,
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
                                        onTap: () => controller.setFilter(
                                          FeedFilter.all,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _FilterChip(
                                        label: 'Population',
                                        selected:
                                            filter == FeedFilter.population,
                                        isDark: isDark,
                                        onTap: () => controller.setFilter(
                                          FeedFilter.population,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _FilterChip(
                                        label: 'Vente & Achats',
                                        selected:
                                            filter == FeedFilter.venteAchat,
                                        isDark: isDark,
                                        onTap: () => controller.setFilter(
                                          FeedFilter.venteAchat,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Barre de statuts, hors de l'en-tête pour qu'elle
                        // défile d'un bord à l'autre : enfermée dans la marge
                        // de 20 px du titre, on ne pouvait pas la faire glisser
                        // jusqu'au bord de l'écran. Réservée au fil : l'onglet
                        // « Vente & Achats » montre des annonces, pas l'humeur
                        // du jour.
                        if (!controller.isMarketMode)
                          SliverToBoxAdapter(child: StatusBar(isDark: isDark)),
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
                    );
                  }),
                ),
              ),
              // Nouvelles publications arrivées pendant la lecture : on ne
              // les glisse pas sous le doigt, on propose de les afficher.
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Obx(() {
                    final count = controller.pendingNew.length;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: count == 0 || controller.isMarketMode
                          ? const SizedBox.shrink()
                          : _NewPostsPill(
                              count: count,
                              onTap: controller.showPendingNew,
                            ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _NewPostsPill extends StatelessWidget {
  const _NewPostsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.orange,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                color: AppColors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                count == 1
                    ? 'Nouvelle publication'
                    : '$count nouvelles publications',
                style: GoogleFonts.manrope(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      // Trois cartes fantômes plutôt qu'une roue centrée : la mise en page
      // du fil est déjà là quand le contenu arrive, au lieu d'un écran
      // vide qui bascule d'un coup.
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        sliver: SliverList.separated(
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) =>
              FeedCardSkeleton(isDark: isDark, hasImage: i == 1),
        ),
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
            FeedImagePrefetch.ahead(context, [
              for (final next in items.skip(i + 1).take(3))
                ...next.imageUrls.take(4),
            ]);
            return FeedImpression(
              key: ValueKey(item.id),
              onSeen: () => controller.markSeen(item),
              onDwell: () => controller.markDwell(item),
              child: _FeedCard(
                item: item,
                isDark: isDark,
                timeLabel: controller.timeAgo(item.publishedAt),
                onOpen: () => controller.openPost(item),
                onLike: () => controller.toggleLike(item.id),
                onComment: () => controller.openPost(item),
                onRepost: () => controller.repostPost(item),
              ),
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
              ? _FeedEndCard(
                  isDark: isDark,
                  muted: muted,
                  onReshuffle: controller.reshuffleFeed,
                )
              : const SizedBox(height: 12),
        ),
      ),
    ),
  ];
}

/// Bas du fil.
///
/// Dans une commune, on a vite fait le tour des publications : un simple
/// « Fin du fil d'actualité » donne l'impression d'une app vide. On
/// propose plutôt de rebattre l'ordre — les publications déjà chargées
/// reviennent dans un autre agencement, sans une seule requête de plus.
class _FeedEndCard extends StatelessWidget {
  const _FeedEndCard({
    required this.isDark,
    required this.muted,
    required this.onReshuffle,
  });

  final bool isDark;
  final Color muted;
  final VoidCallback onReshuffle;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 28,
            color: AppColors.orange,
          ),
          const SizedBox(height: 10),
          Text(
            'Vous êtes à jour',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Vous avez vu toutes les publications récentes.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              height: 1.4,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onReshuffle,
            icon: const Icon(Icons.shuffle, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orange,
              side: BorderSide(color: AppColors.orange.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            label: const Text('Revoir le fil autrement'),
          ),
        ],
      ),
    );
  }
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
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        sliver: SliverList.separated(
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) =>
              FeedCardSkeleton(isDark: isDark, hasImage: i != 2),
        ),
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
            FeedImagePrefetch.ahead(context, [
              for (final next in items.skip(i + 1).take(3))
                ...next.imageUrls.take(1),
            ]);
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
      // Pas de mention de fin ici : sous cet onglet, les annonces sont
      // servies en une fenêtre unique (`MarketService.fetchWindow`), donc
      // `hasMore` est faux dès le premier affichage. Un « Fin des
      // annonces » collé sous trois articles laisserait croire que la
      // commune n'a rien de plus à proposer.
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28, top: 4),
        child: Center(
          child: loadingMore
              ? const FoumbotLoader()
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
                backgroundColor: AppColors.orange.withValues(alpha: 0.15),
                child: Icon(Icons.person_outline, color: AppColors.orange),
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
              Icon(Icons.add_circle, color: AppColors.orange, size: 26),
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

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.isDark,
    required this.timeLabel,
    required this.onOpen,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
  });

  final FeedItem item;
  final bool isDark;
  final String timeLabel;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final badgeColor = switch (item.type) {
      FeedType.annonce => AppColors.orange,
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
            border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
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
                    child: LiveRing(
                      uid: item.authorUid,
                      radius: 20,
                      child: UserAvatar(
                        name: item.authorName,
                        photoUrl: item.authorPhotoUrl,
                        radius: 20,
                        backgroundColor: badgeColor.withValues(alpha: 0.15),
                        foregroundColor: badgeColor,
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
                            '${item.authorSubtitle} · $timeLabel'
                            '${item.isEdited ? ' · modifié' : ''}',
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
                  _SaveButton(post: item, muted: muted),
                  PostActionsMenu(post: item, isDark: isDark),
                ],
              ),
              if (item.isRepost &&
                  item.repostOfAuthorName != null &&
                  item.repostOfAuthorName!.isNotEmpty)
                RepostBanner(
                  originalAuthorName: item.repostOfAuthorName!,
                  originalAuthorUid: item.repostOfAuthorUid,
                  originalAuthorPhotoUrl: item.repostOfAuthorPhotoUrl,
                  isDark: isDark,
                ),
              const SizedBox(height: 12),
              // Titre et message sont facultatifs l'un comme l'autre : une
              // publication peut n'être qu'une photo. On n'insère le bloc —
              // et son espacement — que s'il porte quelque chose.
              if (item.hasTitle) ...[
                Text(
                  item.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: ink,
                  ),
                ),
                if (item.hasBody) const SizedBox(height: 6),
              ],
              if (item.hasBody)
                ExpandableText(
                  text: item.body,
                  linkColor: badgeColor,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.4,
                    color: muted,
                  ),
                ),
              if (item.hasImages) ...[
                const SizedBox(height: 10),
                PostMedia(
                  imageUrls: item.imageUrls,
                  isDark: isDark,
                  // Préfixe propre au fil : l'écran de détail emploie
                  // `post_…`, sinon ouvrir une publication ferait voler
                  // ses photos d'un écran à l'autre.
                  heroPrefix: 'feed_${item.id}',
                  borderRadius: 12,
                  onLike: onLike,
                  alreadyLiked: item.likedByMe,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '${item.likesCount} J’aime · ${item.commentsCount} commentaires',
                style: GoogleFonts.manrope(fontSize: 12, color: muted),
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
                      color: item.likedByMe ? AppColors.orange : ink,
                      onTap: onLike,
                    ),
                  ),
                  Expanded(
                    child: _FeedAction(
                      icon: item.commentsDisabled
                          ? Icons.speaker_notes_off_outlined
                          : Icons.chat_bubble_outline,
                      label: item.commentsDisabled ? 'Fermés' : 'Commenter',
                      color: item.commentsDisabled
                          ? muted.withValues(alpha: 0.6)
                          : ink,
                      onTap: item.commentsDisabled ? onOpen : onComment,
                    ),
                  ),
                  Expanded(
                    child: _FeedAction(
                      icon: Icons.repeat_rounded,
                      label: 'Republier',
                      color: ink,
                      onTap: onRepost,
                    ),
                  ),
                  Expanded(
                    child: _FeedAction(
                      icon: Icons.menu_book_outlined,
                      label: 'Lire',
                      color: item.type == FeedType.annonce
                          ? AppColors.orange
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

/// Signet d'une publication. Lit l'état directement sur le contrôleur dans
/// son propre `Obx` : « enregistré » ne voyage pas dans le [FeedItem], il
/// vit dans `HomeController.savedPostIds` et doit pouvoir se rafraîchir
/// sans reconstruire toute la carte.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.post, required this.muted});

  final FeedItem post;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    return Obx(() {
      final saved = home.isSavedByMe(post.id);
      return IconButton(
        tooltip: saved ? 'Retirer des enregistrements' : 'Enregistrer',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(
          saved ? Icons.bookmark : Icons.bookmark_border,
          size: 20,
          color: saved ? AppColors.orange : muted,
        ),
        onPressed: () => home.toggleSave(post),
      );
    });
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 10,
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
    final accent = isVente ? AppColors.orange : AppColors.blue;

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
                      child: Text(
                        item.category.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
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
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        Text(
                          '${item.location} · $timeLabel',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.4,
                    color: muted,
                  ),
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
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.condition!.label,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
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
                      color: AppColors.orange,
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
                        (f) =>
                            f.section == section &&
                            f.id != AppFeatureId.notifications,
                      ),
                      ink: ink,
                      muted: muted,
                      onSelect: onSelect,
                    ),
                ],
              ),
            ),
            _SignOutButton(isDark: isDark, muted: muted),
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

/// Déconnexion, en pied de tiroir.
///
/// Elle vivait dans une icône sans libellé, coincée dans la carte du
/// compte en haut : personne ne la trouvait. En bas et nommée, elle est
/// là où l'on va la chercher — et elle disparaît pour qui n'est pas
/// connecté, où elle n'aurait aucun sens.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    final home = Get.find<HomeController>();

    return Obx(() {
      // Un compte sans profil complété doit aussi pouvoir se déconnecter.
      if (!auth.isSignedIn) {
        return const SizedBox.shrink();
      }

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(color: muted.withValues(alpha: 0.18), height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Le tiroir se referme d'abord : le laisser ouvert
                    // sur un compte qui n'existe plus donnerait à voir un
                    // menu à moitié vide le temps de la bascule.
                    Get.back();
                    home.signOut();
                  },
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  label: Text(
                    'Se déconnecter',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // « Supprimer mon compte » vit dans « Modifier mon profil » :
              // à côté de « Confidentialité », il débordait du tiroir sur
              // les écrans Android étroits.
              TextButton(
                onPressed: home.openPrivacyPolicy,
                child: Text(
                  'Confidentialité',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
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
              leading: Icon(f.icon, color: AppColors.orange),
              title: Text(
                f.title,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
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
  const _AccountSection({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

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
                  UserAvatar(
                    name: profile.displayName,
                    photoUrl: profile.photoUrl,
                    radius: 18,
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
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: muted,
                          ),
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
                ],
              )
            : InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Get.back();
                  // Connecté sans profil : l'écran s'ouvre sur le profil.
                  Get.toNamed(AppRoutes.auth);
                },
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: AppColors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        auth.isSignedIn
                            ? 'Compléter mon profil'
                            : 'Se connecter',
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
