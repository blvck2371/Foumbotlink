import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/call_controller.dart';
import '../controllers/chat_controller.dart';
import '../models/call.dart';
import '../routes/app_routes.dart';
import 'auth_service.dart';
import 'call_service.dart';
import 'callkit_helper.dart';
import 'local_notifications_service.dart';
import 'notification_launch_guard.dart';
import 'notification_router.dart';

/// Notifications push d'appel (FCM) + pont avec l'UI d'appel native
/// ([FlutterCallkitIncoming]).
///
/// - enregistre le token FCM de l'appareil dans `users/{uid}/private/push`
///   (doc privé), et le retire à la déconnexion ;
/// - à la réception d'un message `incoming_call` (premier plan ou
///   arrière-plan — l'app tuée passe par le handler de `main.dart`), lève
///   l'écran d'appel entrant CallKit ;
/// - écoute les évènements CallKit : « Répondre » ouvre l'écran d'appel
///   WebRTC existant, « Refuser » / expiration écrit le statut dans Firestore ;
/// - `call_cancelled` (l'appelant a raccroché, réponse ailleurs) coupe la
///   sonnerie.
///
/// Calqué sur [PresenceService] : `GetxService` permanent qui réagit à
/// `AuthService.firebaseUser` et fait des écritures `merge` tolérantes aux
/// erreurs.
class PushService extends GetxService {
  static const _prefEnabledKey = 'foumbotlink_push_enabled';

  final _db = FirebaseFirestore.instance;
  final _messaging = FirebaseMessaging.instance;

  StreamSubscription<CallEvent?>? _callkitSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  Worker? _authWorker;

  String? _currentToken;
  ({String route, dynamic args})? _pendingNavigation;

  /// Réception des notifications sur *cet* appareil, choix de
  /// l'utilisateur (écran Paramètres), conservé d'un lancement à l'autre.
  final pushEnabled = true.obs;

  /// Résolue quand la préférence a été relue du disque.
  ///
  /// Rien ne doit enregistrer de token avant : au lancement, la session
  /// Firebase est restaurée plus vite que `SharedPreferences` ne répond,
  /// et on réinscrirait alors un appareil que l'utilisateur venait
  /// justement de désinscrire.
  late final Future<void> _preferenceLoaded;

  AuthService get _auth => Get.find<AuthService>();
  CallService get _calls => Get.find<CallService>();

  DocumentReference<Map<String, dynamic>> _pushDoc(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('push');

  @override
  void onInit() {
    super.onInit();

    _preferenceLoaded = _restorePreference();

    _listenCallkitEvents();
    _handleColdStartAcceptedCall();

    _onMessageSub = FirebaseMessaging.onMessage.listen(_onMessage);
    _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationLaunchGuard.markHandled(
        NotificationLaunchGuard.keyFromFcm(message),
      );
      _onNotificationTap(message);
    });
    _messaging.getInitialMessage().then((message) async {
      if (message == null) return;
      final key = NotificationLaunchGuard.keyFromFcm(message);
      if (await NotificationLaunchGuard.consumeIfNew(key)) {
        _onNotificationTap(message);
      }
    });
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_saveToken);

    // iOS : laisser le système afficher la bannière même app au premier plan
    // (sur Android, FCM ne le fait jamais → on pose une notification locale,
    // voir _onMessage).
    if (GetPlatform.isIOS) {
      _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _authWorker = ever<User?>(_auth.firebaseUser, (user) {
      if (user != null) _registerToken();
    });

    _requestPermissions().then((_) {
      if (_auth.isSignedIn) _registerToken();
    });
  }

  @override
  void onClose() {
    _callkitSub?.cancel();
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    _tokenRefreshSub?.cancel();
    _authWorker?.dispose();
    super.onClose();
  }

  // -----------------------------------------------------------------------
  // Token FCM
  // -----------------------------------------------------------------------

  Future<void> _requestPermissions() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      if (GetPlatform.isAndroid) {
        // Android 13+ : permission POST_NOTIFICATIONS (sinon aucune UI
        // d'appel entrant ni notification d'appel manqué).
        await FlutterCallkitIncoming.requestNotificationPermission({
          'rationaleMessagePermission':
              'Autorisez les notifications pour recevoir les appels.',
          'postNotificationMessageRequired':
              'Activez les notifications dans les réglages pour recevoir les appels.',
        });
      }
    } on Object catch (e) {
      developer.log('requestPermissions', name: 'PushService', error: e);
    }
  }

  Future<void> _registerToken() async {
    await _preferenceLoaded;
    if (!pushEnabled.value) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } on Object catch (e) {
      developer.log('getToken', name: 'PushService', error: e);
    }
  }

  Future<void> _saveToken(String token) async {
    if (!_auth.isSignedIn || !pushEnabled.value) return;
    _currentToken = token;
    try {
      await _pushDoc(_auth.uid).set({
        'tokens': FieldValue.arrayUnion([token]),
        'platform': GetPlatform.isIOS ? 'ios' : 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      developer.log('saveToken', name: 'PushService', error: e);
    }
  }

  Future<void> _restorePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      pushEnabled.value = prefs.getBool(_prefEnabledKey) ?? true;
    } on Object catch (e) {
      developer.log('restorePreference', name: 'PushService', error: e);
    }
  }

  /// Active ou coupe les notifications sur cet appareil.
  ///
  /// Couper retire le token FCM du compte : l'appareil cesse vraiment de
  /// recevoir messages **et appels**, ce n'est pas qu'un masquage local.
  Future<void> setPushEnabled(bool value) async {
    if (pushEnabled.value == value) return;
    pushEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabledKey, value);
    } on Object catch (e) {
      developer.log('setPushEnabled', name: 'PushService', error: e);
    }
    if (value) {
      await _requestPermissions();
      await _registerToken();
    } else {
      await unregisterToken();
    }
  }

  /// À appeler à la déconnexion **avant** `AuthService.signOut()` (l'uid doit
  /// encore être disponible).
  Future<void> unregisterToken() async {
    if (!_auth.isSignedIn) return;
    try {
      // `getToken()` dans le `try` : sur un appareil sans Play Services,
      // ou sur iOS tant qu'APNs n'a pas répondu, il lève — et l'exception
      // remontait jusqu'à l'appelant, qui interrompait sa déconnexion.
      final token = _currentToken ?? await _messaging.getToken();
      if (token != null) {
        await _pushDoc(_auth.uid).set({
          'tokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      await _messaging.deleteToken();
    } on Object catch (e) {
      developer.log('unregisterToken', name: 'PushService', error: e);
    }
    _currentToken = null;
  }

  // -----------------------------------------------------------------------
  // Messages FCM (app vivante)
  // -----------------------------------------------------------------------

  Future<void> _onMessage(RemoteMessage message) async {
    final data = message.data;
    switch (data['type']) {
      case 'incoming_call':
        await showCallkitIncomingFromData(data);
      case 'call_cancelled':
        final callId = data['callId'] as String?;
        // Ce push est diffusé à *tous* les appareils de l'appelé dès que la
        // sonnerie s'arrête — y compris quand elle s'arrête parce que **cet**
        // appareil vient de décrocher. Le retirer sans ce filtre détruisait
        // l'UI d'appel native de l'appel en cours (et, sur iOS, la session
        // audio CallKit qui va avec) : l'appel se coupait juste après le
        // décroché. Seuls les *autres* appareils doivent cesser de sonner.
        if (_calls.isActiveCall(callId)) return;
        await dismissCallkit(callId);
      case 'message' ||
          'like' ||
          'comment' ||
          'follow' ||
          'post' ||
          'dossier' ||
          'missedCall' ||
          'missed_call':
        // iOS affiche déjà sa propre bannière au premier plan (voir
        // setForegroundNotificationPresentationOptions dans onInit).
        if (GetPlatform.isIOS) return;
        // Android : FCM n'affiche rien au premier plan — on pose nous-mêmes
        // une vraie notification système (canal adapté, même payload de tap).
        // Le flux complet reste par ailleurs dans l'écran Notifications,
        // alimenté en direct par Firestore.
        if (_isViewingConversationWith(data['senderUid'] as String?)) return;
        await Get.find<LocalNotificationsService>().showFromFcm(message);
    }
  }

  /// Vrai si l'écran de discussion ouvert est celui avec `senderUid` — on
  /// n'y notifie pas un message qu'on est déjà en train de lire (comme
  /// WhatsApp).
  bool _isViewingConversationWith(String? senderUid) {
    if (senderUid == null || senderUid.isEmpty) return false;
    if (Get.currentRoute != AppRoutes.chat) return false;
    if (!Get.isRegistered<ChatController>()) return false;
    return Get.find<ChatController>().peerUid == senderUid;
  }

  void _onNotificationTap(RemoteMessage message) =>
      NotificationRouter.routeFromData(message.data);

  // -----------------------------------------------------------------------
  // Évènements CallKit
  // -----------------------------------------------------------------------

  void _listenCallkitEvents() {
    _callkitSub = FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          _onAccept(callKitParams);
        case CallEventActionCallDecline(:final callKitParams):
          _calls.updateStatus(callKitParams.id, CallStatus.declined);
          dismissCallkit(callKitParams.id);
        case CallEventActionCallEnded(:final callKitParams):
          _onCallkitEnded(callKitParams.id);
        case CallEventActionCallTimeout(:final id):
          _calls.updateStatus(id, CallStatus.missed);
        case CallEventActionCallToggleMute(:final id, :final isMuted):
          // Micro coupé depuis l'UI système (écran verrouillé, CarPlay…) :
          // sans ce relais, l'icône de l'app et l'état réel de la piste
          // audio divergeaient.
          _syncMute(id, isMuted);
        default:
          break;
      }
    });
  }

  Future<void> _handleColdStartAcceptedCall() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final p in calls) {
        if (p.isAccepted) {
          _onAccept(p);
          return;
        }
      }
    } on Object catch (e) {
      developer.log('activeCalls', name: 'PushService', error: e);
    }
  }

  void _onAccept(CallKitParams params) {
    final extra = params.extra ?? const <String, dynamic>{};
    final callId = params.id;
    if (callId.isEmpty) return;

    _calls.markHandled(callId);

    final callType = (extra['callType'] as String?) ?? 'audio';
    _navigateWhenReady(AppRoutes.call, {
      'callId': callId,
      'incoming': true,
      'otherUid': extra['callerUid'] ?? '',
      'type': callType == 'video' ? CallType.video : CallType.audio,
      'conversationId': extra['conversationId'] ?? '',
      // L'utilisateur a déjà décroché dans l'UI système : l'écran d'appel
      // doit enchaîner sur la connexion, pas redemander « Accepter /
      // Refuser » (et refaire sonner le téléphone).
      'autoAccept': true,
    });
  }

  /// « Raccrocher » depuis l'UI d'appel native (écran verrouillé, bandeau
  /// système, bouton du casque). Sans ce relais, le bouton coupait l'UI
  /// CallKit mais laissait la session WebRTC — et le document Firestore —
  /// bien vivants côté correspondant.
  void _onCallkitEnded(String callId) {
    if (callId.isEmpty) return;
    // `CallController._teardown` retire lui-même l'appel de CallKit, ce qui
    // renvoie cet évènement en écho — le contrôleur est alors déjà en train
    // de se fermer et `endCall()` y est idempotent.
    final controller = _controllerFor(callId);
    if (controller != null) {
      controller.endCall();
      return;
    }
    // Aucun écran d'appel ouvert (raccroché depuis l'écran verrouillé avant
    // que l'app ne soit revenue au premier plan) : on ferme quand même
    // l'appel côté signalisation.
    _calls.updateStatus(callId, CallStatus.ended);
  }

  void _syncMute(String callId, bool muted) {
    final controller = _controllerFor(callId);
    if (controller != null && controller.isMuted.value != muted) {
      controller.toggleMute();
    }
  }

  /// Le contrôleur de l'écran d'appel, **si** il pilote bien `callId`.
  ///
  /// `Get.find` seul ne suffit pas : la liaison de route utilise `lazyPut`,
  /// donc un `find` sur un écran jamais ouvert instancierait un contrôleur
  /// sans `Get.arguments`. Et un évènement CallKit retardataire peut porter
  /// l'identifiant d'un appel précédent — l'appliquer à l'appel en cours
  /// raccrocherait la mauvaise conversation.
  CallController? _controllerFor(String callId) {
    if (!Get.isRegistered<CallController>()) return null;
    final controller = Get.find<CallController>();
    return controller.callId == callId ? controller : null;
  }

  // -----------------------------------------------------------------------
  // Navigation (résiste au démarrage à froid : le navigateur GetX n'est pas
  // prêt quand l'app est lancée par l'action « Répondre » de CallKit)
  // -----------------------------------------------------------------------

  void _navigateWhenReady(String route, dynamic args, [int tries = 0]) {
    _pendingNavigation = (route: route, args: args);
    _flush(tries);
  }

  void _flush(int tries) {
    final pending = _pendingNavigation;
    if (pending == null) return;

    final ready = Get.key.currentState != null;
    if (!ready) {
      if (tries > 40) {
        _pendingNavigation = null;
        return;
      }
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _flush(tries + 1),
      );
      return;
    }

    _pendingNavigation = null;
    if (pending.route == AppRoutes.call && Get.currentRoute == AppRoutes.call) {
      return;
    }
    Get.toNamed(pending.route, arguments: pending.args);
  }
}
