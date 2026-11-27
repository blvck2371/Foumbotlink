import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/market_controller.dart';
import '../../models/market_item.dart';
import '../../models/seller_review.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/market_service.dart';
import '../../services/seller_review_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/market_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/safety_notice.dart';
import 'seller_review_sheet.dart';
import '../../utils/image_url.dart';

class MarketDetailScreen extends StatefulWidget {
  const MarketDetailScreen({super.key});

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  final _market = Get.find<MarketService>();
  final _reviews = Get.find<SellerReviewService>();
  final _auth = Get.find<AuthService>();

  // L'écran de détail peut être ouvert depuis le Marché (contrôleur déjà
  // présent) comme depuis l'accueil (pas encore) — on réutilise l'instance
  // existante ou on en crée une, pour que les actions vendeur/acheteur
  // soient toujours disponibles.
  final MarketController _marketCtrl = Get.isRegistered<MarketController>()
      ? Get.find<MarketController>()
      : Get.put(MarketController());

  late String _itemId;
  MarketItem? _item;
  bool _loading = true;

  SellerReputation _reputation = const SellerReputation();
  List<SellerReview> _sellerReviews = const [];
  bool _canReview = false;

  /// Les autres annonces en vente du même vendeur. Chargées après la
  /// fiche, jamais avant : c'est un complément, il ne doit pas retarder
  /// ce que la personne est venue voir.
  List<MarketItem> _otherListings = const [];

  /// Annonces proches, chez d'autres vendeurs. Classées par
  /// [marketSimilarityScore].
  List<MarketItem> _similar = const [];

  @override
  void initState() {
    super.initState();
    _itemId = Get.arguments as String;
    _loadItem();
  }

  Future<void> _loadItem() async {
    final idx = _marketCtrl.items.indexWhere((e) => e.id == _itemId);
    if (idx >= 0) {
      if (mounted) {
        setState(() {
          _item = _marketCtrl.items[idx];
          _loading = false;
        });
      }
    } else {
      final fetched = await _market.getById(_itemId);
      if (!mounted) return;
      setState(() {
        _item = fetched;
        _loading = false;
      });
    }

    final item = _item;
    if (item == null) return;

    // Vue comptée une fois par ouverture, et jamais pour son propre
    // article : le compteur sert au vendeur à jauger l'intérêt réel, pas
    // à compter ses propres passages.
    if (!_marketCtrl.isMine(item)) {
      unawaited(_market.incrementViews(item.id));
    }
    await _loadSeller(item);
  }

  Future<void> _loadSeller(MarketItem item) async {
    final reputation = await _reviews.reputation(item.sellerUid);
    final list = await _reviews.fetch(item.sellerUid, limit: 3);
    final canReview = _auth.isSignedIn
        ? await _reviews.canReview(sellerUid: item.sellerUid, myUid: _auth.uid)
        : false;
    if (!mounted) return;
    setState(() {
      _reputation = reputation;
      _sellerReviews = list;
      _canReview = canReview;
    });

    // Les deux bandes en parallèle : ce sont deux requêtes
    // indépendantes, les enchaîner doublerait l'attente pour rien.
    final (others, similar) = await (
      _market.otherListingsBySeller(
        sellerUid: item.sellerUid,
        excludeId: item.id,
      ),
      _market.similarListings(to: item),
    ).wait;

    if (!mounted) return;
    setState(() {
      _otherListings = others;
      _similar = similar;
    });
  }

  Future<void> _onToggleSold(MarketItem item) async {
    final updated = await _marketCtrl.toggleSold(item);
    if (mounted) setState(() => _item = updated);
  }

  Future<void> _onRenew(MarketItem item) async {
    final updated = await _marketCtrl.renewListing(item);
    if (mounted) setState(() => _item = updated);
  }

  Future<void> _onEdit(MarketItem item) async {
    final updated = await _marketCtrl.openEditListing(item);
    if (updated != null && mounted) setState(() => _item = updated);
  }

  Future<void> _onDelete(MarketItem item) async {
    final deleted = await _marketCtrl.confirmDelete(item);
    if (deleted && mounted) Get.back();
  }

  Future<void> _onReview(MarketItem item) async {
    final published = await showSellerReviewSheet(
      sellerUid: item.sellerUid,
      sellerName: item.sellerName,
      item: item,
    );
    if (published) await _loadSeller(item);
  }

  Future<void> _onRevealPhone(MarketItem item) async {
    await _marketCtrl.revealPhone(item);
    if (mounted) setState(() {});
  }

  Future<void> _onOffer(MarketItem item) async {
    final amount = await _showOfferDialog(item);
    if (amount != null && amount > 0) {
      await _marketCtrl.offerSeller(item, amount);
    }
  }

  Future<int?> _showOfferDialog(MarketItem item) {
    final ctrl = TextEditingController();
    return Get.dialog<int>(
      AlertDialog(
        title: const Text('Faire une offre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Annonce affichée à ${item.priceLabel}. Votre proposition sera '
              'envoyée au vendeur dans la messagerie.',
              style: GoogleFonts.manrope(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                suffixText: 'FCFA',
                hintText: 'Votre prix',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                final v =
                    int.tryParse(ctrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
                Get.back(result: v > 0 ? v : null);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v =
                  int.tryParse(ctrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
              Get.back(result: v > 0 ? v : null);
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      if (_loading) {
        return Scaffold(
          backgroundColor: isDark ? AppColors.black : AppColors.white,
          appBar: FoumbotAppBar(isDark: isDark, title: 'Détail'),
          body: const Center(child: FoumbotLoader()),
        );
      }

      final item = _item;
      if (item == null) {
        return Scaffold(
          backgroundColor: isDark ? AppColors.black : AppColors.white,
          appBar: FoumbotAppBar(isDark: isDark, title: 'Détail'),
          body: Center(
            child: Text(
              'Annonce introuvable',
              style: GoogleFonts.manrope(color: muted),
            ),
          ),
        );
      }

      final accent = marketTypeColor(item.listingType);
      final mine = _marketCtrl.isMine(item);
      final phone = _marketCtrl.revealedPhones[item.id];

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: 'Détail',
          actions: [
            if (!mine)
              IconButton(
                tooltip: 'Mettre de côté',
                icon: Icon(
                  _marketCtrl.isFavorite(item.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: AppColors.orange,
                ),
                onPressed: () async {
                  await _marketCtrl.toggleFavorite(item);
                  if (mounted) setState(() {});
                },
              ),
            IconButton(
              tooltip: 'Partager',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _marketCtrl.shareListing(item),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _onEdit(item);
                  case 'sold':
                    _onToggleSold(item);
                  case 'renew':
                    _onRenew(item);
                  case 'delete':
                    _onDelete(item);
                  case 'report':
                    _marketCtrl.reportListing(item);
                }
              },
              itemBuilder: (context) => mine
                  ? [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Modifier l’annonce'),
                      ),
                      PopupMenuItem(
                        value: 'sold',
                        child: Text(
                          item.sold
                              ? item.reopenLabel
                              : 'Marquer comme ${item.closedLabel.toLowerCase()}',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'renew',
                        child: Text('Relancer (60 jours)'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Supprimer l’annonce'),
                      ),
                    ]
                  : [
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Signaler cette annonce'),
                      ),
                    ],
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
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Stack(
                      children: [
                        if (item.hasImages)
                          _ImageSection(
                            item: item,
                            isDark: isDark,
                            accent: accent,
                          )
                        else
                          _TextOnlyHeader(item: item, isDark: isDark),
                        if (item.sold)
                          Positioned(
                            top: 14,
                            left: 14,
                            child: _StateTag(
                              label: item.closedLabel.toUpperCase(),
                            ),
                          )
                        else if (item.isExpired)
                          const Positioned(
                            top: 14,
                            left: 14,
                            child: _StateTag(label: 'EXPIRÉE'),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Badge(
                                label: item.typeLabel.toUpperCase(),
                                bg: accent.withValues(alpha: 0.12),
                                fg: accent,
                              ),
                              _Badge(
                                label:
                                    '${item.category.icon} ${item.category.label}',
                                bg: ink.withValues(alpha: 0.06),
                                fg: muted,
                              ),
                              if (item.condition != null)
                                _Badge(
                                  label: item.condition!.label,
                                  bg: ink.withValues(alpha: 0.06),
                                  fg: muted,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            item.title,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 0,
                            runSpacing: 6,
                            children: [
                              Text(
                                item.priceLabel,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                              if (item.negotiable) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.4),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Négociable',
                                    style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.rentalDurationLabel.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: muted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Location de ${item.rentalDurationLabel}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (item.hasDescription) ...[
                            const SizedBox(height: 22),
                            Text(
                              'Description',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.description,
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                height: 1.55,
                                color: muted,
                              ),
                            ),
                          ],

                          // --- Statistiques, réservées au propriétaire ---
                          if (mine) ...[
                            const SizedBox(height: 24),
                            _OwnerStats(item: item, isDark: isDark),
                          ],

                          const SizedBox(height: 24),
                          _SellerCard(
                            item: item,
                            reputation: _reputation,
                            reviews: _sellerReviews,
                            isDark: isDark,
                            canReview: !mine && _canReview,
                            onReview: () => _onReview(item),
                          ),

                          if (_otherListings.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _ListingRail(
                              items: _otherListings,
                              title: mine
                                  ? 'Vos autres annonces'
                                  : 'Autres annonces de ${item.sellerName}',
                              subtitle: _otherListings.length == 1
                                  ? '1 annonce encore en vente'
                                  : '${_otherListings.length} annonces '
                                        'encore en vente',
                              isDark: isDark,
                            ),
                          ],

                          const SizedBox(height: 10),
                          _InfoTile(
                            icon: Icons.location_on_outlined,
                            label: 'Localisation',
                            value: item.location.isEmpty
                                ? 'Foumbot'
                                : item.location,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _InfoTile(
                            icon: Icons.access_time,
                            label: 'Publié',
                            value: _marketCtrl.timeAgo(item.createdAt),
                            isDark: isDark,
                          ),

                          // --- Numéro du vendeur ---
                          if (!mine && !item.sold && item.hasPhone) ...[
                            const SizedBox(height: 10),
                            _PhoneTile(
                              phone: phone,
                              isDark: isDark,
                              onReveal: () => _onRevealPhone(item),
                            ),
                          ],

                          if (!mine) ...[
                            const SizedBox(height: 18),
                            SafetyNotice(isDark: isDark),
                          ],

                          // Tout en bas, et c'est voulu : on ne propose
                          // autre chose qu'à quelqu'un qui a déjà lu
                          // l'annonce jusqu'au bout sans être convaincu.
                          if (_similar.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            _ListingRail(
                              items: _similar,
                              title: 'Annonces similaires',
                              subtitle:
                                  'Dans ${item.category.label.toLowerCase()}, '
                                  'chez d’autres vendeurs',
                              isDark: isDark,
                            ),
                          ],
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                item: item,
                isDark: isDark,
                mine: mine,
                phoneRevealed: phone != null,
                onCall: () => _marketCtrl.callSeller(item),
                onWhatsApp: () => _marketCtrl.whatsappSeller(item),
                onSms: () => _marketCtrl.smsSeller(item),
                onRevealPhone: () => _onRevealPhone(item),
                onMessage: () => _marketCtrl.chatWithSeller(item),
                onOffer: () => _onOffer(item),
                onEdit: () => _onEdit(item),
                onToggleSold: () => _onToggleSold(item),
                onRenew: () => _onRenew(item),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Bandes d'annonces (autres annonces du vendeur, annonces similaires)
// ---------------------------------------------------------------------------

/// Bande horizontale d'annonces, employée par les deux sections de la
/// fiche : les autres annonces du vendeur, et les annonces similaires.
///
/// Horizontale plutôt qu'en grille : ce sont des compléments, ils ne
/// doivent pas repousser en bas d'écran la localisation, la date et le
/// numéro — ce que l'acheteur est vraiment venu chercher.
class _ListingRail extends StatelessWidget {
  const _ListingRail({
    required this.items,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  final List<MarketItem> items;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Column(
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
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // La liste dépasse les marges de la fiche pour que la
            // dernière carte soit coupée par le bord : c'est ce qui
            // signale qu'on peut faire défiler.
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) =>
                _OtherListingCard(item: items[i], isDark: isDark),
          ),
        ),
      ],
    );
  }
}

class _OtherListingCard extends StatelessWidget {
  const _OtherListingCard({required this.item, required this.isDark});

  final MarketItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final accent = item.listingType == MarketListingType.vente
        ? AppColors.orange
        : AppColors.blue;

    return SizedBox(
      width: 142,
      child: Material(
        color: isDark ? AppColors.blackElevated : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // `preventDuplicates: false` est indispensable : on empile un
          // écran de détail sur un écran de détail, que GetX refuserait
          // par défaut — l'appui n'aurait alors aucun effet.
          onTap: () => Get.toNamed(
            AppRoutes.marketDetail,
            arguments: item.id,
            preventDuplicates: false,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 106,
                  width: double.infinity,
                  child: item.hasImages
                      ? CachedNetworkImage(
                          imageUrl: displayImageUrl(item.imageUrls.first),
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              ColoredBox(color: accent.withValues(alpha: 0.06)),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: accent.withValues(alpha: 0.06),
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: muted,
                              size: 22,
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: accent.withValues(alpha: 0.08),
                          child: Center(
                            child: Icon(
                              Icons.sell_outlined,
                              color: accent,
                              size: 26,
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.priceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bandeau d'état (vendu / expirée)
// ---------------------------------------------------------------------------

class _StateTag extends StatelessWidget {
  const _StateTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numéro du vendeur — masqué tant qu'on ne le demande pas
// ---------------------------------------------------------------------------

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({
    required this.phone,
    required this.isDark,
    required this.onReveal,
  });

  final String? phone;
  final bool isDark;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, size: 20, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Téléphone',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone ?? '•• •• •• •• ••',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: phone == null ? 1.5 : 0,
                    color: phone == null ? muted : ink,
                  ),
                ),
              ],
            ),
          ),
          if (phone == null)
            TextButton(
              onPressed: onReveal,
              child: Text(
                'Afficher',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: AppColors.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Statistiques du propriétaire
// ---------------------------------------------------------------------------

class _OwnerStats extends StatelessWidget {
  const _OwnerStats({required this.item, required this.isDark});

  final MarketItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    final expiry = item.sold
        ? 'Retirée du marché'
        : item.isExpired
        ? 'Expirée — relancez-la pour la remettre en ligne'
        : 'Encore ${item.daysLeft} jour${item.daysLeft > 1 ? 's' : ''} '
              'en ligne';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre annonce',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(
                value: item.viewsCount,
                label: 'vues',
                icon: Icons.visibility_outlined,
                ink: ink,
                muted: muted,
              ),
              _Stat(
                value: item.favoritesCount,
                label: 'favoris',
                icon: Icons.favorite_border,
                ink: ink,
                muted: muted,
              ),
              _Stat(
                value: item.contactsCount,
                label: 'contacts',
                icon: Icons.phone_in_talk_outlined,
                ink: ink,
                muted: muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  expiry,
                  style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.ink,
    required this.muted,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 18, color: AppColors.orange),
        const SizedBox(height: 5),
        Text(
          '$value',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        Text(label, style: GoogleFonts.manrope(fontSize: 11.5, color: muted)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Fiche vendeur — ancienneté, note, derniers avis
// ---------------------------------------------------------------------------

class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.item,
    required this.reputation,
    required this.reviews,
    required this.isDark,
    required this.canReview,
    required this.onReview,
  });

  final MarketItem item;
  final SellerReputation reputation;
  final List<SellerReview> reviews;
  final bool isDark;
  final bool canReview;
  final VoidCallback onReview;

  String get _memberSince {
    final date = reputation.memberSince;
    if (date == null) return 'Habitant·e de Foumbot';
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return 'Membre depuis ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.orange.withValues(alpha: 0.15),
                child: Text(
                  item.sellerName.isEmpty
                      ? '?'
                      : item.sellerName.characters.first.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.sellerName,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _memberSince,
                      style: GoogleFonts.manrope(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              if (reputation.hasRating)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          reputation.ratingLabel,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${reputation.ratingCount} avis',
                      style: GoogleFonts.manrope(fontSize: 11, color: muted),
                    ),
                  ],
                ),
            ],
          ),
          if (!reputation.hasRating) ...[
            const SizedBox(height: 10),
            Text(
              'Ce vendeur n’a pas encore d’avis. Rencontrez-vous dans un '
              'lieu public et vérifiez l’article avant de payer.',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.45,
                color: muted,
              ),
            ),
          ],
          for (final review in reviews) ...[
            const SizedBox(height: 12),
            _ReviewLine(review: review, ink: ink, muted: muted),
          ],
          if (canReview) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.star_border, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: BorderSide(
                    color: AppColors.orange.withValues(alpha: 0.5),
                  ),
                ),
                label: const Text('Noter ce vendeur'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({
    required this.review,
    required this.ink,
    required this.muted,
  });

  final SellerReview review;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= review.rating ? Icons.star : Icons.star_border,
                size: 13,
                color: AppColors.orange,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                review.reviewerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            review.comment,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.4,
              color: muted,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête texte seul (quand pas de photo)
// ---------------------------------------------------------------------------

class _TextOnlyHeader extends StatelessWidget {
  const _TextOnlyHeader({required this.item, required this.isDark});

  final MarketItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = marketTypeColor(item.listingType);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.15 : 0.08),
            accent.withValues(alpha: isDark ? 0.05 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(item.category.icon, style: const TextStyle(fontSize: 64)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section images (galerie plein écran)
// ---------------------------------------------------------------------------

class _ImageSection extends StatefulWidget {
  const _ImageSection({
    required this.item,
    required this.isDark,
    required this.accent,
  });

  final MarketItem item;
  final bool isDark;
  final Color accent;

  @override
  State<_ImageSection> createState() => _ImageSectionState();
}

class _ImageSectionState extends State<_ImageSection> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.item.imageUrls;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _page = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, i) =>
                FeedNetworkImage(url: images[i], isDark: widget.isDark),
          ),
          if (images.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1} / ${images.length}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (images.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composants réutilisables
// ---------------------------------------------------------------------------

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre d'actions (bas d'écran) — dépend du rôle (propriétaire / acheteur)
// et de l'état (vendu, expiré, numéro révélé ou non).
// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.item,
    required this.isDark,
    required this.mine,
    required this.phoneRevealed,
    required this.onCall,
    required this.onWhatsApp,
    required this.onSms,
    required this.onRevealPhone,
    required this.onMessage,
    required this.onOffer,
    required this.onEdit,
    required this.onToggleSold,
    required this.onRenew,
  });

  final MarketItem item;
  final bool isDark;
  final bool mine;
  final bool phoneRevealed;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onSms;
  final VoidCallback onRevealPhone;
  final VoidCallback onMessage;
  final VoidCallback onOffer;
  final VoidCallback onEdit;
  final VoidCallback onToggleSold;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        border: Border(top: BorderSide(color: ink.withValues(alpha: 0.08))),
      ),
      child: SafeArea(top: false, child: _buildContent(ink, muted)),
    );
  }

  Widget _buildContent(Color ink, Color muted) {
    if (mine) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.isExpired && !item.sold) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRenew,
                icon: const Icon(Icons.refresh, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: Text('Relancer pour ${kListingLifetime.inDays} jours'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: BorderSide(color: ink.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: const Text('Modifier'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onToggleSold,
                  icon: Icon(
                    item.sold ? Icons.refresh : Icons.check_circle_outline,
                    size: 18,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: item.sold ? muted : AppColors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: Text(
                    item.sold
                        ? item.reopenLabel
                        : 'Marquer ${item.closedLabel.toLowerCase()}',
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (item.sold || item.isExpired) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 18, color: muted),
          const SizedBox(width: 8),
          Text(
            item.sold ? item.closedMessage : 'Cette annonce a expiré',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.hasPhone) ...[
          // Tant que le numéro n'est pas révélé, un seul bouton : ça évite
          // trois raccourcis qui déclencheraient chacun la même lecture,
          // et ça rend explicite le moment où l'on demande le contact.
          if (!phoneRevealed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRevealPhone,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.orange,
                  side: const BorderSide(color: AppColors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                label: const Text('Afficher le numéro'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _MiniAction(
                    icon: Icons.phone,
                    label: 'Appeler',
                    color: AppColors.orange,
                    isDark: isDark,
                    onTap: onCall,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.chat,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    isDark: isDark,
                    onTap: onWhatsApp,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.sms_outlined,
                    label: 'SMS',
                    color: AppColors.blue,
                    isDark: isDark,
                    onTap: onSms,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.forum_outlined, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('Message'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: onOffer,
                icon: const Icon(Icons.local_offer_outlined, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: BorderSide(color: ink.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('Faire une offre'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: isDark ? 0.16 : 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
