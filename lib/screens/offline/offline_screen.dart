import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/connectivity_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';

/// Page affichée par-dessus l'app quand l'appareil n'atteint plus
/// Internet — voir [ConnectivityGate], qui décide de la montrer.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key, this.onRetry, this.onContinue});

  /// Relance une sonde réseau. `null` = pas de bouton (aperçu, tests).
  final VoidCallback? onRetry;

  /// Referme la page sans attendre le retour du réseau — voir
  /// [ConnectivityGate] : une partie du contenu déjà chargé reste
  /// consultable depuis le cache Firestore.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Scaffold(
      backgroundColor: isDark ? AppColors.black : AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange.withValues(
                      alpha: isDark ? 0.16 : 0.10,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 52,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Pas de connexion',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Foumbot Link n’arrive pas à joindre Internet. '
                  'Vérifiez votre Wi-Fi ou vos données mobiles, puis '
                  'réessayez.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.5,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 28),
                if (onRetry != null)
                  SizedBox(
                    width: double.infinity,
                    child: _RetryButton(onRetry: onRetry!),
                  ),
                if (onContinue != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onContinue,
                    child: Text(
                      'Continuer hors connexion',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                  Text(
                    'Le contenu déjà chargé reste consultable.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(fontSize: 12, color: muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton « Réessayer » qui montre la sonde en cours quand le service de
/// connectivité est là — c'est le seul retour visible qu'a la personne
/// pendant les quelques secondes que dure l'essai.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ConnectivityService>()) {
      return ElevatedButton(onPressed: onRetry, child: const Text('Réessayer'));
    }
    final checking = Get.find<ConnectivityService>().isChecking;
    return Obx(
      () => ElevatedButton(
        onPressed: checking.value ? null : onRetry,
        child: checking.value
            ? const FoumbotLoader.button()
            : const Text('Réessayer'),
      ),
    );
  }
}

/// Pose [OfflineScreen] par-dessus toute l'app dès que la connexion est
/// perdue, et la retire dès qu'elle revient.
///
/// Monté dans le `builder` de `GetMaterialApp` plutôt que poussé comme
/// route : la coupure peut survenir n'importe où — en pleine conversation,
/// dans la visionneuse de photos — et l'écran doit se retirer tout seul au
/// retour du réseau, sans dépiler ce que la personne était en train de
/// faire.
class ConnectivityGate extends StatefulWidget {
  const ConnectivityGate({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  final _dismissed = false.obs;
  Worker? _worker;

  /// `null` quand le service n'est pas enregistré : le portillon s'efface
  /// alors complètement et rend l'app telle quelle. C'est le cas des tests
  /// de widgets, qui ne doivent pas se mettre à sonder le réseau — et
  /// mieux vaut une app sans page hors-connexion qu'une app qui refuse de
  /// démarrer.
  ConnectivityService? _connectivity;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<ConnectivityService>()) return;
    final connectivity = _connectivity = Get.find<ConnectivityService>();
    // Un retour du réseau réarme la page : la coupure suivante doit se
    // revoir, même si la précédente avait été mise de côté.
    _worker = ever<bool>(connectivity.online, (online) {
      if (online) _dismissed.value = false;
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // L'`Obx` enveloppe la pile entière : un `Positioned` doit être fils
    // direct d'un `Stack`, il ne peut pas être rendu depuis un `Obx`
    // intercalé. `widget.child` reste la même instance d'une
    // reconstruction à l'autre — l'app dessous n'est donc pas remontée et
    // ne perd rien de son état.
    final connectivity = _connectivity;
    if (connectivity == null) return widget.child;

    return Obx(() {
      final offline = !connectivity.online.value && !_dismissed.value;
      return Stack(
        // `StackFit.expand` : un enfant non positionné reçoit sinon des
        // contraintes lâches, et l'app dessous ne saurait plus quelle
        // hauteur prendre.
        fit: StackFit.expand,
        children: [
          widget.child,
          if (offline)
            Positioned.fill(
              child: OfflineScreen(
                onRetry: connectivity.check,
                onContinue: () => _dismissed.value = true,
              ),
            ),
        ],
      );
    });
  }
}
