import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import 'notification_launch_guard.dart';
import 'notification_router.dart';

/// Affiche une vraie notification système **pendant que l'app est au premier
/// plan** (FCM ne le fait que lorsqu'elle est en arrière-plan / tuée) et
/// route les taps.
///
/// Séparation nette avec FCM :
///  - app en arrière-plan / tuée → la couche FCM affiche elle-même la
///    bannière (les pushes de `functions/index.js` portent un bloc
///    `notification`) ; ce service ne fait rien.
///  - app au premier plan → `FirebaseMessaging.onMessage` (voir
///    [PushService]) appelle [showFromFcm], qui pose une notification locale
///    sur le bon canal Android, avec le même `payload` que la bannière
///    système pour que le tap aboutisse au même endroit.
class LocalNotificationsService extends GetxService {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Messages privés — importance haute (bannière + son).
  static const _messages = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Nouveaux messages privés',
    importance: Importance.high,
  );

  /// Activité sociale : J’aime, commentaires, nouveaux abonnés, publications.
  static const _social = AndroidNotificationChannel(
    'social',
    'Activité',
    description: 'J’aime, commentaires, abonnés et nouvelles publications',
    importance: Importance.defaultImportance,
  );

  /// Suivi des démarches — importance haute.
  ///
  /// Canal distinct de l'activité sociale, pour deux raisons. Un « votre
  /// dossier est prêt » doit s'afficher en bannière, pas se glisser
  /// silencieusement dans le tiroir. Et surtout, Android laisse couper un
  /// canal : quelqu'un qui fait taire les J'aime et les commentaires ne
  /// doit pas perdre du même geste les nouvelles de son dossier.
  ///
  /// L'importance d'un canal ne se change plus une fois qu'il existe sur
  /// l'appareil — d'où un identifiant neuf plutôt qu'un réglage de
  /// `social`, qui serait resté sans effet sur les installations en place.
  static const _demarches = AndroidNotificationChannel(
    'demarches',
    'Suivi des démarches',
    description: 'Avancement des dossiers déposés au guichet',
    importance: Importance.high,
  );

  /// Appels manqués (le canal par défaut du manifeste historique).
  static const _missedCalls = AndroidNotificationChannel(
    'missed_calls',
    'Appels manqués',
    description: 'Appels auxquels vous n’avez pas répondu',
    importance: Importance.high,
  );

  Future<LocalNotificationsService> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Les permissions sont déjà demandées par PushService via FCM — on ne
    // redemande pas ici pour ne pas afficher deux invites.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      for (final channel in const [
        _messages,
        _social,
        _missedCalls,
        _demarches,
      ]) {
        await androidImpl.createNotificationChannel(channel);
      }
    }

    // Filet de sécurité : app lancée par un tap sur une notification locale
    // encore présente dans le tiroir — une seule fois par tap (pas à chaque
    // hot restart de l'IDE).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch!.notificationResponse?.payload;
      if (payload != null &&
          payload.isNotEmpty &&
          await NotificationLaunchGuard.consumeIfNew(
            NotificationLaunchGuard.keyFromPayload(payload),
          )) {
        _routePayload(payload);
      }
    }

    return this;
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      NotificationLaunchGuard.markHandled(
        NotificationLaunchGuard.keyFromPayload(payload),
      );
    }
    _routePayload(payload);
  }

  void _routePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = (jsonDecode(payload) as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      NotificationRouter.routeFromData(data);
    } on Object catch (e) {
      developer.log('payload illisible', name: 'LocalNotifications', error: e);
    }
  }

  /// Pose une notification locale à partir d'un message FCM reçu au premier
  /// plan. L'`id` est stable par fil / publication : une conversation active
  /// remplace sa notification précédente plutôt que d'en empiler.
  Future<void> showFromFcm(RemoteMessage message) async {
    final n = message.notification;
    final data = message.data;
    final type = (data['type'] as String?) ?? '';

    final channel = switch (type) {
      'message' => _messages,
      'missed_call' || 'missedCall' => _missedCalls,
      'dossier' => _demarches,
      _ => _social,
    };

    final title = n?.title ?? (data['title'] as String?) ?? 'Foumbot Link';
    final body = n?.body ?? (data['body'] as String?) ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final tag =
        (data['conversationId'] ??
                data['postId'] ??
                data['followerUid'] ??
                data['senderUid'] ??
                type)
            .toString();

    await _plugin.show(
      tag.hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
