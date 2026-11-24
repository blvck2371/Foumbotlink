import 'package:cloud_firestore/cloud_firestore.dart';

/// Nature du contenu signalé — détermine le chemin Firestore que la
/// modération doit ouvrir pour trancher. Doit rester aligné sur la liste
/// acceptée par firestore.rules (`reports`) et sur `onReportCreated`.
enum ReportTargetType { post, comment, user, marketItem, message, status, live }

/// Motifs proposés à l'utilisateur. L'ordre est celui de la feuille de
/// signalement ; `autre` est toujours en dernier et exige un commentaire.
enum ReportReason {
  spam,
  harcelement,
  haine,
  violence,
  nuditeSexuel,
  fausseInformation,
  arnaque,
  autre,
}

extension ReportReasonLabel on ReportReason {
  String get label => switch (this) {
    ReportReason.spam => 'Spam ou publicité',
    ReportReason.harcelement => 'Harcèlement ou intimidation',
    ReportReason.haine => 'Discours haineux',
    ReportReason.violence => 'Violence ou menaces',
    ReportReason.nuditeSexuel => 'Nudité ou contenu sexuel',
    ReportReason.fausseInformation => 'Fausse information',
    ReportReason.arnaque => 'Arnaque ou fraude',
    ReportReason.autre => 'Autre',
  };

  String get description => switch (this) {
    ReportReason.spam => 'Publications répétitives, publicité non sollicitée',
    ReportReason.harcelement => 'S’en prend à une personne de façon répétée',
    ReportReason.haine =>
      'Attaque une personne ou un groupe (origine, religion, genre…)',
    ReportReason.violence => 'Menace ou incite à faire du mal',
    ReportReason.nuditeSexuel => 'Images ou propos à caractère sexuel',
    ReportReason.fausseInformation =>
      'Information trompeuse présentée comme vraie',
    ReportReason.arnaque => 'Tentative de soutirer de l’argent ou des données',
    ReportReason.autre => 'Précisez ce qui pose problème',
  };
}

/// Document `reports/{reportId}` — écrit par le client, jamais relu ni
/// modifié par lui (voir firestore.rules). La modération le traite depuis
/// la console Firebase ou l'Admin SDK.
class ContentReport {
  const ContentReport({
    required this.targetType,
    required this.targetId,
    required this.targetPath,
    required this.targetOwnerUid,
    required this.reporterUid,
    required this.reason,
    this.details = '',
    this.excerpt = '',
  });

  final ReportTargetType targetType;
  final String targetId;

  /// Chemin Firestore complet du document visé (ex.
  /// `posts/ab12/comments/cd34`). Le seul `targetId` ne suffit pas à
  /// retrouver un commentaire, imbriqué sous son post ; `onReportCreated`
  /// s'en sert pour incrémenter le compteur et masquer le contenu.
  final String targetPath;

  final String targetOwnerUid;
  final String reporterUid;
  final ReportReason reason;

  /// Précision libre saisie par l'utilisateur (obligatoire pour `autre`).
  final String details;

  /// Copie du contenu au moment du signalement — le contenu d'origine peut
  /// avoir été édité ou supprimé quand la modération ouvre le dossier.
  final String excerpt;

  Map<String, dynamic> toMap() => {
    'targetType': targetType.name,
    'targetId': targetId,
    'targetPath': targetPath,
    'targetOwnerUid': targetOwnerUid,
    'reporterUid': reporterUid,
    'reason': reason.name,
    'details': details.trim(),
    'excerpt': excerpt,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  };
}
