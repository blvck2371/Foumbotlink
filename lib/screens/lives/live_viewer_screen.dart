import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/live_feed.dart';
import '../../controllers/live_viewer_controller.dart';
import '../../models/live_session.dart';
import '../../models/report.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/live_service.dart';
import '../../services/moderation_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/user_avatar.dart';
import 'live_widgets.dart';
import '../../utils/image_url.dart';

/// Regarder les lives en plein écran, en glissant de l'un à l'autre.
class LiveViewerScreen extends GetView<LiveViewerController> {
  const LiveViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: AppColors.black,
      // Le clavier ne rétrécit pas la vidéo : seuls les contrôles
      // remontent (voir _LivePage).
      resizeToAvoidBottomInset: false,
      body: Obx(() {
        if (controller.missing.value) return const _EndedPage(live: null);
        if (controller.loading.value || controller.pages.isEmpty) {
          return const Center(child: FoumbotLoader());
        }
        final pages = controller.pages.toList();
        return PageView.builder(
          controller: controller.pageController,
          scrollDirection: Axis.vertical,
          // Sur le panel, on ne glisse pas vers un autre live par
          // mégarde : on le quitte d'abord.
          physics: controller.session.value?.publishing.value ?? false
              ? const NeverScrollableScrollPhysics()
              : null,
          onPageChanged: controller.onPageChanged,
          itemCount: pages.length,
          itemBuilder: (context, i) => Obx(() {
            final s = controller.session.value;
            final active = s != null && s.initial.id == pages[i].id;
            return active
                ? _LivePage(session: s)
                : _Backdrop(live: pages[i], label: null);
          }),
        );
      }),
    );
  }
}

/// Fond d'attente : la photo de l'hôte, assombrie.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.live, required this.label});

  final LiveSession live;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final photo = live.hostPhoto;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null)
          CachedNetworkImage(
            imageUrl: displayImageUrl(photo),
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.6),
            colorBlendMode: BlendMode.darken,
            errorWidget: (_, _, _) => const ColoredBox(color: AppColors.black),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A1406), AppColors.black],
              ),
            ),
          ),
        if (label != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FoumbotLoader(),
                const SizedBox(height: 14),
                Text(
                  label!,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LivePage extends StatelessWidget {
  const _LivePage({required this.session});
  final LiveWatchSession session;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = session.status.value;
      final feed = session.feed.value;
      final live = session.live;

      if (status == LiveWatchStatus.ended) return _EndedPage(live: live);
      if (status == LiveWatchStatus.failed) {
        return _FailedPage(live: live, message: session.message.value);
      }

      final me = feed?.myGuest;
      final onStage = me?.onStage ?? false;
      final guests = feed?.stage ?? const <LiveGuest>[];
      final videos = session.media.videos;
      final micOff = session.media.micOff;
      final tiles = <LiveStageTile>[
        LiveStageTile(
          uid: live.hostUid,
          name: live.hostName,
          photo: live.hostPhoto,
          track: videos[live.hostUid],
          micOff: micOff.contains(live.hostUid),
          isHost: true,
        ),
        for (final g in guests)
          g.uid == session.me.uid
              ? LiveStageTile(
                  uid: g.uid,
                  name: g.name,
                  photo: g.photo,
                  track: session.cameraOn.value ? session.camera.value : null,
                  mirror: session.frontCamera.value,
                  micOff: !session.micOn.value || g.mutedByHost,
                )
              : LiveStageTile(
                  uid: g.uid,
                  name: g.name,
                  photo: g.photo,
                  track: videos[g.uid],
                  micOff: g.mutedByHost || micOff.contains(g.uid),
                ),
      ];

      return GestureDetector(
        // Double tape : un cœur, comme sur TikTok.
        onDoubleTap: feed?.tapHeart,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LiveStageGrid(
              tiles: tiles,
              // Une place libre : demander à monter.
              onTapSeat: me == null && feed != null
                  ? () => showJoinStageSheet(session)
                  : null,
              onTapTile: (t) {
                if (t.uid != session.me.uid && !t.isHost) {
                  unawaited(
                    Get.toNamed(AppRoutes.userProfile, arguments: t.uid),
                  );
                }
              },
              fallback: _Backdrop(
                live: live,
                // Pas d'écran de chargement : la photo de l'hôte occupe
                // l'écran le temps que l'image arrive. Seule une vraie
                // attente s'annonce.
                label: live.hostOnline
                    ? null
                    : 'L’hôte a perdu la connexion, il revient…',
              ),
            ),
            const _Scrims(),
            if (session.audioBlocked.value)
              Center(
                child: FilledButton.icon(
                  onPressed: session.enableAudio,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Activer le son'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    children: [
                      _TopBar(session: session),
                      const Spacer(),
                      if (feed != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: liveFeedHeight(context),
                                child: LiveCommentsList(
                                  feed: feed,
                                  hostUid: live.hostUid,
                                  onLongPress: (c) => _commentActions(c),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              height: liveFeedHeight(context),
                              child: FloatingHearts(bursts: feed.hearts),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LiveComposer(
                          feed: feed,
                          actions: [
                            if (onStage) ...[
                              LiveRoundButton(
                                icon: session.micOn.value && !me!.mutedByHost
                                    ? Icons.mic_none_rounded
                                    : Icons.mic_off_rounded,
                                tooltip: me!.mutedByHost
                                    ? 'Micro coupé par l’hôte'
                                    : session.micOn.value
                                    ? 'Couper le micro'
                                    : 'Rallumer le micro',
                                color: session.micOn.value && !me.mutedByHost
                                    ? null
                                    : liveRed,
                                size: 44,
                                onTap: session.toggleMic,
                              ),
                              LiveRoundButton(
                                icon: session.cameraOn.value
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                tooltip: session.cameraOn.value
                                    ? 'Éteindre ma caméra'
                                    : 'Allumer ma caméra',
                                color: session.cameraOn.value ? null : liveRed,
                                size: 44,
                                onTap: session.toggleCamera,
                              ),
                              if (session.cameraOn.value &&
                                  session.camera.value != null)
                                LiveRoundButton(
                                  icon: Icons.cameraswitch_outlined,
                                  tooltip: 'Changer de caméra',
                                  size: 44,
                                  onTap: session.switchCamera,
                                ),
                              LiveRoundButton(
                                icon: Icons.call_end_rounded,
                                tooltip: 'Quitter le panel',
                                color: liveRed,
                                size: 44,
                                onTap: () => _confirmLeaveStage(),
                              ),
                            ] else ...[
                              _JoinStageButton(session: session),
                              LiveRoundButton(
                                icon: Icons.favorite_rounded,
                                tooltip: 'Envoyer un cœur',
                                color: liveRed,
                                size: 44,
                                onTap: feed.tapHeart,
                              ),
                            ],
                            // Sur le panel, la barre garde la place pour
                            // micro et caméra.
                            if (!onStage)
                              LiveRoundButton(
                                icon: Icons.more_horiz_rounded,
                                tooltip: 'Plus',
                                size: 44,
                                onTap: () => _liveActions(live),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // L'hôte vous invite : une fenêtre, comme sur TikTok. Accepter
            // fait monter tout de suite sur le panel.
            if (me?.status == LiveGuestStatus.invited)
              LivePrompt(
                name: live.hostName,
                photo: live.hostPhoto,
                title: '${live.hostName} vous invite à rejoindre son LIVE',
                message:
                    'Votre caméra et votre micro seront visibles de tous les '
                    'spectateurs. Vous pourrez quitter le panel à tout moment.',
                confirmLabel: 'Accepter et monter',
                onConfirm: session.acceptInvite,
                cancelLabel: 'Refuser',
                onCancel: session.declineInvite,
                extra: LiveCameraChoice(cameraOn: session.cameraOn),
              ),
          ],
        ),
      );
    });
  }

  Future<void> _confirmLeaveStage() async {
    final ok = await confirmAction(
      title: 'Quitter le panel ?',
      message: 'Vous redevenez spectateur de ce live.',
      confirmLabel: 'Quitter',
    );
    if (ok) await session.leaveStage();
  }

  Future<void> _commentActions(LiveComment c) async {
    final me = Get.find<AuthService>().uid;
    final mine = c.uid == me;
    final choice = await showLiveSheet<String>(
      title: '${c.name} : ${c.text}',
      options: [
        if (mine)
          (
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer mon message',
            value: 'delete',
            danger: true,
          )
        else
          (
            icon: Icons.person_outline_rounded,
            label: 'Voir le profil de ${c.name}',
            value: 'profile',
            danger: false,
          ),
      ],
    );
    if (choice == 'delete') {
      await session.feed.value?.deleteComment(c.id);
    } else if (choice == 'profile') {
      unawaited(Get.toNamed(AppRoutes.userProfile, arguments: c.uid));
    }
  }

  Future<void> _liveActions(LiveSession live) async {
    final moderation = Get.find<ModerationService>();
    final choice = await showLiveSheet<String>(
      title: live.title,
      options: [
        (
          icon: Icons.flag_outlined,
          label: 'Signaler ce live',
          value: 'report',
          danger: false,
        ),
        (
          icon: Icons.block_rounded,
          label: 'Bloquer ${live.hostName}',
          value: 'block',
          danger: true,
        ),
        if (moderation.isAdmin.value)
          (
            icon: Icons.stop_circle_outlined,
            label: 'Couper ce live (modération)',
            value: 'cut',
            danger: true,
          ),
      ],
    );
    switch (choice) {
      case 'report':
        await _report(live);
      case 'block':
        await _block(live);
      case 'cut':
        final ok = await confirmAction(
          title: 'Couper ce live ?',
          message: 'Le live s’arrête pour tous les spectateurs.',
          confirmLabel: 'Couper',
        );
        if (!ok) return;
        try {
          await Get.find<LiveService>().end(live.id);
        } on LiveException catch (e) {
          Get.snackbar('Impossible', e.message);
        }
    }
  }

  Future<void> _report(LiveSession live) async {
    final choice = await showReportSheet(targetLabel: 'ce live');
    if (choice == null) return;
    try {
      await Get.find<ModerationService>().report(
        ContentReport(
          targetType: ReportTargetType.live,
          targetId: live.id,
          targetPath: 'liveSessions/${live.id}',
          targetOwnerUid: live.hostUid,
          reporterUid: Get.find<AuthService>().uid,
          reason: choice.reason,
          details: choice.details,
          excerpt: live.title,
        ),
      );
      Get.snackbar(
        'Merci',
        'Votre signalement a été transmis à la modération.',
      );
    } catch (_) {
      Get.snackbar('Échec', 'Le signalement n’a pas pu être envoyé.');
    }
  }

  Future<void> _block(LiveSession live) async {
    final ok = await confirmAction(
      title: 'Bloquer ${live.hostName} ?',
      message:
          'Vous ne verrez plus ses lives ni ses publications, et vous ne '
          'pourrez plus échanger.',
      confirmLabel: 'Bloquer',
    );
    if (!ok) return;
    await Get.find<ModerationService>().blockUser(
      myUid: Get.find<AuthService>().uid,
      targetUid: live.hostUid,
      targetName: live.hostName,
    );
    Get.find<LiveViewerController>().removeCurrentPage();
  }
}

/// Dégradés haut et bas : le texte blanc reste lisible sur n'importe
/// quelle image.
class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x73000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0x8C000000),
            ],
            stops: [0, 0.2, 0.55, 1],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});
  final LiveWatchSession session;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final feed = session.feed.value;
      final live = feed?.live.value ?? session.initial;
      final viewers = feed?.viewers.values.toList() ?? const <LiveViewer>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: LiveHostCapsule(
                  name: live.hostName,
                  photo: live.hostPhoto,
                  likes: feed?.likes.value ?? live.likes,
                  trailing: _FollowButton(hostUid: live.hostUid),
                  onTap: () => Get.toNamed(
                    AppRoutes.userProfile,
                    arguments: live.hostUid,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              LiveAudience(
                viewers: viewers,
                count: feed?.viewerCount ?? live.viewers,
                onTap: feed == null ? null : () => _showAudience(feed),
              ),
              const SizedBox(width: 6),
              LiveRoundButton(
                icon: Icons.close_rounded,
                tooltip: 'Quitter le live',
                size: 32,
                onTap: Get.back,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              LiveElapsedBadge(startedAt: live.startedAt),
              const SizedBox(width: 8),
              // Lancer son propre live, même quand on en regarde un.
              const _GoLiveButton(compact: true),
            ],
          ),
        ],
      );
    });
  }

  void _showAudience(LiveFeed feed) {
    Get.bottomSheet<void>(
      SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(Get.context!).height * 0.5,
          child: Obx(() {
            final list = feed.viewers.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    '${feed.viewerCount} spectateur'
                    '${feed.viewerCount > 1 ? 's' : ''}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
                for (final v in list)
                  ListTile(
                    leading: UserAvatar(
                      name: v.name,
                      photoUrl: v.photo,
                      radius: 18,
                    ),
                    title: Text(
                      v.name,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                    onTap: () {
                      Get.back<void>();
                      Get.toNamed(AppRoutes.userProfile, arguments: v.uid);
                    },
                  ),
              ],
            );
          }),
        ),
      ),
      backgroundColor: AppColors.blackElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    );
  }
}

/// « Suivre » : disparaît une fois abonné.
class _FollowButton extends StatefulWidget {
  const _FollowButton({required this.hostUid});
  final String hostUid;

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool? _following;
  StreamSubscription<Object?>? _sub;

  String get _me => Get.find<AuthService>().uid;

  @override
  void initState() {
    super.initState();
    _sub = Get.find<FollowService>().watchFollowStatus(
      myUid: _me,
      targetUid: widget.hostUid,
      onData: (f) {
        if (mounted) setState(() => _following = f);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_following != false) return const SizedBox.shrink();
    return SizedBox(
      height: 30,
      child: FilledButton(
        onPressed: () {
          setState(() => _following = true);
          Get.find<FollowService>().follow(_me, widget.hostUid).catchError((
            Object _,
          ) {
            if (mounted) setState(() => _following = false);
          });
        },
        style: FilledButton.styleFrom(
          backgroundColor: liveRed,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: const Text('Suivre'),
      ),
    );
  }
}

class _EndedPage extends StatelessWidget {
  const _EndedPage({required this.live});
  final LiveSession? live;

  @override
  Widget build(BuildContext context) {
    return _MessagePage(
      live: live,
      icon: Icons.videocam_off_outlined,
      title: 'Ce live est terminé',
      body: live == null
          ? 'Il n’y a pas de live en cours pour le moment.'
          : 'Glissez vers le haut pour découvrir un autre live.',
      action: live == null ? const _GoLiveButton(label: true) : null,
    );
  }
}

class _FailedPage extends StatelessWidget {
  const _FailedPage({required this.live, required this.message});
  final LiveSession live;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return _MessagePage(
      live: live,
      icon: Icons.error_outline_rounded,
      title: 'Live indisponible',
      body: message ?? 'Connexion au live impossible.',
      action: const _GoLiveButton(label: true),
    );
  }
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({
    required this.live,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final LiveSession? live;
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (live != null)
          _Backdrop(live: live!, label: null)
        else
          const ColoredBox(color: AppColors.black),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topRight,
              child: LiveRoundButton(
                icon: Icons.close_rounded,
                tooltip: 'Fermer',
                onTap: Get.back,
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: AppColors.white),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.white.withValues(alpha: 0.8),
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 22), action!],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Passer à l'antenne depuis le lecteur. Remplace le lecteur plutôt que de
/// s'empiler dessus : on quitte le live regardé (salle LiveKit fermée)
/// avant d'ouvrir sa caméra.
class _GoLiveButton extends StatelessWidget {
  const _GoLiveButton({this.label = false, this.compact = false});

  /// Grand bouton avec libellé (page sans live).
  final bool label;

  /// Petite pastille « + LIVE » sous l'en-tête d'un live regardé.
  final bool compact;

  void _go() => Get.offNamed(AppRoutes.liveHost);

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Semantics(
        button: true,
        label: 'Lancer mon live',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: _go,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: liveGlass(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_rounded,
                  size: 15,
                  color: AppColors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  'Lancer mon live',
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: _go,
      icon: const Icon(Icons.videocam_rounded, size: 20),
      label: const Text('Lancer un live'),
      style: FilledButton.styleFrom(
        backgroundColor: liveRed,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Le bouton du panel, dans la barre du bas : il ouvre la feuille
/// « Rejoindre le LIVE » ; une demande en attente se voit (sablier orange).
class _JoinStageButton extends StatelessWidget {
  const _JoinStageButton({required this.session});
  final LiveWatchSession session;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final me = session.feed.value?.myGuest;
      final waiting = me?.status == LiveGuestStatus.requested;
      if (session.stageBusy.value) {
        return const SizedBox(
          width: 44,
          height: 44,
          child: Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.white,
            ),
          ),
        );
      }
      return LiveRoundButton(
        icon: waiting ? Icons.hourglass_top_rounded : Icons.group_add_rounded,
        tooltip: waiting ? 'Demande envoyée' : 'Rejoindre le panel',
        color: waiting ? AppColors.orangeDeep : null,
        size: 44,
        onTap: () => showJoinStageSheet(session),
      );
    });
  }
}

/// « Rejoindre le LIVE de Awa » : qui est déjà sur le panel, les places
/// libres, et le bouton pour demander — ou annuler sa demande. L'hôte
/// décide ; s'il accepte, on monte tout seul.
void showJoinStageSheet(LiveWatchSession session) {
  Get.bottomSheet<void>(
    SafeArea(
      child: Obx(() {
        final feed = session.feed.value;
        final live = session.live;
        final stage = feed?.stage ?? const <LiveGuest>[];
        final me = feed?.myGuest;
        final waiting = me?.status == LiveGuestStatus.requested;
        final full = stage.length >= LiveRules.maxGuests;
        final seats = <({String name, String? photo, bool host})>[
          (name: live.hostName, photo: live.hostPhoto, host: true),
          for (final g in stage) (name: g.name, photo: g.photo, host: false),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rejoindre le LIVE de ${live.hostName}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                waiting
                    ? 'Demande envoyée. Dès que ${live.hostName} accepte, vous '
                          'montez automatiquement sur le panel.'
                    : 'Demandez à monter : si ${live.hostName} accepte, votre '
                          'caméra et votre micro passent en direct.',
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.whiteMuted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (var i = 0; i < LiveRules.maxGuests + 1; i++)
                    Expanded(
                      child: Column(
                        children: [
                          if (i < seats.length) ...[
                            UserAvatar(
                              name: seats[i].name,
                              photoUrl: seats[i].photo,
                              radius: 24,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              seats[i].host ? 'Hôte' : seats[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: seats[i].host
                                    ? AppColors.orangeSoft
                                    : AppColors.white,
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.white.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                color: AppColors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Libre',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: AppColors.whiteMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              if (!waiting) ...[
                const SizedBox(height: 18),
                LiveCameraChoice(cameraOn: session.cameraOn),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: waiting
                    ? OutlinedButton(
                        onPressed: () {
                          Get.back<void>();
                          unawaited(session.cancelRequest());
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: Color(0x66FFFFFF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Annuler ma demande'),
                      )
                    : FilledButton.icon(
                        onPressed: full || feed == null
                            ? null
                            : () {
                                Get.back<void>();
                                unawaited(session.requestJoin());
                              },
                        icon: const Icon(Icons.group_add_rounded, size: 20),
                        label: Text(
                          full ? 'Panel complet' : 'Demander à rejoindre',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: liveRed,
                          disabledBackgroundColor: const Color(0x33FFFFFF),
                          foregroundColor: AppColors.white,
                          disabledForegroundColor: AppColors.whiteMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      }),
    ),
    backgroundColor: AppColors.blackElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
  );
}
