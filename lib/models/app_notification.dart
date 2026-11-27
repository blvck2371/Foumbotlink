import 'package:cloud_firestore/cloud_firestore.dart';

/// Types de notifications gérés par le projet — voir functions/index.js
/// pour les déclencheurs qui les créent (Cloud Functions, sauf [appUpdate]
/// écrite par le client lui-même après comparaison de version).
enum AppNotificationType {
  message,
  like,
  comment,
  follow,
  post,
  missedCall,
  appUpdate,

  /// Une annonce correspond à une recherche enregistrée (voir
  /// `SavedSearch`). Émise par `onMarketItemCreated`.
  marketAlert,

  /// Un dossier déposé au guichet a changé d'état. Émise par
  /// `onDossierWritten` — voir `Dossier` et `DossierStatus`.
  dossier,

  /// Un dossier de modération est devenu prioritaire. Réservée aux
  /// administrateurs, émise par `onReportCreated`.
  moderation,

  /// Un compte suivi passe en live. Émise par `onLiveSessionCreated`.
  live,

  /// Décision sur une demande de certification (functions/
  /// certification.js).
  certification,

  /// On vous a mentionné (@) dans une publication. Émise par
  /// `onPostCreated`.
  mention,
}

/// Document `users/{uid}/notifications/{id}` — flux personnel, jamais
/// visible par un tiers (voir firestore.rules).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.fromUid,
    this.fromName,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? fromUid;
  final String? fromName;
  final DateTime createdAt;
  final bool read;

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AppNotification(
      id: doc.id,
      type: AppNotificationType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => AppNotificationType.post,
      ),
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      data: Map<String, dynamic>.from(d['data'] as Map? ?? const {}),
      fromUid: d['fromUid'] as String?,
      fromName: d['fromName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read: d['read'] as bool? ?? false,
    );
  }

  /// Seule la notification de mise à jour disponible est créée côté
  /// client (voir firestore.rules — `allow create` n'accepte que ce
  /// type-là) ; toutes les autres viennent des Cloud Functions.
  Map<String, dynamic> toMap() => {
    'type': type.name,
    'title': title,
    'body': body,
    'data': data,
    'createdAt': FieldValue.serverTimestamp(),
    'read': false,
  };
}
