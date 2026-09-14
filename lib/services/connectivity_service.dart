import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Sait si l'appareil atteint réellement Internet.
///
/// On ouvre une socket vers l'hôte Firestore plutôt que de demander au
/// système « y a-t-il du Wi-Fi ? » : à Foumbot, être associé à une borne ou
/// avoir des barres de réseau ne veut pas dire que les données passent
/// (portail captif, forfait épuisé, cellule saturée). Seule une connexion
/// qui aboutit prouve que l'app peut travailler — et c'est exactement
/// l'hôte dont elle a besoin.
///
/// Aucune dépendance ajoutée pour ça : `dart:io` suffit, et un paquet de
/// connectivité aurait de toute façon répondu sur l'interface réseau, pas
/// sur l'accès réel.
class ConnectivityService extends GetxService {
  static const _probeHost = 'firestore.googleapis.com';
  static const _probePort = 443;

  /// Au-delà, on considère que ça ne passe pas. Volontairement court : une
  /// connexion qui met plus de quelques secondes à s'établir ne permettra
  /// de toute façon pas de charger le fil.
  static const _probeTimeout = Duration(seconds: 4);

  /// Rythme de vérification. Serré hors ligne — c'est le moment où l'on
  /// attend le retour du réseau —, espacé une fois connecté pour ne pas
  /// réveiller la radio pour rien.
  static const _onlineInterval = Duration(seconds: 25);
  static const _offlineInterval = Duration(seconds: 5);

  /// Optimiste au démarrage : afficher la page « hors connexion » le temps
  /// de la première sonde ferait clignoter l'app à chaque lancement, y
  /// compris sur un réseau parfaitement valide.
  final online = true.obs;

  /// Vrai pendant une sonde — le bouton « Réessayer » s'en sert pour
  /// montrer qu'il travaille.
  final isChecking = false.obs;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  void onInit() {
    super.onInit();
    // Au retour de veille, l'état date d'avant la mise en arrière-plan :
    // on revérifie tout de suite plutôt que d'attendre le prochain tour.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    unawaited(check());
  }

  /// Sonde le réseau et met [online] à jour. Renvoie l'état constaté.
  Future<bool> check() async {
    if (isChecking.value) return online.value;
    isChecking.value = true;
    try {
      final socket = await Socket.connect(
        _probeHost,
        _probePort,
        timeout: _probeTimeout,
      );
      socket.destroy();
      _setOnline(true);
    } on SocketException catch (e) {
      developer.log('Sonde réseau', name: 'ConnectivityService', error: e);
      _setOnline(false);
    } on TimeoutException {
      _setOnline(false);
    } finally {
      isChecking.value = false;
      _scheduleNext();
    }
    return online.value;
  }

  void _setOnline(bool value) {
    if (online.value != value) online.value = value;
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(
      online.value ? _onlineInterval : _offlineInterval,
      () => unawaited(check()),
    );
  }

  @override
  void onClose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.onClose();
  }
}
