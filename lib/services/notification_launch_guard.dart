import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Empêche de **rejouer** la navigation d'un tap notification à chaque
/// hot restart : `getInitialMessage` (FCM) et
/// `getNotificationAppLaunchDetails` (notifications locales) peuvent
/// renvoyer le même évènement de lancement alors que l'utilisateur a déjà
/// été routé une première fois.
class NotificationLaunchGuard {
  NotificationLaunchGuard._();

  static const _prefsKey = 'handled_notification_launch_key';

  /// `true` si cette clé n'a pas encore été consommée — et la marque comme
  /// traitée. À utiliser uniquement pour les navigations « cold start ».
  static Future<bool> consumeIfNew(String key) async {
    if (key.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefsKey) == key) return false;
    await prefs.setString(_prefsKey, key);
    return true;
  }

  /// Marque une navigation déjà effectuée (tap à chaud) pour ne pas la
  /// rejouer au prochain redémarrage de l'isolate.
  static Future<void> markHandled(String key) async {
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key);
  }

  static String keyFromFcm(RemoteMessage message) {
    final id = message.messageId;
    if (id != null && id.isNotEmpty) return 'fcm:$id';
    final d = message.data;
    return 'fcm:${d['type']}:${d['senderUid'] ?? d['callerUid'] ?? d['postId'] ?? d['conversationId'] ?? ''}';
  }

  static String keyFromPayload(String payload) => 'local:$payload';
}
