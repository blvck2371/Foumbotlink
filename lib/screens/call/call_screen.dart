import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/call_controller.dart';
import '../../theme/app_colors.dart';

/// Écran plein cadre pour un appel WebRTC — sonnerie entrante/sortante et
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
          child: RTCVideoView(
            controller.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: false,
          ),
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
                child: RTCVideoView(
                  controller.localRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: controller.isFrontCamera.value,
                ),
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
              const SizedBox(width: 20),
              if (controller.isVideoCall) ...[
                _CallButton(
                  icon: controller.isCameraOff.value
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  active: controller.isCameraOff.value,
                  onTap: controller.toggleCamera,
                ),
                const SizedBox(width: 20),
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
