import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../controllers/live_feed.dart';
import '../../controllers/live_host_controller.dart';
import '../../models/live_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/user_avatar.dart';
import 'live_widgets.dart';

/// L'antenne : aperçu, titre, « Passer en direct », puis le live et son
/// bilan.
class LiveHostScreen extends GetView<LiveHostController> {
  const LiveHostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Obx(() {
        final phase = controller.phase.value;
        final onAir =
            phase == LiveHostPhase.live || phase == LiveHostPhase.ending;
        return PopScope(
          // En direct, le retour demande confirmation : un geste de trop ne
          // doit pas couper le live de toute une audience.
          canPop: !onAir,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && phase == LiveHostPhase.live) _confirmEnd();
          },
          child: Scaffold(
            backgroundColor: AppColors.black,
            // Le clavier ne rétrécit pas l'image de la caméra.
            resizeToAvoidBottomInset: false,
            body: switch (phase) {
              LiveHostPhase.ended => _Summary(controller: controller),
              LiveHostPhase.failed => _Failure(controller: controller),
              _ => _Stage(controller: controller),
            },
          ),
        );
      }),
    );
  }

  Future<void> _confirmEnd() async {
    final ok = await confirmAction(
      title: 'Terminer le live ?',
      message: 'Vos spectateurs verront que le live est terminé.',
      confirmLabel: 'Terminer',
    );
    if (ok) await controller.endLive();
  }
}

/// La caméra en plein écran, avec par-dessus soit la préparation, soit
/// le live.
class _Stage extends StatelessWidget {
  const _Stage({required this.controller});
  final LiveHostController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final track = controller.camera.value;
      final phase = controller.phase.value;
      final feed = controller.feed.value;
      final onAir = phase == LiveHostPhase.live && feed != null;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (onAir)
            _HostStage(controller: controller, feed: feed)
          else if (track != null)
            VideoTrackRenderer(
              track,
              fit: VideoViewFit.cover,
              mirrorMode: controller.frontCamera.value
                  ? VideoViewMirrorMode.mirror
                  : VideoViewMirrorMode.off,
            )
          else
            const Center(child: FoumbotLoader()),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x73000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                  stops: [0, 0.2, 0.5, 1],
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
                child: onAir
                    ? _OnAir(controller: controller, feed: feed)
                    : _Setup(controller: controller),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Avant le direct : titre et bouton.
class _Setup extends StatelessWidget {
  const _Setup({required this.controller});
  final LiveHostController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            LiveRoundButton(
              icon: Icons.close_rounded,
              tooltip: 'Fermer',
              onTap: Get.back,
            ),
            const Spacer(),
            LiveRoundButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: 'Changer de caméra',
              onTap: controller.switchCamera,
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: liveGlass(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller.titleCtrl,
                maxLength: LiveRules.maxTitle,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                cursorColor: AppColors.orangeSoft,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterStyle: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.white.withValues(alpha: 0.6),
                  ),
                  hintText: 'Donnez un titre à votre live',
                  hintStyle: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Text(
                'Vos abonnés seront prévenus. Restez respectueux : un live '
                'signalé peut être coupé.',
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.white.withValues(alpha: 0.75),
                ),
              ),
              Obx(() {
                final error = controller.error.value;
                if (error == null) return const SizedBox(height: 14);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF8A80),
                    ),
                  ),
                );
              }),
              Obx(() {
                final phase = controller.phase.value;
                final busy = phase != LiveHostPhase.ready;
                return SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: busy ? null : controller.goLive,
                    style: FilledButton.styleFrom(
                      backgroundColor: liveRed,
                      disabledBackgroundColor: liveRed.withValues(alpha: 0.6),
                      foregroundColor: AppColors.white,
                      disabledForegroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: phase == LiveHostPhase.starting
                        ? const FoumbotLoader.button()
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sensors_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Passer en direct'),
                            ],
                          ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

/// En direct : barre du haut, commentaires, cœurs, actions.
class _OnAir extends StatelessWidget {
  const _OnAir({required this.controller, required this.feed});
  final LiveHostController controller;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Obx(() {
          final live = feed.live.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (live != null) LiveHostChip(live: live),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        LiveBadge(elapsed: controller.elapsed.value),
                        if (controller.reconnecting.value) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: liveGlass(6),
                            child: Text(
                              'Reconnexion…',
                              style: GoogleFonts.manrope(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ViewersPill(
                count: live?.viewers ?? 0,
                onTap: () => _showViewers(),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () => _confirmEnd(),
                  style: FilledButton.styleFrom(
                    backgroundColor: liveRed,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                    textStyle: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Terminer'),
                ),
              ),
            ],
          );
        }),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: SizedBox(
                height: liveFeedHeight(context),
                child: LiveCommentsList(
                  feed: feed,
                  hostUid: feed.me.uid,
                  onLongPress: _commentActions,
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
            Obx(
              () => LiveRoundButton(
                icon: controller.micOn.value
                    ? Icons.mic_none_rounded
                    : Icons.mic_off_rounded,
                tooltip: controller.micOn.value
                    ? 'Couper le micro'
                    : 'Rallumer le micro',
                color: controller.micOn.value ? null : liveRed,
                size: 44,
                onTap: controller.toggleMic,
              ),
            ),
            LiveRoundButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: 'Changer de caméra',
              size: 44,
              onTap: controller.switchCamera,
            ),
            Obx(() {
              final requests = feed.guests.values
                  .where((g) => g.status == LiveGuestStatus.requested)
                  .length;
              return LiveCountBadge(
                count: requests,
                child: LiveRoundButton(
                  icon: Icons.group_add_outlined,
                  tooltip: 'Invités du live',
                  size: 44,
                  onTap: () => showGuestsPanel(controller, feed),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmEnd() async {
    final ok = await confirmAction(
      title: 'Terminer le live ?',
      message: 'Vos spectateurs verront que le live est terminé.',
      confirmLabel: 'Terminer',
    );
    if (ok) await controller.endLive();
  }

  Future<void> _commentActions(LiveComment c) async {
    final mine = c.uid == feed.me.uid;
    final choice = await showLiveSheet<String>(
      title: '${c.name} : ${c.text}',
      options: [
        (
          icon: Icons.delete_outline_rounded,
          label: 'Supprimer ce message',
          value: 'delete',
          danger: false,
        ),
        if (!mine)
          (
            icon: Icons.person_remove_outlined,
            label: 'Retirer ${c.name} du live',
            value: 'expel',
            danger: true,
          ),
      ],
    );
    if (choice == 'delete') {
      await feed.deleteComment(c.id);
    } else if (choice == 'expel') {
      await _expel(LiveViewer(uid: c.uid, name: c.name, photo: c.photo));
    }
  }

  Future<void> _expel(LiveViewer v) async {
    final ok = await confirmAction(
      title: 'Retirer ${v.name} ?',
      message:
          'Ses messages sont effacés et il ne pourra plus revenir dans ce '
          'live.',
      confirmLabel: 'Retirer',
    );
    if (ok) await controller.expel(v);
  }

  void _showViewers() {
    Get.bottomSheet<void>(
      SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(Get.context!).height * 0.55,
          child: Obx(() {
            final list = feed.viewers.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    list.isEmpty
                        ? 'Personne pour l’instant'
                        : '${list.length} spectateur${list.length > 1 ? 's' : ''}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
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
                          trailing: TextButton(
                            onPressed: () {
                              Get.back<void>();
                              unawaited(_expel(v));
                            },
                            child: Text(
                              'Retirer',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFFF6B6B),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});
  final LiveHostController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.summary.value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 52,
              color: AppColors.orangeSoft,
            ),
            const SizedBox(height: 16),
            Text(
              s?.stoppedByServer == true
                  ? 'Votre live a été arrêté'
                  : 'Live terminé',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
            if (s?.stoppedByServer == true) ...[
              const SizedBox(height: 8),
              Text(
                'La connexion a été perdue trop longtemps, ou le live a été '
                'coupé par la modération.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.whiteMuted,
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                _Stat(
                  label: 'Durée',
                  value: LiveRules.elapsed(s?.duration ?? Duration.zero),
                ),
                _Stat(
                  label: 'Spectateurs max.',
                  value: LiveRules.compactCount(s?.peakViewers ?? 0),
                ),
                _Stat(
                  label: 'Cœurs',
                  value: LiveRules.compactCount(s?.likes ?? 0),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: Get.back,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orangeDeep,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              color: AppColors.whiteMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.controller});
  final LiveHostController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: LiveRoundButton(
                icon: Icons.close_rounded,
                tooltip: 'Fermer',
                onTap: Get.back,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.videocam_off_outlined,
              size: 48,
              color: AppColors.white,
            ),
            const SizedBox(height: 16),
            Obx(
              () => Text(
                controller.error.value ?? 'Le live n’a pas pu démarrer.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.45,
                  color: AppColors.white,
                ),
              ),
            ),
            const Spacer(),
            Obx(
              () => SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: controller.needsSettings.value
                      ? openAppSettings
                      : controller.prepare,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orangeDeep,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(
                    controller.needsSettings.value
                        ? 'Ouvrir les réglages'
                        : 'Réessayer',
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

/// Le plateau de l'hôte : sa caméra, puis ses invités. Toucher un invité
/// ouvre ce que l'hôte peut faire de lui.
class _HostStage extends StatelessWidget {
  const _HostStage({required this.controller, required this.feed});
  final LiveHostController controller;
  final LiveFeed feed;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final live = feed.live.value;
      final videos = controller.media.videos;
      final micOff = controller.media.micOff;
      final tiles = <LiveStageTile>[
        LiveStageTile(
          uid: feed.me.uid,
          name: live?.hostName ?? feed.me.name,
          photo: feed.me.photo,
          track: controller.camera.value,
          mirror: controller.frontCamera.value,
          micOff: !controller.micOn.value,
          isHost: true,
        ),
        for (final g in feed.stage)
          LiveStageTile(
            uid: g.uid,
            name: g.name,
            photo: g.photo,
            track: videos[g.uid],
            micOff: g.mutedByHost || micOff.contains(g.uid),
          ),
      ];
      return LiveStageGrid(
        tiles: tiles,
        onTapTile: (t) {
          final g = feed.guests[t.uid];
          if (g != null) unawaited(guestActions(controller, g));
        },
        onTapSeat: () => showGuestsPanel(controller, feed),
        fallback: const Center(child: FoumbotLoader()),
      );
    });
  }
}

/// Ce que l'hôte peut faire d'un invité du panel : couper ou rendre son
/// micro, le faire descendre, ou le retirer du live.
Future<void> guestActions(LiveHostController controller, LiveGuest g) async {
  final choice = await showLiveSheet<String>(
    title: g.name,
    options: [
      (
        icon: g.mutedByHost ? Icons.mic_none_rounded : Icons.mic_off_rounded,
        label: g.mutedByHost ? 'Rendre le micro' : 'Couper le micro',
        value: 'mic',
        danger: false,
      ),
      (
        icon: Icons.south_rounded,
        label: 'Faire descendre du panel',
        value: 'down',
        danger: false,
      ),
      (
        icon: Icons.person_remove_outlined,
        label: 'Retirer ${g.name} du live',
        value: 'expel',
        danger: true,
      ),
    ],
  );
  switch (choice) {
    case 'mic':
      await controller.toggleGuestMic(g);
    case 'down':
      await controller.removeFromStage(g.uid);
    case 'expel':
      final ok = await confirmAction(
        title: 'Retirer ${g.name} ?',
        message:
            'Ses messages sont effacés et il ne pourra plus revenir dans ce '
            'live.',
        confirmLabel: 'Retirer',
      );
      if (ok) {
        await controller.expel(
          LiveViewer(uid: g.uid, name: g.name, photo: g.photo),
        );
      }
  }
}

/// Le panneau « Invités » de l'hôte : les demandes à accepter, ceux qui
/// sont sur le panel, et les spectateurs à inviter.
void showGuestsPanel(LiveHostController controller, LiveFeed feed) {
  TextStyle section() => GoogleFonts.manrope(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.4,
    color: AppColors.whiteMuted,
  );
  TextStyle name() =>
      GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.white);
  Widget small(String label, VoidCallback onTap, {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: primary
            ? FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: liveRed,
                  foregroundColor: AppColors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(label),
              )
            : TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(label),
              ),
      );

  Get.bottomSheet<void>(
    SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(Get.context!).height * 0.6,
        child: Obx(() {
          final guests = feed.guests;
          final requests =
              guests.values
                  .where((g) => g.status == LiveGuestStatus.requested)
                  .toList()
                ..sort((a, b) => a.at.compareTo(b.at));
          final stage = feed.stage;
          final full = stage.length >= LiveRules.maxGuests;
          final viewers =
              feed.viewers.values
                  .where((v) => guests[v.uid]?.onStage != true)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  'Invités du live',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '${stage.length}/${LiveRules.maxGuests} places occupées sur '
                  'le panel',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.whiteMuted,
                  ),
                ),
              ),
              if (requests.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text('DEMANDES', style: section()),
                ),
                for (final g in requests)
                  ListTile(
                    leading: UserAvatar(
                      name: g.name,
                      photoUrl: g.photo,
                      radius: 18,
                    ),
                    title: Text(g.name, style: name()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        small('Refuser', () => controller.reject(g.uid)),
                        small(
                          'Accepter',
                          () => full
                              ? Get.snackbar(
                                  'Panel complet',
                                  'Faites d’abord descendre un invité.',
                                )
                              : controller.approve(g.uid),
                          primary: true,
                        ),
                      ],
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('SUR LE PANEL', style: section()),
              ),
              if (stage.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    'Personne pour l’instant. Invitez un spectateur ci-dessous.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.whiteMuted,
                    ),
                  ),
                ),
              for (final g in stage)
                ListTile(
                  leading: UserAvatar(
                    name: g.name,
                    photoUrl: g.photo,
                    radius: 18,
                  ),
                  title: Text(g.name, style: name()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: g.mutedByHost
                            ? 'Rendre le micro'
                            : 'Couper le micro',
                        onPressed: () => controller.toggleGuestMic(g),
                        icon: Icon(
                          g.mutedByHost
                              ? Icons.mic_off_rounded
                              : Icons.mic_none_rounded,
                          color: g.mutedByHost
                              ? const Color(0xFFFF6B6B)
                              : AppColors.white,
                        ),
                      ),
                      small(
                        'Faire descendre',
                        () => controller.removeFromStage(g.uid),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('SPECTATEURS', style: section()),
              ),
              if (viewers.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    'Aucun spectateur pour l’instant.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.whiteMuted,
                    ),
                  ),
                ),
              for (final v in viewers)
                ListTile(
                  leading: UserAvatar(
                    name: v.name,
                    photoUrl: v.photo,
                    radius: 18,
                  ),
                  title: Text(v.name, style: name()),
                  trailing: switch (guests[v.uid]?.status) {
                    LiveGuestStatus.invited => Text(
                      'Invité',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.orangeSoft,
                      ),
                    ),
                    LiveGuestStatus.requested => const SizedBox.shrink(),
                    _ => small(
                      'Inviter',
                      () => full
                          ? Get.snackbar(
                              'Panel complet',
                              'Faites d’abord descendre un invité.',
                            )
                          : controller.invite(v.uid),
                      primary: true,
                    ),
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
