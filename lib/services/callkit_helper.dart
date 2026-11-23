import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Affiche l'écran d'appel entrant natif (CallKit sur iOS, UI plein écran sur
/// Android) à partir d'un payload FCM `type == incoming_call`.
///
/// Volontairement isolé, sans dépendance GetX/Firebase, pour être appelable
/// aussi bien depuis [PushService] (app au premier plan / arrière-plan) que
/// depuis le handler de messages en fond `firebaseMessagingBackgroundHandler`
/// (app tuée), où seul un isolate minimal tourne.
///
/// L'`id` CallKit est le `callId` Firestore : si le même appel arrive à la
/// fois par le push FCM et par le listener Firestore [CallService._watchIncoming],
/// le second `showCallkitIncoming` est dédupliqué par l'OS.
/// Vrai entre le `didActivate` et le `didDeactivate` de la session audio
/// CallKit (iOS). Relayé par PushService depuis l'évènement
/// `actionCallToggleAudioSession` : un appel décroché depuis l'UI native ne
/// doit faire tourner son micro et son haut-parleur que dans cette fenêtre
/// (voir CallController._useCallkitAudio).
final callkitAudioActive = ValueNotifier<bool>(false);

Future<void> showCallkitIncomingFromData(Map<String, dynamic> data) async {
  final callId = (data['callId'] as String?)?.trim() ?? '';
  if (callId.isEmpty) return;

  final callType = (data['callType'] as String?) ?? 'audio';
  final isVideo = callType == 'video';
  final callerName = (data['callerName'] as String?)?.trim();

  final params = CallKitParams(
    id: callId,
    nameCaller: (callerName == null || callerName.isEmpty)
        ? 'Appel entrant'
        : callerName,
    appName: 'Foumbot Link',
    type: isVideo ? 1 : 0,
    // Aligné sur CallController._ringTimeout : au-delà, l'appelant marque
    // l'appel « manqué », donc l'UI entrante doit disparaître d'elle-même.
    duration: 45000,
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Appel manqué',
    ),
    // Récupéré tel quel dans les évènements CallKit (accept/decline) pour
    // rouvrir l'écran d'appel avec les bons arguments.
    extra: <String, dynamic>{
      'callId': callId,
      'callerUid': data['callerUid'] ?? '',
      'callType': callType,
      'conversationId': data['conversationId'] ?? '',
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      isShowCallID: false,
      isImportant: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0A0A0A',
      actionColor: '#4CAF50',
      textColor: '#FFFFFF',
      textAccept: 'Répondre',
      textDecline: 'Refuser',
      incomingCallNotificationChannelName: 'Appels entrants',
      missedCallNotificationChannelName: 'Appels manqués',
    ),
    ios: IOSParams(
      handleType: 'generic',
      supportsVideo: isVideo,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      configureAudioSession: true,
      audioSessionMode: 'default',
      audioSessionActive: true,
    ),
  );

  await _guard(
    'showCallkitIncoming',
    () => FlutterCallkitIncoming.showCallkitIncoming(params),
  );
}

/// Retire un appel de l'UI CallKit (coupe la sonnerie). Sans `callId`, retire
/// tous les appels en cours.
Future<void> dismissCallkit([String? callId]) async {
  final id = callId?.trim() ?? '';
  await _guard(
    'dismissCallkit',
    () => id.isEmpty
        ? FlutterCallkitIncoming.endAllCalls()
        : FlutterCallkitIncoming.endCall(id),
  );
}

/// Signale à CallKit que l'appel `callId` est connecté (met à jour l'UI et
/// l'historique côté iOS ; sans effet visible sur Android).
Future<void> markCallkitConnected(String? callId) async {
  final id = callId?.trim() ?? '';
  if (id.isEmpty) return;
  await _guard(
    'markCallkitConnected',
    () => FlutterCallkitIncoming.setCallConnected(id),
  );
}

/// Les appareils sans téléphonie (`android.software.telecom` absent —
/// tablettes, la plupart des émulateurs) font échouer `flutter_callkit_incoming`
/// au niveau natif. On avale l'erreur : ces appareils ne sont de toute façon
/// pas des cibles d'appel réelles, l'app ne doit pas planter pour autant.
Future<void> _guard(String label, Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (e) {
    developer.log('CallKit indisponible ($label)', name: 'callkit', error: e);
  }
}
