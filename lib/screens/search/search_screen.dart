import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/search_controller.dart';
import '../../models/demarche.dart';
import '../../models/feed_item.dart';
import '../../models/live_session.dart';
import '../../models/market_item.dart';
import '../../models/search_text.dart';
import '../../models/user_profile.dart';
import '../../services/search_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/highlighted_text.dart';
import '../../widgets/live_ring.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';

/// Recherche globale : comptes, publications, annonces et lives.
class SearchScreen extends GetView<AppSearchController> {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = Get.find<ThemeController>().isDarkMode;
      final p = _Palette(isDark);
      return Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(color: p.ink),
          title: _SearchField(controller: controller, p: p),
          actions: const [SizedBox(width: 12)],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: Obx(
              () => controller.isSearching.value
                  ? const LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.orange,
                      backgroundColor: Colors.transparent,
                    )
                  : const SizedBox(height: 2),
            ),
          ),
        ),
        body: Obx(
          () => controller.hasQuery
              ? _Results(controller: controller, p: p)
              : _Suggestions(controller: controller, p: p),
        ),
      );
    });
  }
}

/// Couleurs de l'écran selon le thème.
class _Palette {
  _Palette(this.isDark);
  final bool isDark;

  Color get bg => isDark ? AppColors.black : AppColors.white;
  Color get ink => isDark ? AppColors.white : AppColors.black;
  Color get muted => isDark ? AppColors.whiteMuted : AppColors.gray;
  Color get field => isDark ? AppColors.blackElevated : AppColors.whiteSoft;
  Color get card => isDark ? AppColors.blackElevated : AppColors.white;
  Color get line => isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E6E6);

  TextStyle title({double size = 15}) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: ink,
  );
  TextStyle body({double size = 13.5}) =>
      GoogleFonts.manrope(fontSize: size, color: muted, height: 1.35);
  TextStyle hl(TextStyle base) =>
      base.copyWith(color: AppColors.orange, fontWeight: FontWeight.w800);
  TextStyle section() => GoogleFonts.spaceGrotesk(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: ink,
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.p});

  final AppSearchController controller;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search_rounded, color: p.muted, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller.textController,
              focusNode: controller.focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: controller.submit,
              style: GoogleFonts.manrope(fontSize: 15.5, color: p.ink),
              cursorColor: AppColors.orange,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Personnes, annonces, démarches, lives…',
                hintStyle: GoogleFonts.manrope(fontSize: 15, color: p.muted),
              ),
            ),
          ),
          Obx(
            () => controller.query.value.isEmpty
                ? const SizedBox(width: 12)
                : IconButton(
                    tooltip: 'Effacer',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.clear,
                    icon: Icon(Icons.cancel_rounded, color: p.muted, size: 20),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sans saisie : historique, lives en cours, comptes populaires
// ---------------------------------------------------------------------------

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.controller, required this.p});

  final AppSearchController controller;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final recent = controller.recent.toList();
      final lives = controller.currentLives;
      final popular = controller.popular.toList();
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (recent.isNotEmpty) ...[
            _SectionHeader(
              title: 'Recherches récentes',
              p: p,
              action: 'Tout effacer',
              onAction: controller.clearRecent,
            ),
            for (final q in recent)
              ListTile(
                dense: true,
                leading: Icon(Icons.history_rounded, color: p.muted),
                title: Text(q, style: p.title(size: 15)),
                trailing: IconButton(
                  tooltip: 'Retirer',
                  icon: Icon(Icons.close_rounded, color: p.muted, size: 20),
                  onPressed: () => controller.forget(q),
                ),
                onTap: () => controller.useRecent(q),
              ),
          ],
          if (lives.isNotEmpty) ...[
            _SectionHeader(title: 'En direct maintenant', p: p),
            _LiveStrip(lives: lives, tokens: const [], c: controller, p: p),
          ],
          if (popular.isNotEmpty) ...[
            _SectionHeader(title: 'Comptes populaires', p: p),
            for (final u in popular)
              _UserTile(user: u, tokens: const [], c: controller, p: p),
          ],
          if (recent.isEmpty && lives.isEmpty && popular.isEmpty)
            _Hint(
              icon: Icons.travel_explore_rounded,
              title: 'Rechercher dans Foumbot',
              text:
                  'Trouvez des habitants, des publications, des annonces '
                  'de vente ou d’achat et les lives en cours.',
              p: p,
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Résultats
// ---------------------------------------------------------------------------

class _Results extends StatelessWidget {
  const _Results({required this.controller, required this.p});

  final AppSearchController controller;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final r = controller.results.value;
      final tokens = searchQueryTokens(controller.query.value);
      final tab = controller.tab.value;
      // Rien encore pour cette saisie (première requête en vol) : on ne
      // montre pas « aucun résultat » trop tôt.
      final waiting = controller.isSearching.value && r.isEmpty;

      return Column(
        children: [
          _Tabs(results: r, current: tab, c: controller, p: p),
          Divider(height: 1, color: p.line),
          Expanded(
            child: waiting
                ? const SizedBox.shrink()
                : r.isEmpty && !controller.isSearching.value
                ? _Hint(
                    icon: Icons.search_off_rounded,
                    title:
                        'Aucun résultat pour « ${controller.query.value.trim()} »',
                    text:
                        'Vérifiez l’orthographe, essayez un autre mot ou '
                        'seulement le début d’un nom.',
                    p: p,
                  )
                : _tabBody(tab, r, tokens),
          ),
        ],
      );
    });
  }

  Widget _tabBody(SearchTab tab, SearchResults r, List<String> tokens) {
    final c = controller;
    Widget list(List<Widget> children, String emptyText) => children.isEmpty
        ? _Hint(
            icon: Icons.inbox_outlined,
            title: emptyText,
            text: 'Essayez l’onglet « Top » ou un autre mot.',
            p: p,
          )
        : ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: children,
          );

    switch (tab) {
      case SearchTab.accounts:
        return list([
          for (final u in r.users)
            _UserTile(user: u, tokens: tokens, c: c, p: p),
        ], 'Aucun compte');
      case SearchTab.posts:
        return list([
          for (final post in r.posts)
            _PostTile(post: post, tokens: tokens, c: c, p: p),
        ], 'Aucune publication');
      case SearchTab.listings:
        return list([
          for (final item in r.listings)
            _ListingTile(item: item, tokens: tokens, c: c, p: p),
        ], 'Aucune annonce');
      case SearchTab.demarches:
        return list([
          for (final d in r.demarches)
            _DemarcheTile(demarche: d, tokens: tokens, c: c, p: p),
        ], 'Aucune démarche');
      case SearchTab.lives:
        return r.lives.isEmpty
            ? _Hint(
                icon: Icons.live_tv_outlined,
                title: 'Aucun live correspondant',
                text: 'Seuls les lives en cours apparaissent ici.',
                p: p,
              )
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: r.lives.length,
                itemBuilder: (_, i) =>
                    _LiveCard(live: r.lives[i], tokens: tokens, c: c, p: p),
              );
      case SearchTab.top:
        return list([
          if (r.lives.isNotEmpty) ...[
            _SectionHeader(title: 'En direct', p: p),
            _LiveStrip(lives: r.lives, tokens: tokens, c: c, p: p),
          ],
          // Une démarche qui correspond est presque toujours ce que l'on
          // cherche (« passeport », « acte de naissance ») : en tête.
          if (r.demarches.isNotEmpty) ...[
            _SectionHeader(
              title: 'Démarches',
              p: p,
              action: r.demarches.length > 2 ? 'Voir tout' : null,
              onAction: () => c.tab.value = SearchTab.demarches,
            ),
            for (final d in r.demarches.take(2))
              _DemarcheTile(demarche: d, tokens: tokens, c: c, p: p),
          ],
          if (r.users.isNotEmpty) ...[
            _SectionHeader(
              title: 'Comptes',
              p: p,
              action: r.users.length > 3 ? 'Voir tout' : null,
              onAction: () => c.tab.value = SearchTab.accounts,
            ),
            for (final u in r.users.take(3))
              _UserTile(user: u, tokens: tokens, c: c, p: p),
          ],
          if (r.posts.isNotEmpty) ...[
            _SectionHeader(
              title: 'Publications',
              p: p,
              action: r.posts.length > 3 ? 'Voir tout' : null,
              onAction: () => c.tab.value = SearchTab.posts,
            ),
            for (final post in r.posts.take(3))
              _PostTile(post: post, tokens: tokens, c: c, p: p),
          ],
          if (r.listings.isNotEmpty) ...[
            _SectionHeader(
              title: 'Ventes & achats',
              p: p,
              action: r.listings.length > 3 ? 'Voir tout' : null,
              onAction: () => c.tab.value = SearchTab.listings,
            ),
            for (final item in r.listings.take(3))
              _ListingTile(item: item, tokens: tokens, c: c, p: p),
          ],
        ], 'Aucun résultat');
    }
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.results,
    required this.current,
    required this.c,
    required this.p,
  });

  final SearchResults results;
  final SearchTab current;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final entries = [
      (SearchTab.top, 'Top', 0),
      (SearchTab.accounts, 'Comptes', results.users.length),
      (SearchTab.posts, 'Publications', results.posts.length),
      (SearchTab.listings, 'Annonces', results.listings.length),
      (SearchTab.demarches, 'Démarches', results.demarches.length),
      (SearchTab.lives, 'Lives', results.lives.length),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final (tab, label, count) in entries)
            _TabChip(
              label: count > 0 ? '$label · $count' : label,
              selected: tab == current,
              onTap: () => c.tab.value = tab,
              p: p,
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.p,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.orange : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? p.ink : p.muted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Éléments
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.p,
    this.action,
    this.onAction,
  });

  final String title;
  final _Palette p;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: p.section())),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: GoogleFonts.manrope(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.title,
    required this.text,
    required this.p,
  });

  final IconData icon;
  final String title;
  final String text;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 44, color: p.muted),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: p.title(size: 16.5)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: p.body(size: 14)),
        ],
      ),
    );
  }
}

String _count(int n, String one, String many) {
  if (n >= 1000) {
    final k = (n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1);
    return '${k.replaceAll('.', ',')} k $many';
  }
  return '$n ${n > 1 ? many : one}';
}

String _ago(DateTime d) => Get.isRegistered<HomeController>()
    ? Get.find<HomeController>().timeAgo(d)
    : '';

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final UserProfile user;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final name = p.title();
    return InkWell(
      onTap: () => c.openUser(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            LiveRing(
              uid: user.uid,
              radius: 24,
              child: UserAvatar(
                name: user.displayName,
                photoUrl: user.photoUrl,
                radius: 24,
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
                        child: HighlightedText(
                          user.displayName,
                          tokens: tokens,
                          style: name,
                          highlight: p.hl(name),
                        ),
                      ),
                      if (user.verified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${user.authorSubtitle} · '
                    '${_count(user.followersCount, 'abonné', 'abonnés')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.body(),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final FeedItem post;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final title = p.title();
    final body = p.body();
    final heading = post.title.trim().isNotEmpty ? post.title : post.body;
    final excerpt = post.title.trim().isNotEmpty ? post.body : '';
    return InkWell(
      onTap: () => c.openPost(post),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        name: post.authorName,
                        photoUrl: post.authorPhotoUrl,
                        radius: 10,
                        fontSize: 9,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: HighlightedText(
                          post.authorName,
                          tokens: tokens,
                          style: p.body(size: 13),
                          highlight: p.hl(p.body(size: 13)),
                        ),
                      ),
                      Text(
                        ' · ${_ago(post.publishedAt)}',
                        style: p.body(size: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  HighlightedText(
                    heading.replaceAll('\n', ' '),
                    tokens: tokens,
                    style: title,
                    highlight: p.hl(title),
                    maxLines: 2,
                  ),
                  if (excerpt.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    HighlightedText(
                      excerpt.replaceAll('\n', ' '),
                      tokens: tokens,
                      style: body,
                      highlight: p.hl(body),
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    '${_count(post.likesCount, 'j’aime', 'j’aime')} · '
                    '${_count(post.commentsCount, 'commentaire', 'commentaires')}',
                    style: p.body(size: 12.5),
                  ),
                ],
              ),
            ),
            if (post.hasImages) ...[
              const SizedBox(width: 12),
              _Thumb(url: post.imageUrls.first, p: p, size: 76),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingTile extends StatelessWidget {
  const _ListingTile({
    required this.item,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final MarketItem item;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final title = p.title();
    return InkWell(
      onTap: () => c.openListing(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            item.imageUrls.isEmpty
                ? Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: p.field,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storefront_outlined, color: p.muted),
                  )
                : _Thumb(url: item.imageUrls.first, p: p, size: 76),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    item.title,
                    tokens: tokens,
                    style: title,
                    highlight: p.hl(title),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.priceLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(height: 3),
                  HighlightedText(
                    [
                      if (item.location.trim().isNotEmpty) item.location,
                      _ago(item.bumpedAt),
                    ].join(' · '),
                    tokens: tokens,
                    style: p.body(size: 12.5),
                    highlight: p.hl(p.body(size: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemarcheTile extends StatelessWidget {
  const _DemarcheTile({
    required this.demarche,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final Demarche demarche;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final title = p.title();
    return InkWell(
      onTap: () => c.openDemarche(demarche),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                demarche.category.icon,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    demarche.title,
                    tokens: tokens,
                    style: title,
                    highlight: p.hl(title),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${demarche.structureName} · ${demarche.category.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.body(size: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.p, required this.size});

  final String url;
  final _Palette p;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: FeedNetworkImage(url: url, isDark: p.isDark, decodeWidth: 240),
      ),
    );
  }
}

class _LiveStrip extends StatelessWidget {
  const _LiveStrip({
    required this.lives,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final List<LiveSession> lives;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: lives.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(
          width: 132,
          child: _LiveCard(live: lives[i], tokens: tokens, c: c, p: p),
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.live,
    required this.tokens,
    required this.c,
    required this.p,
  });

  final LiveSession live;
  final List<String> tokens;
  final AppSearchController c;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: AppColors.white);
    final name = GoogleFonts.manrope(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
    ).merge(white);
    return GestureDetector(
      onTap: () => c.openLive(live),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            live.hostPhoto == null || live.hostPhoto!.isEmpty
                ? ColoredBox(
                    color: p.field,
                    child: Center(
                      child: UserAvatar(name: live.hostName, radius: 30),
                    ),
                  )
                : FeedNetworkImage(
                    url: live.hostPhoto!,
                    isDark: p.isDark,
                    decodeWidth: 360,
                  ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.live,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    color: AppColors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${live.viewers}',
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ).merge(white),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedText(
                    live.hostName,
                    tokens: tokens,
                    style: name,
                    highlight: name.copyWith(color: AppColors.orangeSoft),
                  ),
                  if (live.title.trim().isNotEmpty)
                    HighlightedText(
                      live.title,
                      tokens: tokens,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                      ).merge(const TextStyle(color: Color(0xDDFFFFFF))),
                      highlight: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.orangeSoft,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lazy : le service et le contrôleur ne naissent qu'à la première
/// ouverture de la recherche.
class SearchBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SearchService>()) {
      Get.put(SearchService(), permanent: true);
    }
    Get.lazyPut(AppSearchController.new);
  }
}
