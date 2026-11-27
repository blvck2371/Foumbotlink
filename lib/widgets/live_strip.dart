import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/live_session.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/live_service.dart';
import '../services/moderation_service.dart';
import '../services/profile_gate.dart';
import '../theme/app_colors.dart';
import 'live_ring.dart';
import 'user_avatar.dart';

/// Bouton « LIVE » de la barre du haut, comme sur TikTok : rouge et animé
/// quand quelqu'un est en direct, avec leur nombre ; discret sinon.
class LiveEntryButton extends StatelessWidget {
  const LiveEntryButton({super.key, required this.onTap, required this.ink});

  final VoidCallback onTap;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = _visibleLives().length;
      final on = count > 0;
      return Semantics(
        button: true,
        label: on ? 'Lives : $count en direct' : 'Lives',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: on ? AppColors.live : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: on
                  ? null
                  : Border.all(color: ink.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LIVE',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: on ? AppColors.white : ink,
                  ),
                ),
                if (on) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.live,
                      ),
                    ),
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

/// Lives visibles pour moi : ni les miens, ni ceux de comptes bloqués.
List<LiveSession> _visibleLives() {
  if (!Get.isRegistered<LiveService>()) return const [];
  final auth = Get.find<AuthService>();
  final me = auth.isSignedIn ? auth.uid : '';
  final moderation = Get.isRegistered<ModerationService>()
      ? Get.find<ModerationService>()
      : null;
  return [
    for (final l in Get.find<LiveService>().lives)
      if (l.hostUid != me && !(moderation?.hides(l.hostUid) ?? false)) l,
  ];
}

/// « En direct » en haut du fil : qui est en live en ce moment, en
/// pastilles cerclées de rouge — un toucher et on est dans son live. La
/// première pastille lance le sien. N'apparaît que s'il y a un live.
class LiveStrip extends StatelessWidget {
  const LiveStrip({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final lives = _visibleLives();
      if (lives.isEmpty) return const SizedBox.shrink();
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.live,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'En direct',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${lives.length}',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: lives.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                if (i == 0) return _GoLiveBubble(ink: ink);
                final live = lives[i - 1];
                return _LiveBubble(live: live, ink: ink, muted: muted);
              },
            ),
          ),
        ],
      );
    });
  }
}

class _LiveBubble extends StatelessWidget {
  const _LiveBubble({
    required this.live,
    required this.ink,
    required this.muted,
  });

  final LiveSession live;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${live.hostName} est en live : ${live.title}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => watchLive(live.id),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.live, Color(0xFFFF5C8A)],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).scaffoldBackgroundColor,
                      ),
                      child: UserAvatar(
                        name: live.hostName,
                        photoUrl: live.hostPhoto,
                        radius: 28,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.live,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        'LIVE',
                        style: GoogleFonts.manrope(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                live.hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              Text(
                '${LiveRules.compactCount(live.viewers)} spect.',
                maxLines: 1,
                style: GoogleFonts.manrope(fontSize: 10.5, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoLiveBubble extends StatelessWidget {
  const _GoLiveBubble({required this.ink});
  final Color ink;

  Future<void> _go() async {
    if (!await ProfileGate.ensure(reason: 'Pour lancer un live')) return;
    await Get.toNamed(AppRoutes.liveHost);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Lancer un live',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _go,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.live.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: AppColors.live,
                  size: 28,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Lancer',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
