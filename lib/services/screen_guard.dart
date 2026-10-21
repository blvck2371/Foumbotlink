import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Interdit la capture d'écran tant qu'un contenu à vue unique est
/// affiché.
///
/// Côté Android, `MainActivity` pose `FLAG_SECURE` sur la fenêtre — les
/// captures, les enregistrements vidéo et l'aperçu dans les applications
/// récentes sont noircis — et interdit aux autres applications
/// d'enregistrer le son de celle-ci.
///
/// **iOS n'a pas d'équivalent** : le système n'offre aucun moyen
/// d'empêcher une capture. [acquire] y ouvre donc une *surveillance* au
/// lieu de verrouiller la fenêtre, et rend deux signaux de nature
/// différente :
///
///  - [isCaptured] dit qu'un enregistrement d'écran ou une recopie est en
///    cours. Il se sait **avant** que rien soit capté : l'affichage peut
///    masquer le contenu, et c'est une vraie protection.
///  - [onScreenshot] arrive **après** la capture. Plus rien à empêcher :
///    tout ce qui reste est de le dire à qui a envoyé le message.
///
/// Aucune de ces protections ne résiste à un second téléphone braqué sur
/// l'écran. Ne les promettez pas plus haut qu'elles ne portent.
class ScreenGuard {
  const ScreenGuard._();

  static const _channel = MethodChannel('foumbot/screen_guard');

  /// Nombre de contenus protégés affichés en ce moment.
  ///
  /// Un compteur, pas un booléen : un vocal à vue unique peut encore
  /// jouer quand on ouvre une photo à vue unique. Refermer la photo ne
  /// doit pas lever la protection que le vocal tient toujours.
  static int _holds = 0;

  /// Vrai tant qu'un enregistrement d'écran ou une recopie est en cours
  /// (iOS). Reste faux sur Android, où la fenêtre est verrouillée plutôt
  /// que surveillée : il n'y a rien à masquer, le système s'en charge.
  static final ValueNotifier<bool> isCaptured = ValueNotifier<bool>(false);

  static final _screenshots = StreamController<void>.broadcast();

  /// Une capture d'écran vient d'être prise (iOS). Jamais émis sur
  /// Android, où elle n'a pas pu avoir lieu.
  static Stream<void> get onScreenshot => _screenshots.stream;

  static bool _listening = false;

  static Future<void> acquire() async {
    _listen();
    _holds++;
    if (_holds == 1) await _send('secure');
  }

  static Future<void> release() async {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0) {
      await _send('unsecure');
      // Le natif l'annonce aussi en s'arrêtant ; on le remet ici pour que
      // l'état soit juste même si le message se perd.
      isCaptured.value = false;
    }
  }

  /// Branche l'écoute des signaux natifs, une fois pour toutes.
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'captured':
          isCaptured.value = call.arguments == true;
        case 'screenshot':
          _screenshots.add(null);
      }
      return null;
    });
  }

  /// Protège l'écran le temps de [body], y compris si elle échoue — une
  /// visionneuse qui plante ne doit pas laisser la fenêtre ouverte à la
  /// capture, ni la verrouiller pour toujours.
  static Future<T> guard<T>(Future<T> Function() body) async {
    await acquire();
    try {
      return await body();
    } finally {
      await release();
    }
  }

  static Future<void> _send(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // iOS, ou test sans hôte : rien à faire, et rien à signaler.
    } on PlatformException catch (e) {
      developer.log('Protection d’écran', name: 'ScreenGuard', error: e);
    }
  }
}
