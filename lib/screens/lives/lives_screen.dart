import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/live_session.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/live_service.dart';
import '../../services/moderation_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/user_avatar.dart';
import 'live_widgets.dart';
import '../../utils/image_url.dart';

/// Le menu Lives : lancer le sien, ou entrer dans un live en cours. La
/// grille se met à jour toute seule (Realtime Database) : un live qui
/// démarre apparaît, un live qui finit disparaît, les compteurs bougent.
class LivesScreen extends StatelessWidget {
  const LivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final service = Get.find<LiveService>();
    final moderation = Get.find<ModerationService>();
    final auth = Get.find<AuthService>();
    final myUid = auth.isSignedIn ? auth.uid : '';

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final lives = [
        for (final l in service.lives)
          if (!moderation.hides(l.hostUid)) l,
      ];

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Lives'),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: _GoLiveCard(isDark: isDark, ink: ink, muted: muted),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'En direct maintenant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    if (lives.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const LiveBadge(small: true),
                      const SizedBox(width: 6),
                      Text(
                        '${lives.length}',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (lives.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(ink: ink, muted: muted),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: lives.length,
                  itemBuilder: (context, i) => _LiveCard(
                    live: lives[i],
                    mine: lives[i].hostUid == myUid,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _GoLiveCard extends StatelessWidget {
  const _GoLiveCard({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackSoft : const Color(0xFFFFF4EC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => Get.toNamed(AppRoutes.liveHost),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: liveRed,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: AppColors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lancer un live',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Filmez en direct : vos abonnés sont prévenus.',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
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

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.mine});

  final LiveSession live;
  final bool mine;

  Future<void> _open() async {
    if (!mine) {
      await Get.toNamed(AppRoutes.liveViewer, arguments: {'liveId': live.id});
      return;
    }
    // Son propre live, resté ouvert après un arrêt de l'app : on ne peut
    // pas le « regarder » (ce serait une seconde connexion à son nom),
    // seulement le terminer.
    final ok = await confirmAction(
      title: 'Terminer votre live ?',
      message:
          'Ce live est toujours affiché comme en cours. Terminez-le pour '
          'en lancer un nouveau.',
      confirmLabel: 'Terminer',
    );
    if (!ok) return;
    try {
      await Get.find<LiveService>().end(live.id);
    } on LiveException catch (e) {
      Get.snackbar('Impossible', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = live.hostPhoto;
    return Semantics(
      button: true,
      label:
          'Live de ${live.hostName} : ${live.title}, '
          '${live.viewers} spectateurs',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null)
                CachedNetworkImage(
                  imageUrl: displayImageUrl(photo),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const _CardFallback(),
                )
              else
                const _CardFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x59000000),
                      Color(0x00000000),
                      Color(0xCC000000),
                    ],
                    stops: [0, 0.35, 1],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    const LiveBadge(small: true),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: liveGlass(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.visibility_outlined,
                            size: 13,
                            color: AppColors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            LiveRules.compactCount(live.viewers),
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (mine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.orangeDeep,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Votre live',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      live.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        UserAvatar(
                          name: live.hostName,
                          photoUrl: photo,
                          radius: 11,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            live.hostName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _CardFallback extends StatelessWidget {
  const _CardFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7A2E0B), Color(0xFF1F1F1F)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videocam_outlined,
          size: 40,
          color: Color(0x66FFFFFF),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.ink, required this.muted});
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.live_tv_outlined, size: 48, color: muted),
          const SizedBox(height: 14),
          Text(
            'Aucun live en ce moment',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lancez le premier : vos voisins le verront apparaître ici en '
            'temps réel.',
            textAlign: TextAlign.center,
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
