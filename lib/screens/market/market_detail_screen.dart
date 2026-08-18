import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/market_controller.dart';
import '../../models/market_item.dart';
import '../../services/market_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

class MarketDetailScreen extends StatefulWidget {
  const MarketDetailScreen({super.key});

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  final _market = Get.find<MarketService>();
  final _marketCtrl = Get.find<MarketController>();

  late String _itemId;
  MarketItem? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _itemId = Get.arguments as String;
    _loadItem();
  }

  Future<void> _loadItem() async {
    final idx = _marketCtrl.items.indexWhere((e) => e.id == _itemId);
    if (idx >= 0) {
      if (mounted) setState(() { _item = _marketCtrl.items[idx]; _loading = false; });
      return;
    }
    final fetched = await _market.getById(_itemId);
    if (mounted) setState(() { _item = fetched; _loading = false; });
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
          body: const Center(
            child: FoumbotLoader(),
          ),
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

      final isVente = item.listingType == MarketListingType.vente;
      final accent = isVente ? AppColors.red : AppColors.blue;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Détail'),
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
                    if (item.hasImages)
                      _ImageSection(item: item, isDark: isDark, accent: accent)
                    else
                      _TextOnlyHeader(item: item, isDark: isDark),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badges
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
                                label: '${item.category.icon} ${item.category.label}',
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
                          // Titre
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
                          // Prix
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
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
                                      horizontal: 8, vertical: 4),
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
                          // Description
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
                          const SizedBox(height: 24),
                          // Infos vendeur
                          _InfoTile(
                            icon: Icons.person_outline,
                            label: 'Vendeur',
                            value: item.sellerName,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _InfoTile(
                            icon: Icons.location_on_outlined,
                            label: 'Localisation',
                            value: item.location,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _InfoTile(
                            icon: Icons.access_time,
                            label: 'Publié',
                            value: _marketCtrl.timeAgo(item.createdAt),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ContactBar(phone: item.sellerPhone, isDark: isDark, accent: accent),
            ],
          ),
        ),
      );
    });
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
    final isVente = item.listingType == MarketListingType.vente;
    final accent = isVente ? AppColors.red : AppColors.blue;

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
        child: Text(
          item.category.icon,
          style: const TextStyle(fontSize: 64),
        ),
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
            itemBuilder: (context, i) => FeedNetworkImage(
              url: images[i],
              isDark: widget.isDark,
            ),
          ),
          // Compteur
          if (images.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          // Indicateurs
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
          Icon(icon, size: 20, color: AppColors.red),
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

class _ContactBar extends StatelessWidget {
  const _ContactBar({
    required this.phone,
    required this.isDark,
    required this.accent,
  });

  final String phone;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        border: Border(
          top: BorderSide(color: ink.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Contact',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: accent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {},
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone, size: 18, color: AppColors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Appeler',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
