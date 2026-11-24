import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/live_service.dart';
import '../services/moderation_service.dart';
import '../services/profile_gate.dart';
import '../theme/app_colors.dart';

/// Ouvre un live en plein écran, directement sur celui demandé ; glisser
/// mène ensuite aux autres lives en cours.
Future<void> watchLive(String liveId) async {
  // Le serveur refuse l'entrée d'un live sans profil complété.
  if (!await ProfileGate.ensure(reason: 'Pour regarder un live')) return;
  await Get.toNamed(
    AppRoutes.liveViewer,
    arguments: {'liveId': liveId},
    preventDuplicates: false,
  );
}

/// Anneau orange « LIVE » autour de la photo de quelqu'un qui est en
/// direct, comme sur TikTok : il pulse, porte une pastille « LIVE », et un
/// appui ouvre directement son live.
///
/// Sans live en cours, rien ne change : [child] (passé à [orElse] s'il est
/// fourni) est rendu tel quel, et les gestes du parent (ouvrir le profil…) restent
/// actifs. Suit [LiveService.lives] en temps réel : l'anneau apparaît
/// quand le live démarre et disparaît quand il finit.
class LiveRing extends StatelessWidget {
  const LiveRing({
    super.key,
    required this.uid,
    required this.radius,
    required this.child,
    this.orElse,
    this.thickness,
  });

  /// Compte dont on cherche le live.
  final String uid;

  /// Rayon de l'avatar entouré.
  final double radius;

  /// L'avatar (de rayon [radius]).
  final Widget child;

  /// Habillage hors live — par exemple l'anneau des statuts autour de
  /// l'avatar. En live, l'anneau du live le remplace.
  final Widget Function(Widget avatar)? orElse;

  final double? thickness;

  @override
  Widget build(BuildContext context) {
    final fallback = orElse?.call(child) ?? child;
    if (uid.isEmpty || !Get.isRegistered<LiveService>()) return fallback;
    final service = Get.find<LiveService>();
    final moderation = Get.isRegistered<ModerationService>()
        ? Get.find<ModerationService>()
        : null;

    return Obx(() {
      final live = service.lives.firstWhereOrNull((l) => l.hostUid == uid);
      if (live == null || (moderation?.hides(uid) ?? false)) return fallback;

      final auth = Get.find<AuthService>();
      // Son propre live ne se « regarde » pas (ce serait une seconde
      // connexion à son nom) : l'anneau s'affiche, sans ouvrir le lecteur.
      final mine = auth.isSignedIn && auth.uid == uid;
      final ring = _PulsingLiveRing(
        radius: radius,
        thickness: thickness ?? (radius >= 30 ? 3 : 2.2),
        child: child,
      );
      if (mine) return ring;
      return Semantics(
        button: true,
        label: 'En direct : ouvrir le live de ${live.hostName}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => watchLive(live.id),
          child: ring,
        ),
      );
    });
  }
}

class _PulsingLiveRing extends StatefulWidget {
  const _PulsingLiveRing({
    required this.radius,
    required this.thickness,
    required this.child,
  });

  final double radius;
  final double thickness;
  final Widget child;

  @override
  State<_PulsingLiveRing> createState() => _PulsingLiveRingState();
}

class _PulsingLiveRingState extends State<_PulsingLiveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.07,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // « Réduire les animations » : anneau fixe.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    final t = widget.thickness;
    final gap = t;
    final size = (r + gap + t) * 2;
    final showLabel = r >= 16;
    final labelSize = (r * 0.3).clamp(8.0, 12.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.orange, width: t),
              ),
            ),
          ),
          widget.child,
          if (showLabel)
            Positioned(
              bottom: -labelSize * 0.55,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: labelSize * 0.5,
                  vertical: labelSize * 0.12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(labelSize * 0.4),
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.manrope(
                    fontSize: labelSize,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
