import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../controllers/home_controller.dart';
import '../routes/app_routes.dart';

/// Aiguillage unique de tous les « taps » sur une notification, quelle que
/// soit sa provenance :
///
///  - bannière système FCM (app en arrière-plan / tuée) →
///    `FirebaseMessaging.onMessageOpenedApp` / `getInitialMessage`
///  - notification locale affichée par [LocalNotificationsService] pendant
///    que l'app est au premier plan → `onDidReceiveNotificationResponse`
///  - ligne de l'écran Notifications (flux Firestore) → `NotificationsController.open`
///
/// Toutes convergent ici avec la même forme de données (`{type, …ids}`,
/// calquée sur `functions/index.js`). L'aiguilleur calcule la destination
/// puis navigue — en différant tant que le navigateur n'est pas prêt
/// (démarrage à froid déclenché par le tap) et en garantissant que `home`
/// est dans la pile, car les écrans de détail (publication, profil…)
/// dépendent de `HomeController`.
class NotificationRouter {
  NotificationRouter._();

  static ({String route, dynamic args})? _pending;

  /// Anti-doublon : `onMessageOpenedApp` + `getInitialMessage`, ou le tap
  /// FCM + les `notificationAppLaunchDetails` de flutter_local_notifications
  /// sur iOS, peuvent livrer le **même** tap deux fois de suite.
  static String? _lastKey;
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// `data` = la map `data` d'un message FCM, ou son équivalent construit à
  /// partir d'un `AppNotification` Firestore.
  static void routeFromData(Map<String, dynamic> data) {
    final dest = _destinationFor(data);
    if (dest == null) {
      developer.log(
        'aucune destination pour ${data['type']}',
        name: 'NotificationRouter',
      );
      return;
    }

    final key = '${dest.route}|${dest.args}';
    final now = DateTime.now();
    if (key == _lastKey &&
        now.difference(_lastAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastKey = key;
    _lastAt = now;

    _pending = dest;
    _flush(0);
  }

  static ({String route, dynamic args})? _destinationFor(
    Map<String, dynamic> d,
  ) {
    switch (d['type']) {
      case 'message':
      case 'missed_call':
      case 'missedCall':
        final other =
            (d['senderUid'] ?? d['callerUid'] ?? d['fromUid']) as String?;
        if (other != null && other.isNotEmpty) {
          return (route: AppRoutes.chat, args: {'otherUid': other});
        }
      case 'like':
      case 'comment':
      case 'post':
      case 'mention':
        final postId = d['postId'] as String?;
        if (postId != null && postId.isNotEmpty) {
          return (route: AppRoutes.feedPost, args: postId);
        }
      case 'marketAlert':
        final itemId = d['itemId'] as String?;
        if (itemId != null && itemId.isNotEmpty) {
          return (route: AppRoutes.marketDetail, args: itemId);
        }
      case 'dossier':
        final dossierId = d['dossierId'] as String?;
        if (dossierId != null && dossierId.isNotEmpty) {
          return (route: AppRoutes.dossierDetail, args: dossierId);
        }
        // Sans identifiant exploitable, la liste vaut mieux que rien :
        // le dossier qui vient de bouger y est en tête.
        return (route: AppRoutes.dossiers, args: null);
      case 'follow':
        final follower = (d['followerUid'] ?? d['fromUid']) as String?;
        if (follower != null && follower.isNotEmpty) {
          return (route: AppRoutes.userProfile, args: follower);
        }
      case 'moderation':
        return (route: AppRoutes.moderation, args: null);
      case 'live':
        final liveId = d['liveId'] as String?;
        if (liveId != null && liveId.isNotEmpty) {
          return (route: AppRoutes.liveViewer, args: {'liveId': liveId});
        }
        return (route: AppRoutes.lives, args: null);
      case 'echeance':
        // « Mes échéances » est en tête de l'écran Démarches.
        return (route: AppRoutes.demarches, args: null);
      case 'certification':
        return (route: AppRoutes.editProfile, args: null);
      // 'appUpdate' : purement informatif, aucune navigation.
    }
    return null;
  }

  static void _flush(int tries) {
    final pending = _pending;
    if (pending == null) return;

    final navReady = Get.key.currentState != null;
    final route = Get.currentRoute;

    // Tant que le splash n'a pas tranché (onboarding / auth / home), on
    // attend : les écrans de détail supposent `HomeController` présent.
    final settled =
        navReady &&
        route.isNotEmpty &&
        route != AppRoutes.splash &&
        route != AppRoutes.onboarding;

    if (!settled) {
      // ~60 s de patience : le temps qu'un démarrage à froid traverse
      // splash → (onboarding) → home avant d'ouvrir la cible.
      if (tries > 240) {
        developer.log(
          'navigateur jamais prêt, abandon',
          name: 'NotificationRouter',
        );
        _pending = null;
        return;
      }
      Future.delayed(
        const Duration(milliseconds: 250),
        () => _flush(tries + 1),
      );
      return;
    }

    _pending = null;

    // Démarrage à froid retombé sur l'écran de connexion : l'utilisateur
    // devra d'abord se connecter, il retrouvera l'info dans son flux de
    // notifications. On n'insiste pas.
    if (route == AppRoutes.auth) return;

    // `home` absent de la pile (cas résiduel) : on le pose d'abord, puis on
    // empile l'écran cible une fois `HomeBinding` installé.
    if (!Get.isRegistered<HomeController>()) {
      Get.offAllNamed(AppRoutes.home);
      Future.delayed(const Duration(milliseconds: 350), () {
        Get.toNamed(pending.route, arguments: pending.args);
      });
      return;
    }

    // Déjà sur une discussion : on remplace pour ouvrir la bonne plutôt que
    // d'empiler un second écran de chat.
    if (pending.route == AppRoutes.chat && Get.currentRoute == AppRoutes.chat) {
      Get.offNamed(pending.route, arguments: pending.args);
      return;
    }

    Get.toNamed(pending.route, arguments: pending.args);
  }
}
