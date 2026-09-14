import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report.dart';

/// Signalement de contenu et blocage d'utilisateur.
///
/// Ces deux fonctions sont exigées par l'App Store (Guideline 1.2) dès
/// qu'une app diffuse du contenu généré par les utilisateurs : pouvoir
/// signaler un contenu, pouvoir bloquer son auteur, et retrait sous 24 h.
/// Le retrait automatique est côté serveur (`onReportCreated` dans
/// functions/index.js masque un contenu au-delà du seuil de signalements).
///
/// Le blocage est unilatéral et local au bloqueur : la liste vit dans
/// `users/{uid}/blocked/{blockedUid}`, n'est lisible que par lui, et sert
/// à filtrer le fil et les commentaires côté client. La personne bloquée
/// n'en est jamais informée.
class ModerationService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _db.collection('reports');

  CollectionReference<Map<String, dynamic>> _blockedRef(String uid) =>
      _db.collection('users').doc(uid).collection('blocked');

  /// Uids bloqués par l'utilisateur courant, tenu à jour par [watchBlocked].
  /// Exposé en synchrone pour que le filtrage du fil reste sans latence.
  final Set<String> blockedUids = <String>{};

  bool isBlocked(String uid) => blockedUids.contains(uid);

  // -----------------------------------------------------------------------
  // Signalement
  // -----------------------------------------------------------------------

  /// Enregistre un signalement. Le même utilisateur ne peut signaler deux
  /// fois le même contenu : l'id du document est déterministe
  /// (`{type}_{cible}_{signaleur}`), donc un second envoi écrase le premier
  /// au lieu de gonfler artificiellement le compteur de signalements.
  Future<void> report(ContentReport report) async {
    final id =
        '${report.targetType.name}_${report.targetId}_${report.reporterUid}';
    await _reportsRef.doc(id).set(report.toMap());
  }

  // -----------------------------------------------------------------------
  // Blocage
  // -----------------------------------------------------------------------

  Future<void> blockUser({
    required String myUid,
    required String targetUid,
    String targetName = '',
  }) async {
    if (myUid == targetUid) return;
    await _blockedRef(myUid).doc(targetUid).set({
      'displayName': targetName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    blockedUids.add(targetUid);
  }

  Future<void> unblockUser({
    required String myUid,
    required String targetUid,
  }) async {
    await _blockedRef(myUid).doc(targetUid).delete();
    blockedUids.remove(targetUid);
  }

  Future<List<String>> fetchBlocked(String myUid) async {
    final snap = await _blockedRef(myUid).get();
    final ids = snap.docs.map((d) => d.id).toList();
    blockedUids
      ..clear()
      ..addAll(ids);
    return ids;
  }

  /// Flux de la liste de blocage. [onChanged] est appelé à chaque
  /// modification pour que l'appelant relance son filtrage.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchBlocked({
    required String myUid,
    required void Function(Set<String> blocked) onChanged,
  }) {
    return _blockedRef(myUid).snapshots().listen((snap) {
      blockedUids
        ..clear()
        ..addAll(snap.docs.map((d) => d.id));
      onChanged(Set<String>.from(blockedUids));
    });
  }
}
