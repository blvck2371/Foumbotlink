import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:get/get.dart';

import '../models/report.dart';

/// Signalement de contenu et blocage d'utilisateur.
///
/// Ces deux fonctions sont exigées par l'App Store (Guideline 1.2) dès
/// qu'une app diffuse du contenu généré par les utilisateurs : pouvoir
/// signaler un contenu, pouvoir bloquer son auteur, et retrait sous 24 h.
/// Le retrait automatique est côté serveur (`onReportCreated` dans
/// functions/index.js masque un contenu au-delà du seuil de signalements).
///
/// Le blocage coupe le lien dans les deux sens, comme sur les grandes
/// messageries :
///  - la liste de celui qui bloque vit dans `users/{uid}/blocked/{cible}`,
///    lisible par lui seul ;
///  - le serveur (`onBlockWritten`) en tient le miroir dans
///    `users/{cible}/blockedBy/{uid}`, lisible par la seule personne
///    bloquée — c'est ce qui permet à son app de masquer à son tour les
///    contenus de celui qui l'a bloquée ;
///  - les règles Firestore refusent messages, appels, commentaires,
///    abonnements et avis entre deux comptes dont l'un a bloqué l'autre.
///
/// Ce service n'expose ici que le filtrage d'affichage : la vraie
/// barrière est côté serveur.
class ModerationService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _db.collection('reports');

  CollectionReference<Map<String, dynamic>> _blockedRef(String uid) =>
      _db.collection('users').doc(uid).collection('blocked');

  /// Comptes que l'utilisateur courant a bloqués.
  final RxSet<String> blocked = <String>{}.obs;

  /// Comptes qui ont bloqué l'utilisateur courant (miroir serveur).
  final RxSet<String> blockedBy = <String>{}.obs;

  /// Compatibilité : lecture synchrone de [blocked].
  Set<String> get blockedUids => blocked;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blockedSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blockedBySub;
  String? _watchedUid;

  /// J'ai bloqué [uid].
  bool isBlocked(String uid) => blocked.contains(uid);

  /// [uid] m'a bloqué.
  bool isBlockedBy(String uid) => blockedBy.contains(uid);

  /// Aucun contenu ni échange possible avec [uid], dans un sens ou dans
  /// l'autre. C'est le filtre à appliquer à tout ce qui s'affiche.
  bool hides(String uid) => isBlocked(uid) || isBlockedBy(uid);

  /// Suit la session : les listes se branchent à la connexion et se
  /// vident à la déconnexion, quel que soit l'écran affiché.
  void bindAuth(Rxn<User> user) {
    void apply(User? u) => u == null ? stopWatching() : startWatching(u.uid);
    apply(user.value);
    ever<User?>(user, apply);
  }

  /// Branche les deux listes pour [myUid]. Sans effet si elles le sont
  /// déjà pour ce compte : plusieurs écrans peuvent l'appeler.
  void startWatching(String myUid) {
    if (myUid.isEmpty || _watchedUid == myUid) return;
    stopWatching();
    _watchedUid = myUid;
    _blockedSub = _blockedRef(myUid).snapshots().listen(
      (snap) => blocked.assignAll(snap.docs.map((d) => d.id)),
      onError: (Object _) {},
    );
    _blockedBySub = _db
        .collection('users')
        .doc(myUid)
        .collection('blockedBy')
        .snapshots()
        .listen(
          (snap) => blockedBy.assignAll(snap.docs.map((d) => d.id)),
          onError: (Object _) {},
        );
  }

  /// Fin de session : plus rien ne doit filtrer pour le compte suivant.
  void stopWatching() {
    _blockedSub?.cancel();
    _blockedBySub?.cancel();
    _blockedSub = null;
    _blockedBySub = null;
    _watchedUid = null;
    blocked.clear();
    blockedBy.clear();
  }

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
    blocked.add(targetUid);
  }

  Future<void> unblockUser({
    required String myUid,
    required String targetUid,
  }) async {
    await _blockedRef(myUid).doc(targetUid).delete();
    blocked.remove(targetUid);
  }

  /// Flux de l'ensemble des comptes masqués (bloqués ou bloquants).
  /// [onChanged] reçoit l'union à chaque modification de l'une des deux
  /// listes, pour que l'appelant retire aussitôt ce qui est déjà affiché.
  Workers watchHidden(void Function(Set<String> hidden) onChanged) {
    void emit(_) => onChanged({...blocked, ...blockedBy});
    return Workers([
      ever<Set<String>>(blocked, emit),
      ever<Set<String>>(blockedBy, emit),
    ]);
  }
}
