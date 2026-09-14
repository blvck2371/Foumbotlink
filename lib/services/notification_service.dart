import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_notification.dart';

/// Flux personnel de notifications (`users/{uid}/notifications`) — message
/// reçu, like, commentaire/réponse, nouvel abonné, publication d'un compte
/// suivi, appel manqué. Les Cloud Functions écrivent ces documents (voir
/// functions/index.js) ; ce service ne fait que les lire/marquer lues,
/// sauf pour [checkAppUpdate] qui écrit sa propre notification côté client
/// (seul cas autorisé par firestore.rules pour un client).
class NotificationService {
  static const _pageSize = 50;

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watch({
    required String uid,
    required void Function(List<AppNotification> list) onData,
    void Function(Object error)? onError,
  }) {
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize)
        .snapshots()
        .listen((snap) {
          onData(snap.docs.map(AppNotification.fromDoc).toList());
        }, onError: onError ?? (_) {});
  }

  Future<void> markRead(String uid, String notificationId) {
    return _ref(uid).doc(notificationId).update({'read': true});
  }

  Future<void> markAllRead(String uid, List<String> unreadIds) async {
    if (unreadIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in unreadIds) {
      batch.update(_ref(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }

  /// Compare la version installée à `config/app.latestVersion` et, si une
  /// mise à jour est disponible et n'a pas déjà été signalée, ajoute une
  /// notification "appUpdate" dans le flux de l'utilisateur — pas de push
  /// nécessaire, l'app est forcément ouverte pour faire cette vérification.
  /// Pas de comparaison sémantique fine : une simple inégalité de chaîne
  /// suffit ici (l'admin publie un numéro de version exact à comparer).
  Future<void> checkAppUpdate(String uid) async {
    try {
      final configDoc = await _db.collection('config').doc('app').get();
      final latest = configDoc.data()?['latestVersion'] as String?;
      if (latest == null || latest.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      if (info.version == latest) return;

      // Évite de renotifier à chaque lancement pour la même version.
      final already = await _ref(uid)
          .where('type', isEqualTo: AppNotificationType.appUpdate.name)
          .where('data.version', isEqualTo: latest)
          .limit(1)
          .get();
      if (already.docs.isNotEmpty) return;

      final message =
          configDoc.data()?['updateMessage'] as String? ??
          'Une nouvelle version de Foumbot Link est disponible.';

      await _ref(uid).add({
        ...AppNotification(
          id: '',
          type: AppNotificationType.appUpdate,
          title: 'Mise à jour disponible',
          body: message,
          data: {'version': latest},
          createdAt: DateTime.now(),
        ).toMap(),
      });
    } on FirebaseException catch (_) {
      // Pas de doc `config/app` ou hors-ligne : pas grave, juste pas de
      // notification cette fois.
    }
  }
}
