import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;

import '../../controllers/call_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/user_avatar.dart';

/// Écran plein cadre pour un appel — sonnerie entrante/sortante et
/// appel en cours, audio ou vidéo. Volontairement toujours en thème sombre
/// (comme la quasi-totalité des UI d'appel) quel que soit le thème choisi
/// dans l'app, pour un rendu immersif et lisible en plein soleil comme en
/// intérieur.
class CallScreen extends GetView<CallController> {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Pas de blocage du retour système ici : un `PopScope(canPop: false)`
    // qui rappelle `Get.back()` depuis son propre `onPopInvokedWithResult`
    // s'auto-bloque (chaque pop, y compris programmatique, redéclenche le
    // callback avec `didPop: false`) — l'écran ne se fermerait jamais. Le
    // nettoyage (statut Firestore + libération des flux) est à la place
    // garanti par `CallController.onClose`, quelle que soit la façon dont
    // l'écran se ferme (bouton raccrocher ou retour système).
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Obx(() {
        final phase = controller.phase.value;
        // `reconnecting` reste une communication en cours : on garde la vue
        // vidéo (dernière image figée) plutôt que de rebasculer sur l'écran
        // audio, ce qui ferait clignoter toute l'UI à chaque micro-coupure.
        final inCall =
            phase == CallScreenPhase.active ||
            phase == CallScreenPhase.reconnecting;
        if (inCall && controller.isGroup) {
          return _GroupCallBody(controller: controller);
        }
        if (inCall && controller.isVideoCall) {
          return _VideoCallBody(controller: controller);
        }
        return _VoiceCallBody(controller: controller);
      }),
    );
  }
}

class _VoiceCallBody extends StatelessWidget {
  const _VoiceCallBody({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final profile = controller.otherProfile.value;
      final name = profile?.displayName ?? 'Appel';
      final phase = controller.phase.value;

      return Stack(
        children: [
          Positioned.fill(child: _CallBackground()),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                Text(
                  _statusLabel(phase, controller),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.whiteMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                _Avatar(name: name),
                const SizedBox(height: 20),
                Text(
                  name,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 8),
                // Le chrono reste affiché pendant une reconnexion : la
                // communication n'est pas terminée, seul le média est
                // momentanément coupé — le masquer donnerait l'impression
                // que l'appel a raccroché.
                if (controller.wasEverConnected &&
                    (phase == CallScreenPhase.active ||
                        phase == CallScreenPhase.reconnecting))
                  Obx(
                    () => Text(
                      controller.formattedDuration,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.whiteMuted,
                      ),
                    ),
                  )
                else
                  Text(
                    controller.isVideoCall ? 'Appel vidéo' : 'Appel audio',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.whiteMuted,
                    ),
                  ),
                if (controller.errorMessage.value != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      controller.errorMessage.value!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.orangeSoft,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _ControlPanel(controller: controller),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      );
    });
  }

  String _statusLabel(CallScreenPhase phase, CallController c) {
    return switch (phase) {
      CallScreenPhase.ringingIncoming =>
        c.isVideoCall ? 'Appel vidéo entrant' : 'Appel entrant',
      CallScreenPhase.ringingOutgoing => 'Appel en cours…',
      CallScreenPhase.connecting => 'Connexion…',
      CallScreenPhase.active => 'En communication',
      CallScreenPhase.reconnecting => 'Reconnexion…',
      CallScreenPhase.ended => 'Appel terminé',
    };
  }
}

class _VideoCallBody extends StatelessWidget {
  const _VideoCallBody({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            final track = controller.remoteVideo.value;
            // Pas encore d'image, ou caméra coupée en face : fond d'appel
            // et initiale plutôt qu'un écran noir figé.
            if (track == null || controller.remoteCameraOff.value) {
              final name = controller.otherProfile.value?.displayName ?? '';
              return Stack(
                children: [
                  Positioned.fill(child: _CallBackground()),
                  Center(child: _Avatar(name: name)),
                ],
              );
            }
            return VideoTrackRenderer(
              track,
              key: ValueKey(track.sid),
              fit: VideoViewFit.cover,
              mirrorMode: VideoViewMirrorMode.off,
            );
          }),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 16,
          child: Obx(
            () => AnimatedOpacity(
              opacity: controller.isCameraOff.value ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 100,
                height: 140,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: switch (controller.localVideo.value) {
                  final track? => VideoTrackRenderer(
                    track,
                    fit: VideoViewFit.cover,
                    mirrorMode: controller.isFrontCamera.value
                        ? VideoViewMirrorMode.mirror
                        : VideoViewMirrorMode.off,
                  ),
                  null => const ColoredBox(color: AppColors.black),
                },
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: Obx(
            () => Text(
              controller.otherProfile.value?.displayName ?? '',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 12)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: SafeArea(
            top: false,
            child: _ControlPanel(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.orange.withValues(alpha: 0.85), AppColors.orangeDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

class _CallBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.2,
          colors: [AppColors.orange.withValues(alpha: 0.12), AppColors.black],
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final phase = controller.phase.value;

      if (phase == CallScreenPhase.ringingIncoming) {
        return _IncomingActions(controller: controller);
      }

      final errorMsg = controller.errorMessage.value;
      if (errorMsg != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Message technique laissé tel quel (pas reformulé) : sert de
              // diagnostic direct sur un téléphone de test sans console
              // attachée — voir CallController._startOutgoingCall/acceptCall.
              Text(
                errorMsg,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.whiteMuted,
                ),
              ),
              const SizedBox(height: 20),
              _HangUpButton(onTap: Get.back),
            ],
          ),
        );
      }

      final canInvite = controller.canInvite;
      // Cinq boutons en vidéo avec « Ajouter » : on resserre pour tenir sur
      // les petits écrans.
      final gap = canInvite && controller.isVideoCall ? 12.0 : 20.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CallButton(
                icon: controller.isMuted.value
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                active: controller.isMuted.value,
                onTap: controller.toggleMute,
              ),
              SizedBox(width: gap),
              if (controller.isVideoCall) ...[
                _CallButton(
                  icon: controller.isCameraOff.value
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  active: controller.isCameraOff.value,
                  onTap: controller.toggleCamera,
                ),
                SizedBox(width: gap),
                _CallButton(
                  icon: Icons.cameraswitch_rounded,
                  active: false,
                  onTap: controller.switchCamera,
                ),
              ] else
                _CallButton(
                  icon: controller.isSpeakerOn.value
                      ? Icons.volume_up_rounded
                      : Icons.hearing_rounded,
                  active: controller.isSpeakerOn.value,
                  onTap: controller.toggleSpeaker,
                ),
              if (canInvite) ...[
                SizedBox(width: gap),
                _CallButton(
                  icon: Icons.person_add_alt_1_rounded,
                  active: false,
                  onTap: () => _showInviteSheet(controller),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          _HangUpButton(onTap: controller.endCall),
        ],
      );
    });
  }
}

class _IncomingActions extends StatelessWidget {
  const _IncomingActions({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            GestureDetector(
              onTap: controller.declineCall,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: AppColors.white,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Refuser',
              style: GoogleFonts.manrope(
                color: AppColors.whiteMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Column(
          children: [
            GestureDetector(
              onTap: controller.acceptCall,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: AppColors.white,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Accepter',
              style: GoogleFonts.manrope(
                color: AppColors.whiteMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active
              ? AppColors.white
              : AppColors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? AppColors.black : AppColors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.orange,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: AppColors.white,
          size: 30,
        ),
      ),
    );
  }
}

/// Appel de groupe : une vignette par personne, la nôtre en premier.
class _GroupCallBody extends StatelessWidget {
  const _GroupCallBody({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _CallBackground()),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Obx(() {
                final present =
                    controller.tiles.where((t) => !t.ringing).length + 1;
                final reconnecting =
                    controller.phase.value == CallScreenPhase.reconnecting;
                return Text(
                  reconnecting
                      ? 'Reconnexion…'
                      : 'Appel de groupe · $present participant'
                            '${present > 1 ? 's' : ''} · '
                            '${controller.formattedDuration}',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.whiteMuted,
                  ),
                );
              }),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  final others = controller.tiles.toList();
                  final count = others.length + 1;
                  return LayoutBuilder(
                    builder: (context, box) {
                      final columns = count <= 2 ? 1 : 2;
                      final rows = (count / columns).ceil();
                      const spacing = 8.0;
                      final width =
                          (box.maxWidth - 16 - spacing * (columns - 1)) /
                          columns;
                      final height =
                          (box.maxHeight - spacing * (rows - 1)) / rows;
                      return GridView.count(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        crossAxisCount: columns,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        // Tout tient à l'écran jusqu'à 8 vignettes ; au-delà
                        // de la hauteur minimale, la grille défile.
                        childAspectRatio: width / height.clamp(120, 2000),
                        children: [
                          _SelfTile(controller: controller),
                          for (final t in others) _RemoteTile(tile: t),
                        ],
                      );
                    },
                  );
                }),
              ),
              Obx(() {
                final error = controller.errorMessage.value;
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.orangeSoft,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              _ControlPanel(controller: controller),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelfTile extends StatelessWidget {
  const _SelfTile({required this.controller});
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final cam = controller.localVideo.value;
      final showVideo = cam != null && !controller.isCameraOff.value;
      return _TileFrame(
        name: 'Vous',
        muted: controller.isMuted.value,
        child: showVideo
            ? VideoTrackRenderer(
                cam,
                fit: VideoViewFit.cover,
                mirrorMode: controller.isFrontCamera.value
                    ? VideoViewMirrorMode.mirror
                    : VideoViewMirrorMode.off,
              )
            : const _TileAvatar(name: 'Vous'),
      );
    });
  }
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({required this.tile});
  final CallTile tile;

  @override
  Widget build(BuildContext context) {
    final video = tile.video;
    return Opacity(
      opacity: tile.ringing ? 0.6 : 1,
      child: _TileFrame(
        name: tile.ringing ? '${tile.name} · appel…' : tile.name,
        speaking: tile.speaking,
        child: video != null && !tile.cameraOff
            ? VideoTrackRenderer(
                video,
                key: ValueKey(video.sid),
                fit: VideoViewFit.cover,
                mirrorMode: VideoViewMirrorMode.off,
              )
            : _TileAvatar(name: tile.name),
      ),
    );
  }
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.name,
    required this.child,
    this.speaking = false,
    this.muted = false,
  });

  final String name;
  final Widget child;
  final bool speaking;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        // Qui parle : liseré orange, comme le reste de l'app.
        border: Border.all(
          color: speaking
              ? AppColors.orange
              : AppColors.white.withValues(alpha: 0.08),
          width: speaking ? 3 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Row(
              children: [
                if (muted) ...[
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 14,
                    color: AppColors.white,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
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

class _TileAvatar extends StatelessWidget {
  const _TileAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: UserAvatar(
        name: name,
        radius: 32,
        backgroundColor: AppColors.orange.withValues(alpha: 0.85),
        foregroundColor: AppColors.white,
      ),
    );
  }
}

/// Choix de la personne à ajouter, parmi les conversations récentes.
void _showInviteSheet(CallController controller) {
  Get.bottomSheet(
    Container(
      constraints: BoxConstraints(maxHeight: Get.height * 0.7),
      decoration: const BoxDecoration(
        color: AppColors.blackElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: AppColors.whiteMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ajouter à l’appel',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Son téléphone va sonner.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.whiteMuted,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<InviteCandidate>>(
                future: controller.inviteCandidates(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: AppColors.orange,
                      ),
                    );
                  }
                  final people = snap.data ?? const <InviteCandidate>[];
                  if (snap.hasError || people.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        snap.hasError
                            ? 'Impossible de charger vos contacts.'
                            : 'Aucune autre conversation à ajouter.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: AppColors.whiteMuted,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: people.length,
                    itemBuilder: (context, i) {
                      final p = people[i];
                      return ListTile(
                        leading: UserAvatar(
                          name: p.name,
                          photoUrl: p.photoUrl,
                          radius: 22,
                        ),
                        title: Text(
                          p.name,
                          style: GoogleFonts.manrope(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.add_call,
                          color: AppColors.orange,
                        ),
                        onTap: () {
                          Get.back();
                          controller.invite(p);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    isScrollControlled: true,
  );
}
