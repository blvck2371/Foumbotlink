import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/chat_controller.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../routes/app_routes.dart';
import '../../services/chat_service.dart' show ChatActivity, ChatService;
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/safety_notice.dart';
import '../../widgets/chat_activity_line.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/post_image_viewer.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    // Volontairement scopé à `theme.isDarkMode` uniquement (change rarement
    // — bascule manuelle). `otherProfile`/`isLoading` sont lus par des Obx
    // dédiés plus bas (voir _ChatAppBar et _MessageListArea) : sinon, le
    // heartbeat de présence de l'autre participant (toutes les 25s, voir
    // PresenceService) ou son indicateur "typing" (toutes les 5s)
    // reconstruiraient tout l'écran — liste de messages comprise — en
    // continu pendant la conversation.
    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _ChatAppBar(
            isDark: isDark,
            ink: ink,
            muted: muted,
            onMenu: _onMenuAction,
          ),
        ),
        body: Stack(
          children: [
            // Subtle background pattern
            _ChatBackground(isDark: isDark),

            Column(
              children: [
                // Ephemeral indicator
                _EphemeralBanner(isDark: isDark),

                // Barre de recherche, quand elle est demandée par le
                // menu — elle porte sur les messages chargés.
                _SearchBar(isDark: isDark, ink: ink, muted: muted),

                // Rappel de prudence en début de discussion, puis alerte
                // ciblée si un message le justifie.
                _SafetyBanner(isDark: isDark),
                _ScamBanner(isDark: isDark),

                // Messages
                Expanded(
                  child: _MessageListArea(isDark: isDark, muted: muted),
                ),

                // Sticker panel
                _AnimatedStickerPanel(isDark: isDark),

                // Input bar
                _InputBar(isDark: isDark, ink: ink, muted: muted),
              ],
            ),
          ],
        ),
      );
    });
  }

  void _onMenuAction(String action) {
    if (action == 'ephemeral') {
      _showEphemeralSheet();
    } else if (action == 'search') {
      controller.openSearch();
    } else if (action == 'profile') {
      final profile = controller.otherProfile.value;
      if (profile != null) {
        Get.toNamed(
          AppRoutes.userProfile,
          arguments: profile.uid,
          preventDuplicates: false,
        );
      }
    }
  }

  void _showEphemeralSheet() {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(Icons.timer_outlined, size: 32, color: AppColors.blue),
              const SizedBox(height: 10),
              Text(
                'Messages éphémères',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Les messages disparaîtront automatiquement',
                style: GoogleFonts.manrope(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 20),
              Obx(() {
                final current = controller.ephemeralSeconds.value;
                return Column(
                  children: [
                    for (final opt in _ephOptions)
                      _EphemeralOption(
                        label: opt.$2,
                        icon: opt.$3,
                        selected: opt.$1 == current,
                        isDark: isDark,
                        ink: ink,
                        onTap: () {
                          controller.setEphemeral(opt.$1);
                          Get.back();
                        },
                      ),
                  ],
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static const _ephOptions = [
    (null, 'Désactivé', Icons.block),
    (30, '30 secondes', Icons.flash_on),
    (300, '5 minutes', Icons.timer),
    (3600, '1 heure', Icons.hourglass_bottom),
    (86400, '24 heures', Icons.today),
    (604800, '7 jours', Icons.date_range),
  ];
}

class _EphemeralOption extends StatelessWidget {
  const _EphemeralOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.blue.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: selected ? AppColors.blue : ink),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.blue : ink,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.blue,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatAppBar extends GetView<ChatController> {
  const _ChatAppBar({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.onMenu,
  });

  final bool isDark;
  final Color ink;
  final Color muted;
  final void Function(String) onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: ink, size: 20),
              onPressed: Get.back,
            ),
            Expanded(
              child: Obx(() {
                final profile = controller.otherProfile.value;
                final name = profile?.displayName ?? 'Chat';
                final verified = profile?.verified ?? false;
                final profileUid = profile?.uid;
                final photoUrl = profile?.photoUrl;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: profileUid == null
                      ? null
                      : () => Get.toNamed(
                          AppRoutes.userProfile,
                          arguments: profileUid,
                          preventDuplicates: false,
                        ),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'avatar_$profileUid',
                        // UserAvatar plutôt qu'un CircleAvatar codé en dur :
                        // l'en-tête n'affichait que la première lettre du
                        // nom et ignorait complètement `photoUrl`, donc la
                        // photo de profil ne s'affichait jamais dans une
                        // discussion. Le repli sur les initiales est géré
                        // par le widget (pas de photo, chargement, erreur).
                        child: UserAvatar(
                          name: name,
                          photoUrl: photoUrl,
                          radius: 19,
                          backgroundColor: AppColors.orange.withValues(
                            alpha: 0.15,
                          ),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.manrope(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 5),
                                  const VerifiedBadge.small(),
                                ],
                              ],
                            ),
                            _StatusLine(muted: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            IconButton(
              icon: Icon(Icons.call_outlined, color: ink, size: 22),
              onPressed: Get.find<ChatController>().startAudioCall,
            ),
            IconButton(
              icon: Icon(Icons.videocam_outlined, color: ink, size: 24),
              onPressed: Get.find<ChatController>().startVideoCall,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: ink),
              color: isDark ? AppColors.blackElevated : AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ephemeral',
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        color: AppColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Messages éphémères',
                        style: GoogleFonts.manrope(color: ink),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: AppColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Rechercher',
                        style: GoogleFonts.manrope(color: ink),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: AppColors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Voir le profil',
                        style: GoogleFonts.manrope(color: ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends GetView<ChatController> {
  const _StatusLine({required this.muted});
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final activity = controller.otherActivity.value;
      // Même libellé et même animation que dans la liste des conversations
      // (voir ChatActivityLine) — l'activité prime sur la présence, comme
      // sur WhatsApp.
      if (activity != ChatActivity.idle) {
        return ChatActivityLine(activity: activity);
      }
      if (controller.isOtherOnline) {
        return _statusText('en ligne', const Color(0xFF4CAF50));
      }
      final lastSeen = controller.otherProfile.value?.lastSeenAt;
      return _statusText(
        lastSeen == null ? 'hors ligne' : 'vu ${_lastSeenLabel(lastSeen)}',
        muted,
      );
    });
  }

  Widget _statusText(String text, Color color) => Text(
    text,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.manrope(
      fontSize: 11,
      color: color,
      fontWeight: FontWeight.w600,
    ),
  );

  String _lastSeenLabel(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return 'à ${DateFormat('HH:mm').format(d)}';
    return 'le ${DateFormat('d MMM', 'fr_FR').format(d)}';
  }
}

/// Recherche dans la discussion.
///
/// Elle porte sur ce qui est **chargé** — Firestore n'offre pas de
/// recherche plein texte, et remonter l'historique élargit d'autant le
/// champ de la recherche. Le compteur le rappelle en donnant le rang du
/// résultat courant.
class _SearchBar extends GetView<ChatController> {
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
    return Obx(() {
      if (!controller.isSearching.value) return const SizedBox.shrink();
      final results = controller.searchResults;

      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        color: isDark ? AppColors.blackSoft : AppColors.whiteSoft,
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                autofocus: true,
                onChanged: controller.updateSearch,
                style: GoogleFonts.manrope(fontSize: 14, color: ink),
                decoration: InputDecoration.collapsed(
                  hintText: 'Rechercher dans la discussion',
                  hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
                ),
              ),
            ),
            if (controller.searchQuery.value.trim().isNotEmpty)
              Text(
                results.isEmpty
                    ? 'Aucun'
                    : '${controller.searchIndex.value + 1}/${results.length}',
                style: GoogleFonts.manrope(fontSize: 12, color: muted),
              ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_up_rounded, color: ink),
              onPressed: results.isEmpty
                  ? null
                  : controller.previousSearchResult,
            ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: ink),
              onPressed: results.isEmpty ? null : controller.nextSearchResult,
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: ink),
              onPressed: controller.closeSearch,
            ),
          ],
        ),
      );
    });
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _ChatPatternPainter(isDark: isDark)),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  _ChatPatternPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? AppColors.white : AppColors.black).withValues(
        alpha: 0.02,
      )
      ..style = PaintingStyle.fill;

    final rng = Random(42);
    for (var i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 2.0 + rng.nextDouble() * 4;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ChatPatternPainter old) => isDark != old.isDark;
}

class _EphemeralBanner extends GetView<ChatController> {
  const _EphemeralBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final eph = controller.ephemeralSeconds.value;
      if (eph == null || eph <= 0) return const SizedBox.shrink();

      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.blue.withValues(alpha: 0.08),
              AppColors.blue.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, size: 14, color: AppColors.blue),
            const SizedBox(width: 6),
            Text(
              'Messages éphémères : ${_ephLabel(eph)}',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.blue,
              ),
            ),
          ],
        ),
      );
    });
  }

  String _ephLabel(int s) {
    if (s <= 30) return '30s';
    if (s <= 300) return '5 min';
    if (s <= 3600) return '1h';
    if (s <= 86400) return '24h';
    return '7j';
  }
}

/// Rappel de prudence affiché au début d'une discussion.
///
/// Une transaction se conclut ici en main propre, sans que l'app y soit
/// pour quoi que ce soit : le seul moment utile pour rappeler les
/// réflexes de base, c'est quand deux personnes commencent à se parler.
/// Il s'efface de lui-même dès que l'échange est engagé, pour ne pas
/// devenir un décor qu'on ne voit plus.
class _SafetyBanner extends GetView<ChatController> {
  const _SafetyBanner({required this.isDark});
  final bool isDark;

  /// Au-delà de ce nombre de messages, la discussion est lancée : le
  /// rappel a été vu, il laisse la place.
  static const _visibleUntil = 4;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.messages.length > _visibleUntil) {
        return const SizedBox.shrink();
      }
      if (controller.scamWarning.value != null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SafetyNotice(isDark: isDark, compact: true),
      );
    });
  }
}

/// Avertissement déclenché par le contenu du dernier message reçu
/// (demande d'acompte, de transfert Mobile Money, envoi à distance…).
///
/// Placé juste au-dessus du fil, là où l'œil revient après avoir lu le
/// message : un rappel affiché ailleurs, ou une fois pour toutes à
/// l'ouverture, ne serait pas lu au moment qui compte.
class _ScamBanner extends GetView<ChatController> {
  const _ScamBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final warning = controller.scamWarning.value;
      if (warning == null) return const SizedBox.shrink();
      return ScamAlertBanner(
        warning: warning,
        isDark: isDark,
        onDismiss: controller.dismissScamWarning,
      );
    });
  }
}

class _MessageListArea extends GetView<ChatController> {
  const _MessageListArea({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(child: FoumbotLoader());
      }
      return _MessageList(isDark: isDark, muted: muted);
    });
  }
}

class _MessageList extends GetView<ChatController> {
  const _MessageList({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final msgs = controller.messages;

      if (msgs.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 40,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Commencez la conversation !',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.white : AppColors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Envoyez un message, un vocal ou un sticker',
                style: GoogleFonts.manrope(fontSize: 13, color: muted),
              ),
            ],
          ),
        );
      }

      // Les photos envoyées à la suite forment un album — voir
      // `groupChatMessages`. Un groupe d'un seul message reste la bulle
      // ordinaire, inchangée.
      final groups = groupChatMessages(msgs);

      return NotificationListener<ScrollNotification>(
        // On remonte une page d'historique quand la personne fait
        // *défiler vers le haut* et approche du début de la liste.
        //
        // Le simple test « pixels <= 120 » se déclenchait aussi à la
        // toute première image, avant même le défilement automatique vers
        // le bas : on chargeait de l'historique que personne n'avait
        // demandé. D'où le `scrollDelta < 0`, qui ne retient que le geste
        // vers le haut.
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification &&
              (notification.scrollDelta ?? 0) < 0 &&
              notification.metrics.pixels <= 120) {
            controller.loadOlder();
          }
          return false;
        },
        child: ListView.builder(
          controller: controller.scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          // Une entrée de plus en tête : le chargeur d'historique, ou le
          // repère « début de la conversation ».
          itemCount: groups.length + 1,
          itemBuilder: (_, index) {
            if (index == 0) return _HistoryHeader(muted: muted);
            final i = index - 1;
            final group = groups[i];
            final msg = group.first;
            final isMine = msg.senderUid == controller.myUid;
            final showDate =
                i == 0 ||
                !_sameDay(groups[i - 1].last.createdAt, msg.createdAt);

            return Column(
              key: ValueKey(msg.id),
              children: [
                if (showDate)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.white : AppColors.black)
                            .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _dateLabel(msg.createdAt),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                if (controller.firstUnreadId.value == msg.id)
                  const _UnreadDivider(),
                RepaintBoundary(
                  child: _AnimatedBubble(
                    index: i,
                    child: Dismissible(
                      key: ValueKey('swipe-${msg.id}'),
                      direction: DismissDirection.horizontal,
                      movementDuration: const Duration(milliseconds: 180),
                      dismissThresholds: const {
                        DismissDirection.startToEnd: 0.22,
                        DismissDirection.endToStart: 0.22,
                      },
                      confirmDismiss: (_) async {
                        HapticFeedback.selectionClick();
                        controller.startReply(msg);
                        return false;
                      },
                      background: const _SwipeReplyHint(alignEnd: false),
                      secondaryBackground: const _SwipeReplyHint(
                        alignEnd: true,
                      ),
                      child: KeyedSubtree(
                        key: controller.bubbleKey(msg.id),
                        child: Obx(() {
                          // Un album porte plusieurs identifiants : citer
                          // l'une de ses photos doit éclairer l'album.
                          final target = controller.highlightedId.value;
                          final highlighted =
                              target != null &&
                              group.any((m) => m.id == target);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: BoxDecoration(
                              color: highlighted
                                  ? AppColors.blue.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _MessageBubble(
                              message: msg,
                              album: group,
                              isMine: isMine,
                              isDark: isDark,
                              onRetry: isMine
                                  ? () => controller.retrySend(msg)
                                  : null,
                              onReply: () => controller.startReply(msg),
                              onQuoteTap: msg.isReply
                                  ? () =>
                                        controller.jumpToMessage(msg.replyToId!)
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Aujourd’hui';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Hier';
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }
}

/// En tête de liste : le chargeur d'historique, le bouton pour remonter,
/// ou le repère de début de conversation.
///
/// L'écoute temps réel ne porte que sur les derniers messages ; sans ce
/// chargement, tout ce qui précède restait inatteignable depuis l'app.
class _HistoryHeader extends GetView<ChatController> {
  const _HistoryHeader({required this.muted});

  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingHistory.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(child: FoumbotLoader()),
        );
      }
      if (!controller.hasMoreHistory.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              'Début de la conversation',
              style: GoogleFonts.manrope(fontSize: 11, color: muted),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: TextButton(
            onPressed: controller.loadOlder,
            child: Text(
              'Charger les messages précédents',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.orange,
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Barre « messages non lus » — posée une fois pour toutes devant le
/// premier message reçu non lu à l'ouverture, pour retrouver où l'on s'est
/// arrêté sans remonter à l'aveugle.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: AppColors.orange.withValues(alpha: 0.35)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Messages non lus',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: AppColors.orange.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBubble extends StatefulWidget {
  const _AnimatedBubble({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Les réactions proposées d'un geste. Volontairement courtes : une
/// rangée qui tient sans défilement sur le plus petit téléphone visé.
const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    this.album = const [],
    this.onRetry,
    this.onReply,
    this.onQuoteTap,
  });

  final ChatMessage message;

  /// Les messages que cette bulle rend d'un bloc. Un seul élément (ou une
  /// liste vide) = bulle ordinaire ; plusieurs = album de photos, monté
  /// par `groupChatMessages`. [message] en est toujours le premier : c'est
  /// lui qui porte l'horodatage, l'état d'envoi et la citation.
  final List<ChatMessage> album;

  final bool isMine;
  final bool isDark;
  final VoidCallback? onRetry;
  final VoidCallback? onReply;

  /// Appui sur la citation d'une réponse → défile jusqu'au message d'origine.
  final VoidCallback? onQuoteTap;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _playerInit = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isMine = widget.isMine;
    final isDark = widget.isDark;
    final time = DateFormat('HH:mm').format(msg.createdAt);

    final colors = _BubbleColors.of(isMine: isMine, isDark: isDark);
    final bgColor = colors.background;
    final textColor = colors.ink;
    final timeColor = colors.meta;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: GestureDetector(
          // Rien à faire sur un message supprimé : ni répondre, ni copier,
          // ni transférer, ni resupprimer.
          onLongPress: msg.deleted ? null : () => _showMessageActions(context),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMine ? 20 : 6),
                bottomRight: Radius.circular(isMine ? 6 : 20),
              ),
              border: colors.border == null
                  ? null
                  : Border.all(color: colors.border!),
              // Ombre neutre et discrète : une ombre teintée sur une bulle
              // colorée salit la teinte au lieu de la détacher.
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(
                    alpha: isDark ? 0.22 : 0.06,
                  ),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Container(
              padding: msg.type == MessageType.image
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (msg.isReply)
                    Padding(
                      padding: EdgeInsets.only(
                        top: msg.type == MessageType.image ? 8 : 0,
                        left: msg.type == MessageType.image ? 8 : 0,
                        right: msg.type == MessageType.image ? 8 : 0,
                        bottom: 6,
                      ),
                      child: _QuotedReply(
                        message: msg,
                        colors: colors,
                        onTap: widget.onQuoteTap,
                      ),
                    ),
                  // Réaction ou commentaire sur un statut : la vignette du
                  // statut coiffe le message, comme sur WhatsApp. Le
                  // statut disparaît au bout de 24 h, cette citation reste
                  // — c'est elle qui garde la conversation compréhensible.
                  //
                  // Sauf si le message a été retiré : la vignette dirait
                  // encore « a aimé votre statut » sous un « Message
                  // supprimé », et laisserait donc lire ce qu'on venait
                  // justement d'effacer.
                  if (msg.statusRef != null && !msg.deleted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _QuotedStatus(
                        statusRef: msg.statusRef!,
                        senderUid: msg.senderUid,
                        colors: colors,
                      ),
                    ),
                  _buildContent(msg, textColor, isDark),
                  if (msg.reactions.isNotEmpty)
                    Padding(
                      padding: msg.type == MessageType.image
                          ? const EdgeInsets.only(left: 8, right: 8, top: 6)
                          : const EdgeInsets.only(top: 6),
                      child: _buildReactions(msg, colors),
                    ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: msg.type == MessageType.image
                        ? const EdgeInsets.only(right: 8, bottom: 4)
                        : EdgeInsets.zero,
                    child: _buildStatusRow(msg, time, timeColor, colors),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageActions(BuildContext context) {
    final msg = widget.message;
    final isDark = widget.isDark;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Réactions d'abord : c'est le geste le plus fréquent, et il
            // referme la feuille aussitôt.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _quickReactions)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Get.find<ChatController>().toggleReaction(msg, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              msg.reactions[Get.find<ChatController>().myUid] ==
                                  emoji
                              ? AppColors.orange.withValues(alpha: 0.18)
                              : Colors.transparent,
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            ListTile(
              leading: Icon(Icons.reply_rounded, color: ink),
              title: Text(
                'Répondre',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onReply?.call();
              },
            ),
            if (msg.type == MessageType.text)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: ink),
                title: Text(
                  'Copier le texte',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.content));
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              leading: Icon(Icons.forward_rounded, color: ink),
              title: Text(
                'Transférer',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showForwardPicker(context, msg);
              },
            ),
            // Retirer de son propre affichage : toujours offert, quel que
            // soit l'expéditeur et l'âge du message.
            ListTile(
              leading: Icon(Icons.visibility_off_outlined, color: ink),
              title: Text(
                'Supprimer pour moi',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              subtitle: Text(
                'Le message reste visible par votre interlocuteur.',
                style: GoogleFonts.manrope(fontSize: 12, color: muted),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmAction(
                  title: 'Supprimer pour moi ?',
                  message:
                      'Ce message disparaîtra de votre écran. Votre '
                      'interlocuteur le verra toujours.',
                );
                if (ok) await Get.find<ChatController>().hideMessage(msg);
              },
            ),
            // Retirer à tout le monde : l'expéditeur seul, et seulement
            // pendant la fenêtre qui suit l'envoi.
            if (msg.canDeleteForEveryone(Get.find<ChatController>().myUid))
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: Text(
                  'Supprimer pour tout le monde',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok = await confirmAction(
                    title: 'Supprimer pour tout le monde ?',
                    message:
                        'Le message sera retiré de la discussion des deux '
                        'côtés. Cette action est définitive.',
                  );
                  if (ok) await Get.find<ChatController>().deleteMessage(msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Choix de la discussion vers laquelle faire suivre le message.
  ///
  /// Les documents `conversations` ne portent ni nom ni photo — ils sont
  /// résolus ici en une lecture groupée des profils, comme le fait la
  /// liste des conversations.
  void _showForwardPicker(BuildContext context, ChatMessage msg) {
    final isDark = widget.isDark;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final chat = Get.find<ChatController>();
    final myUid = chat.myUid;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child:
            FutureBuilder<
              ({
                List<Conversation> conversations,
                Map<String, String> names,
                Map<String, String?> photos,
              })
            >(
              future: _loadForwardTargets(myUid),
              builder: (_, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: FoumbotLoader()),
                  );
                }
                final data = snapshot.data!;
                // La conversation courante n'est pas une destination : y
                // « transférer » reviendrait à renvoyer le message.
                final targets = data.conversations
                    .map((c) => c.otherUid(myUid))
                    .where((uid) => uid.isNotEmpty && uid != chat.peerUid)
                    .toList();

                if (targets.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Aucune autre discussion vers laquelle transférer.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(fontSize: 14, color: muted),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Transférer à',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: targets.length,
                        itemBuilder: (_, i) {
                          final uid = targets[i];
                          final name = data.names[uid] ?? 'Utilisateur';
                          return ListTile(
                            leading: UserAvatar(
                              name: name,
                              photoUrl: data.photos[uid],
                              radius: 20,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              final sent = await chat.forwardMessage(msg, uid);
                              if (sent) {
                                Get.snackbar(
                                  'Message transféré',
                                  'Envoyé à $name.',
                                  duration: const Duration(seconds: 2),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
      ),
    );
  }

  Future<
    ({
      List<Conversation> conversations,
      Map<String, String> names,
      Map<String, String?> photos,
    })
  >
  _loadForwardTargets(String myUid) async {
    final conversations = await Get.find<ChatService>().recentConversations(
      myUid,
    );
    final uids = conversations
        .map((c) => c.otherUid(myUid))
        .where((uid) => uid.isNotEmpty);
    final summaries = await Get.find<UserProfileService>().summariesFor(uids);
    return (
      conversations: conversations,
      names: {for (final e in summaries.entries) e.key: e.value.name},
      photos: {for (final e in summaries.entries) e.key: e.value.photoUrl},
    );
  }

  /// Réactions posées sur le message, regroupées par emoji. Appuyer sur
  /// l'une d'elles pose ou retire la sienne — le geste le plus court pour
  /// se joindre à une réaction déjà là.
  Widget _buildReactions(ChatMessage msg, _BubbleColors colors) {
    final chat = Get.find<ChatController>();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in msg.reactionCounts)
          GestureDetector(
            onTap: () => chat.toggleReaction(msg, entry.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: colors.ink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
                border: msg.reactions[chat.myUid] == entry.emoji
                    ? Border.all(color: colors.accent, width: 1.2)
                    : null,
              ),
              child: Text(
                entry.count > 1 ? '${entry.emoji} ${entry.count}' : entry.emoji,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusRow(
    ChatMessage msg,
    String time,
    Color timeColor,
    _BubbleColors colors,
  ) {
    final isMine = widget.isMine;

    if (isMine && msg.status == MessageDeliveryStatus.failed) {
      return GestureDetector(
        onTap: widget.onRetry,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Non envoyé',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.refresh_rounded, size: 14, color: colors.accent),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (msg.expiresAt != null) ...[
          Icon(Icons.timer_outlined, size: 10, color: timeColor),
          const SizedBox(width: 3),
        ],
        Text(time, style: GoogleFonts.manrope(fontSize: 10, color: timeColor)),
        if (isMine) ...[
          const SizedBox(width: 4),
          if (msg.status == MessageDeliveryStatus.sending)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: timeColor,
              ),
            )
          else
            Icon(
              msg.isRead ? Icons.done_all : Icons.done,
              size: 14,
              color: msg.isRead ? colors.read : timeColor,
            ),
        ],
      ],
    );
  }

  Widget _buildContent(ChatMessage msg, Color textColor, bool isDark) {
    // Suppression douce : le message reste à sa place dans la
    // conversation — les réponses qui le citent gardent leur cible — mais
    // il ne montre plus rien.
    if (msg.deleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            size: 15,
            color: textColor.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            'Message supprimé',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      );
    }
    return switch (msg.type) {
      MessageType.text => Text(
        msg.content,
        style: GoogleFonts.manrope(fontSize: 15, height: 1.4, color: textColor),
      ),
      MessageType.sticker => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(msg.content, style: const TextStyle(fontSize: 56)),
      ),
      MessageType.voice => _buildVoice(msg, textColor),
      MessageType.image =>
        widget.album.length > 1 ? _buildAlbum(widget.album) : _buildImage(msg),
      MessageType.document => _buildDocument(msg, textColor),
    };
  }

  Widget _buildVoice(ChatMessage msg, Color textColor) {
    return GestureDetector(
      onTap: _togglePlayVoice,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: _playing ? 0.2 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: textColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                height: 28,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    // Au repos, 0,4 ne donnait que 2,32:1 sur la bulle
                    // claire : sous le seuil de 3,0 des éléments
                    // graphiques, alors que l'onde est ce qui signale un
                    // message vocal. 0,55 la ramène à 3,42:1.
                    color: textColor.withValues(alpha: _playing ? 0.9 : 0.55),
                    playing: _playing,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                msg.voiceDurationLabel,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayVoice() async {
    if (_playing) {
      await _player?.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }

    if (!_playerInit) {
      _player = AudioPlayer();
      _player!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      _playerInit = true;
    }

    final content = widget.message.content;
    await _player!.play(
      _isRemote(content) ? UrlSource(content) : DeviceFileSource(content),
    );
    if (mounted) setState(() => _playing = true);
  }

  /// Une bulle en attente/échec (voir MessageDeliveryStatus) contient
  /// encore le chemin du fichier local, pas l'URL Storage — pas encore
  /// uploadé, donc rien à charger depuis le réseau.
  bool _isRemote(String content) => content.startsWith('http');

  Widget _buildImage(ChatMessage msg) {
    if (!_isRemote(msg.content)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(msg.content),
          width: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 220,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 32,
                color: AppColors.gray,
              ),
            ),
          ),
        ),
      );
    }
    // Photo envoyée : on peut l'ouvrir en plein écran (zoom, double tap,
    // glisser pour fermer) — la même visionneuse que le fil, plutôt qu'une
    // vignette de 220 px sur laquelle appuyer ne faisait rien.
    return GestureDetector(
      onTap: () => openPostImageViewer(
        context,
        imageUrls: [msg.content],
        heroPrefix: 'chat_${msg.id}',
      ),
      child: Hero(
        tag: 'chat_${msg.id}_0',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: msg.content,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              width: 220,
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: FoumbotLoader()),
            ),
            errorWidget: (_, _, _) => Container(
              width: 220,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 32,
                  color: AppColors.gray,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Album : les photos envoyées ensemble, en une mosaïque, comme sur
  /// WhatsApp. L'appui sur l'une d'elles ouvre la visionneuse plein écran
  /// **sur cette photo**, et on passe ensuite de l'une à l'autre du bout du
  /// doigt.
  ///
  /// Au-delà de quatre, la dernière tuile porte le nombre de photos
  /// restantes : elles sont toutes dans la visionneuse, seule la mosaïque
  /// s'arrête là pour ne pas manger la conversation.
  Widget _buildAlbum(List<ChatMessage> album) {
    const width = 250.0;
    const gap = 3.0;
    final urls = album.map((m) => m.content).toList();
    final heroPrefix = 'chat_album_${album.first.id}';

    Widget tile(int index, double w, double h) => _albumTile(
      urls: urls,
      index: index,
      heroPrefix: heroPrefix,
      width: w,
      height: h,
      // Le compteur ne s'affiche que sur la dernière tuile visible, et
      // seulement s'il reste des photos derrière.
      hiddenCount: index == 3 && urls.length > 4 ? urls.length - 4 : 0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        child: switch (urls.length) {
          2 => Row(
            children: [
              tile(0, (width - gap) / 2, 150),
              const SizedBox(width: gap),
              tile(1, (width - gap) / 2, 150),
            ],
          ),
          3 => Column(
            children: [
              tile(0, width, 140),
              const SizedBox(height: gap),
              Row(
                children: [
                  tile(1, (width - gap) / 2, 110),
                  const SizedBox(width: gap),
                  tile(2, (width - gap) / 2, 110),
                ],
              ),
            ],
          ),
          _ => Column(
            children: [
              Row(
                children: [
                  tile(0, (width - gap) / 2, 120),
                  const SizedBox(width: gap),
                  tile(1, (width - gap) / 2, 120),
                ],
              ),
              const SizedBox(height: gap),
              Row(
                children: [
                  tile(2, (width - gap) / 2, 120),
                  const SizedBox(width: gap),
                  tile(3, (width - gap) / 2, 120),
                ],
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _albumTile({
    required List<String> urls,
    required int index,
    required String heroPrefix,
    required double width,
    required double height,
    int hiddenCount = 0,
  }) {
    return GestureDetector(
      onTap: () => openPostImageViewer(
        context,
        imageUrls: urls,
        initialIndex: index,
        heroPrefix: heroPrefix,
      ),
      child: Hero(
        tag: '${heroPrefix}_$index',
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: AppColors.orange.withValues(alpha: 0.05),
                  child: const Center(child: FoumbotLoader()),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.orange.withValues(alpha: 0.05),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 26,
                      color: AppColors.gray,
                    ),
                  ),
                ),
              ),
              if (hiddenCount > 0)
                ColoredBox(
                  color: AppColors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Text(
                      '+$hiddenCount',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocument(ChatMessage msg, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.description_outlined, color: textColor, size: 22),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.fileName ?? 'Document',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Text(
                'Appuyer pour ouvrir',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const barCount = 24;
    final gap = size.width / barCount;
    final heights = [
      0.3,
      0.5,
      0.8,
      0.4,
      1.0,
      0.6,
      0.9,
      0.3,
      0.7,
      0.5,
      0.4,
      0.8,
      0.6,
      0.9,
      0.4,
      1.0,
      0.5,
      0.7,
      0.3,
      0.6,
      0.8,
      0.4,
      0.7,
      0.5,
    ];

    for (var i = 0; i < barCount; i++) {
      final x = i * gap + gap / 2;
      final scale = playing ? 1.0 : 0.5;
      final h = size.height * heights[i % heights.length] * scale;
      final y1 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y1), Offset(x, y1 + h), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      playing != old.playing || color != old.color;
}

// ---------------------------------------------------------------------------
// Réponse à un message (citation façon iMessage)
// ---------------------------------------------------------------------------

/// Fond révélé pendant le glissement d'une bulle pour y répondre.
class _SwipeReplyHint extends StatelessWidget {
  const _SwipeReplyHint({required this.alignEnd});

  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: const Icon(
          Icons.reply_rounded,
          color: AppColors.orange,
          size: 22,
        ),
      ),
    );
  }
}

/// Couleurs d'une bulle, résolues une fois par message plutôt que
/// reconstruites à chaque endroit qui en a besoin.
///
/// Le fond des messages envoyés était l'orange vif du thème : le texte
/// blanc n'y atteignait que 3,08:1, sous le seuil AA de 4,5:1, et les
/// coches de lecture 1,19:1. Voir [AppColors.bubbleMineLight] pour le
/// détail des mesures.
class _BubbleColors {
  const _BubbleColors({
    required this.background,
    required this.ink,
    required this.meta,
    required this.accent,
    required this.read,
    this.border,
  });

  factory _BubbleColors.of({required bool isMine, required bool isDark}) {
    if (isMine) {
      return isDark
          ? const _BubbleColors(
              background: AppColors.bubbleMineDark,
              ink: AppColors.white,
              meta: AppColors.bubbleMetaDark,
              accent: AppColors.bubbleAccentDark,
              read: AppColors.bubbleReadDark,
            )
          : const _BubbleColors(
              background: AppColors.bubbleMineLight,
              ink: AppColors.bubbleInkLight,
              meta: AppColors.bubbleMetaLight,
              accent: AppColors.bubbleAccentLight,
              read: AppColors.bubbleReadLight,
            );
    }
    return isDark
        ? const _BubbleColors(
            background: AppColors.blackElevated,
            ink: AppColors.white,
            meta: AppColors.whiteMuted,
            accent: AppColors.bubbleAccentDark,
            read: AppColors.bubbleReadDark,
          )
        // Les deux bulles sont claires en thème clair : un filet de bordure
        // détache celle du correspondant du fond de l'écran, là où la
        // teinte chaude suffit à distinguer les siennes.
        : _BubbleColors(
            background: AppColors.whiteSoft,
            ink: AppColors.black,
            meta: AppColors.gray,
            accent: AppColors.bubbleAccentLight,
            read: AppColors.bubbleReadLight,
            border: AppColors.black.withValues(alpha: 0.07),
          );
  }

  /// Fond de la bulle.
  final Color background;

  /// Texte du message.
  final Color ink;

  /// Horodatage, durées, mentions secondaires.
  final Color meta;

  /// Barre de citation, échec d'envoi.
  final Color accent;

  /// Coches « lu ».
  final Color read;

  /// Filet de contour, seulement là où le fond ne suffit pas à détacher la
  /// bulle de l'écran.
  final Color? border;

  /// Fond d'un bloc en retrait dans la bulle (citation) : l'encre posée en
  /// voile, ce qui fonctionne sur une tuile claire comme sombre.
  Color get inset => ink.withValues(alpha: 0.07);
}

/// Bloc de citation affiché en tête d'un message qui répond à un autre.
class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.message, required this.colors, this.onTap});

  final ChatMessage message;
  final _BubbleColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();
    final fromMe = message.replyToSenderUid == controller.myUid;
    final author = fromMe
        ? 'Vous'
        : (controller.otherProfile.value?.displayName ?? 'Contact');

    // La citation se creuse dans la bulle : un voile d'encre pour le fond,
    // l'accent pour la barre et l'auteur, la couleur secondaire pour
    // l'extrait. Aucune de ces valeurs ne dépend plus du camp du message,
    // la palette de la bulle s'en charge.
    final barColor = colors.accent;
    final bg = colors.inset;
    final titleColor = colors.accent;
    final textColor = colors.meta;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: barColor, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              message.replyToText ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 12.5, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vignette du statut auquel un message se rapporte.
///
/// Aimer ou commenter un statut envoie un message ordinaire dans la
/// conversation — c'est le fonctionnement de WhatsApp, et il évite un
/// écran de notifications de plus à surveiller. Reste à ce que le message
/// dise de quoi il parle : d'où cette vignette, dénormalisée à l'envoi et
/// donc toujours lisible une fois le statut expiré.
class _QuotedStatus extends StatelessWidget {
  const _QuotedStatus({
    required this.statusRef,
    required this.senderUid,
    required this.colors,
  });

  final StatusRef statusRef;
  final String senderUid;
  final _BubbleColors colors;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();
    final iSent = senderUid == controller.myUid;
    final mineIsTheStatus = statusRef.authorUid == controller.myUid;

    // Quatre formulations pour quatre situations, plutôt qu'un « Statut »
    // neutre qui laisserait chacun deviner qui a réagi à quoi.
    final title = statusRef.isLike
        ? (iSent
            ? (mineIsTheStatus ? 'Votre statut' : 'Vous avez aimé ce statut')
            : 'A aimé votre statut')
        : (iSent
            ? (mineIsTheStatus ? 'Votre statut' : 'En réponse à ce statut')
            : 'A répondu à votre statut');

    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
      decoration: BoxDecoration(
        color: colors.inset,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                  ),
                ),
                if (statusRef.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    statusRef.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: colors.meta,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusThumb(statusRef: statusRef),
        ],
      ),
    );
  }
}

/// Aperçu carré du statut cité : sa photo si elle en a une, sinon son
/// fond coloré — une vidéo n'ayant pas de vignette côté client, elle
/// s'annonce par son icône.
class _StatusThumb extends StatelessWidget {
  const _StatusThumb({required this.statusRef});

  final StatusRef statusRef;

  @override
  Widget build(BuildContext context) {
    final preview = statusRef.previewUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 38,
        height: 46,
        child: preview != null && preview.isNotEmpty
            ? FeedNetworkImage(url: preview, isDark: true)
            : ColoredBox(
                color: Color(statusRef.backgroundColor),
                child: Icon(
                  statusRef.isVideo
                      ? Icons.play_circle_outline
                      : Icons.text_fields_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
      ),
    );
  }
}

/// Bandeau au-dessus du champ de saisie pendant qu'on rédige une réponse.
class _ReplyComposerBanner extends StatelessWidget {
  const _ReplyComposerBanner({
    required this.message,
    required this.isDark,
    required this.onCancel,
  });

  final ChatMessage message;
  final bool isDark;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final fromMe = message.senderUid == controller.myUid;
    final author = fromMe
        ? 'vous-même'
        : (controller.otherProfile.value?.displayName ?? 'Contact');

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.white : AppColors.black).withValues(
          alpha: 0.05,
        ),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.orange, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: AppColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Réponse à $author',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  message.shortPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: ink),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _InputBar extends GetView<ChatController> {
  const _InputBar({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        6,
        8,
        6,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Obx(() {
        final recording = controller.isRecording.value;

        if (recording) return _RecordingBar(isDark: isDark);

        final replying = controller.replyingTo.value;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replying != null)
              _ReplyComposerBanner(
                message: replying,
                isDark: isDark,
                onCancel: controller.cancelReply,
              ),
            Row(
              children: [
                _CircleAction(
                  icon: Icons.add,
                  color: AppColors.orange,
                  isDark: isDark,
                  onTap: () => _showAttachMenu(context),
                ),
                _CircleAction(
                  icon: Icons.emoji_emotions_outlined,
                  color: muted,
                  isDark: isDark,
                  onTap: controller.toggleStickers,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.blackElevated
                          : AppColors.whiteSoft,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: muted.withValues(alpha: 0.1)),
                    ),
                    child: TextField(
                      controller: controller.textController,
                      focusNode: controller.inputFocusNode,
                      style: GoogleFonts.manrope(fontSize: 15, color: ink),
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        hintStyle: GoogleFonts.manrope(
                          fontSize: 15,
                          color: muted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: controller.startRecording,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: AppColors.orange,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: controller.sendText,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Photo',
                      color: Colors.purple,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        controller.pickAndSendImage();
                      },
                    ),
                    _AttachOption(
                      icon: Icons.description_rounded,
                      label: 'Document',
                      color: AppColors.blue,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        controller.pickAndSendDocument();
                      },
                    ),
                    _AttachOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Caméra',
                      color: AppColors.orange,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        controller.sendImageFromCamera();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.color,
    required this.isDark,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends GetView<ChatController> {
  const _RecordingBar({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final secs = controller.recordDuration.value;
      final m = secs ~/ 60;
      final s = secs % 60;
      final label = '$m:${s.toString().padLeft(2, '0')}';

      return Row(
        children: [
          GestureDetector(
            onTap: () => controller.stopRecording(cancel: true),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.orange,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          _PulsingDot(),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              'Enregistrement…',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.orange,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => controller.stopRecording(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: AppColors.white,
                size: 20,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.5 + _ctrl.value * 0.5),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: _ctrl.value * 0.4),
              blurRadius: 6 + _ctrl.value * 4,
              spreadRadius: _ctrl.value * 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedStickerPanel extends GetView<ChatController> {
  const _AnimatedStickerPanel({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final show = controller.showStickers.value;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        height: show ? 200 : 0,
        child: show ? _StickerGrid(isDark: isDark) : null,
      );
    });
  }
}

class _StickerGrid extends GetView<ChatController> {
  const _StickerGrid({required this.isDark});
  final bool isDark;

  static const _categories = {
    'Émotions': ['😀', '😂', '🥰', '😎', '😢', '😡', '🤔', '🙏', '😱', '🤩'],
    'Gestes': ['👍', '👎', '👋', '✌️', '🤝', '💪', '🫶', '👏', '🙌', '✊'],
    'Symboles': ['❤️', '🔥', '💯', '🎉', '✨', '⭐', '💫', '🌈', '☀️', '🌙'],
    'Cameroun': ['🇨🇲', '🌍', '🌴', '🏠', '⚽', '🍕', '☕', '🎵', '📸', '✈️'],
  };

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        border: Border(top: BorderSide(color: muted.withValues(alpha: 0.1))),
      ),
      child: DefaultTabController(
        length: _categories.length,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              indicatorColor: AppColors.orange,
              labelColor: AppColors.orange,
              unselectedLabelColor: muted,
              labelStyle: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              tabAlignment: TabAlignment.start,
              tabs: [for (final cat in _categories.keys) Tab(text: cat)],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final stickers in _categories.values)
                    GridView.count(
                      crossAxisCount: 5,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final s in stickers)
                          GestureDetector(
                            onTap: () => controller.sendSticker(s),
                            child: Center(
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 30),
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
    );
  }
}
