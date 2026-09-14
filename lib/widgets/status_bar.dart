import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/status_feed_controller.dart';
import '../screens/status/status_compose_flow.dart';
import '../screens/status/status_viewer_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'status_ring.dart';
import 'user_avatar.dart';

/// Barre de statuts en tête de l'accueil, à la façon d'Instagram.
///
/// N'affiche que les comptes **auxquels on est abonné** : un statut n'est
/// pas une publication du fil, il s'adresse à ceux qu'on a choisi de
/// suivre. La sienne est toujours en première position, qu'on ait publié
/// ou non — c'est de là qu'on ajoute.
///
/// La barre disparaît entièrement quand il n'y a ni statut à soi ni
/// abonnement qui en publie : une rangée vide occuperait le haut de
/// l'écran pour ne rien dire.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<StatusFeedController>()) {
      return const SizedBox.shrink();
    }
    final controller = Get.find<StatusFeedController>();
    final auth = Get.find<AuthService>();

    return Obx(() {
      if (!auth.isSignedIn) return const SizedBox.shrink();

      final bubbles = controller.bubbles;
      if (bubbles.isEmpty) return const SizedBox.shrink();

      final mine = bubbles.first;
      final others = bubbles.skip(1).toList();
      // Rien à soi et personne d'autre : on ne montre pas la barre.
      if (!mine.hasStatuses && others.isEmpty) return const SizedBox.shrink();

      final ink = isDark ? AppColors.white : AppColors.black;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: bubbles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final bubble = bubbles[i];
                return _StatusBubbleTile(
                  bubble: bubble,
                  isDark: isDark,
                  onTap: () => _open(context, controller, bubble),
                  onAdd: bubble.isMine
                      ? () => composeAndPublishStatus(context)
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Divider(
              height: 1,
              color: ink.withValues(alpha: 0.07),
            ),
          ),
        ],
      );
    });
  }

  /// Ouvre les statuts d'un compte, puis recale les anneaux : la
  /// visionneuse enregistre les vues au fur et à mesure, et refermer
  /// après le premier statut ne doit pas éteindre l'anneau.
  Future<void> _open(
    BuildContext context,
    StatusFeedController controller,
    StatusBubble bubble,
  ) async {
    if (!bubble.hasStatuses) {
      if (bubble.isMine) await composeAndPublishStatus(context);
      return;
    }
    if (!context.mounted) return;
    await openStatusViewer(
      context,
      statuses: List.of(bubble.statuses),
      initialIndex: bubble.startIndex,
      canDelete: bubble.isMine,
      onDelete: (status) async {
        await Get.find<StatusFeedController>().deleteMyStatus(status.id);
      },
      onLikeChanged: controller.applyLike,
    );
    await controller.refreshSeen();
  }
}

/// Une pastille de la barre : l'avatar cerclé, le prénom dessous.
class _StatusBubbleTile extends StatelessWidget {
  const _StatusBubbleTile({
    required this.bubble,
    required this.isDark,
    required this.onTap,
    this.onAdd,
  });

  final StatusBubble bubble;
  final bool isDark;
  final VoidCallback onTap;

  /// Présent sur sa propre pastille : le « + » ajoute un statut de plus,
  /// sans passer par la visionneuse.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final background = isDark ? AppColors.black : AppColors.white;

    // Le prénom suffit : sous 64 pixels, un nom complet est illisible.
    final label = bubble.isMine
        ? 'Votre statut'
        : bubble.authorName.split(' ').first;

    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 68,
            width: 68,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                StatusRing(
                  radius: 27,
                  hasStatuses: bubble.hasStatuses,
                  hasUnseen: bubble.hasUnseen,
                  backgroundColor: background,
                  onTap: onTap,
                  child: UserAvatar(
                    name: bubble.authorName,
                    photoUrl: bubble.authorPhotoUrl,
                    radius: 27,
                  ),
                ),
                if (onAdd != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: background,
                          shape: BoxShape.circle,
                        ),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.orange,
                          child: Icon(Icons.add,
                              size: 14, color: AppColors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: bubble.hasUnseen ? FontWeight.w700 : FontWeight.w500,
              color: bubble.hasUnseen ? ink : muted,
            ),
          ),
        ],
      ),
    );
  }
}
