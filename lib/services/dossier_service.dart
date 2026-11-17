import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/dossier.dart';

/// Ce qu'une recherche de code au guichet peut donner.
sealed class CodeLookup {
  const CodeLookup();
}

class CodeFound extends CodeLookup {
  const CodeFound({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
}

class CodeUnknown extends CodeLookup {
  const CodeUnknown(this.message);

  final String message;
}

/// Suivi des dossiers déposés au guichet d'une structure.
///
/// Trois collections :
///
/// - `dossiers/{id}` — un dossier et son historique ;
/// - `trackingCodes/{CODE}` — l'annuaire inverse code → habitant, qui
///   permet au guichet de retrouver quelqu'un à partir des sept
///   caractères écrits sur sa chemise ;
/// - `users/{uid}/private/tracking` — le code tel que son propriétaire le
///   voit dans l'app. **Dans la sous-collection privée**, pas sur le
///   document utilisateur : celui-ci est lisible par tout compte connecté
///   (les publications, les profils publics en dépendent), et le code y
///   aurait été à la vue de tous.
///
/// Le code est **attribué une fois pour toutes** à chaque habitant, pas
/// par dossier : c'est ce qu'on lui demande de retenir et de recopier, et
/// un code par démarche l'obligerait à revenir dans l'app avant chaque
/// dépôt. Plusieurs dossiers peuvent donc porter le même code — ce sont
/// des dépôts successifs de la même personne, distingués par leur
/// intitulé et leur date.
class DossierService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _dossiersRef =>
      _db.collection('dossiers');

  CollectionReference<Map<String, dynamic>> get _codesRef =>
      _db.collection('trackingCodes');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// `users/{uid}/private/tracking` — lisible et modifiable par son seul
  /// propriétaire (voir firestore.rules).
  DocumentReference<Map<String, dynamic>> _privateTrackingRef(String uid) =>
      _userRef(uid).collection('private').doc('tracking');

  // -----------------------------------------------------------------------
  // Code de suivi
  // -----------------------------------------------------------------------

  /// Renvoie le code de [uid], en lui en attribuant un s'il n'en a pas.
  ///
  /// L'unicité est garantie par l'identifiant du document dans
  /// `trackingCodes` : deux appels simultanés qui tireraient le même code
  /// ne peuvent pas le réserver tous les deux, le second échoue et
  /// retire un nouveau tirage.
  Future<String> ensureTrackingCode({
    required String uid,
    required String displayName,
  }) async {
    final snap = await _privateTrackingRef(uid).get();
    final existing = snap.data()?['code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    // Cinq essais : avec 27 milliards de combinaisons, une collision est
    // déjà improbable au premier tirage. Au-delà, c'est un autre
    // problème (règles, réseau) qu'il vaut mieux remonter.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = TrackingCode.generate();
      // Les deux documents partent ensemble : les règles exigent que la
      // réservation du code et `private/tracking` soient posées dans la
      // même écriture — c'est ce qui borne chaque compte à un seul code.
      final batch = _db.batch()
        ..set(_codesRef.doc(code), {
          'uid': uid,
          'displayName': displayName,
          'createdAt': FieldValue.serverTimestamp(),
        })
        ..set(_privateTrackingRef(uid), {
          'code': code,
          'createdAt': FieldValue.serverTimestamp(),
        });
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' && e.code != 'already-exists') {
          rethrow;
        }
        // Soit le code est déjà pris, soit un autre appareil du même
        // compte vient d'attribuer le sien — dans ce cas, c'est lui qui
        // fait foi.
        final again = await _privateTrackingRef(uid).get();
        final assigned = again.data()?['code'] as String?;
        if (assigned != null && assigned.isNotEmpty) return assigned;
        continue;
      }
      // Ménage des tout premiers comptes, dont le code avait été écrit
      // sur le document utilisateur — lisible par n'importe quel compte
      // connecté. Sans effet si le champ n'a jamais existé.
      await _userRef(
        uid,
      ).set({'trackingCode': FieldValue.delete()}, SetOptions(merge: true));
      return code;
    }
    throw StateError('Impossible d’attribuer un code de suivi.');
  }

  /// Retrouve l'habitant derrière un code saisi au guichet.
  ///
  /// Le message d'échec est destiné à l'agent, qui a la chemise sous les
  /// yeux : il doit lui dire quoi vérifier, pas seulement « introuvable ».
  Future<CodeLookup> lookupCode(String raw) async {
    final problem = TrackingCode.describeProblem(raw);
    if (problem != null) return CodeUnknown(problem);

    final code = TrackingCode.normalize(raw);
    try {
      final snap = await _codesRef.doc(code).get();
      if (!snap.exists) {
        return const CodeUnknown(
          'Aucun habitant ne porte ce code. Vérifiez la lecture de la '
          'chemise, caractère par caractère.',
        );
      }
      final d = snap.data()!;
      return CodeFound(
        uid: d['uid'] as String? ?? '',
        displayName: d['displayName'] as String? ?? 'Habitant',
      );
    } on FirebaseException catch (e) {
      developer.log('lookupCode', name: 'DossierService', error: e);
      return const CodeUnknown(
        'Recherche impossible pour le moment. Vérifiez la connexion.',
      );
    }
  }

  /// Le code de [uid] en écoute continue.
  ///
  /// `snapshots()` plutôt qu'un `get()` : Firestore émet d'abord ce qu'il
  /// a en cache, puis la réponse serveur. À la deuxième ouverture de
  /// l'écran, le code s'affiche donc immédiatement au lieu d'attendre un
  /// aller-retour réseau — c'est exactement le temps de chargement qu'on
  /// reprochait à cet écran.
  Stream<String?> watchTrackingCode(String uid) => _privateTrackingRef(
    uid,
  ).snapshots().map((snap) => snap.data()?['code'] as String?);

  /// Suit un code saisi au guichet, au lieu de le chercher une fois.
  ///
  /// Même raison : la première émission sort du cache local, sans
  /// attendre le réseau. Et si l'habitant vient tout juste de faire
  /// attribuer son code, l'agent le voit apparaître sans ressaisir.
  ///
  /// [raw] est validé avant toute lecture : inutile d'ouvrir une écoute
  /// sur sept caractères qui ne peuvent pas exister.
  Stream<CodeLookup> watchCode(String raw) {
    final problem = TrackingCode.describeProblem(raw);
    if (problem != null) return Stream.value(CodeUnknown(problem));

    final code = TrackingCode.normalize(raw);
    return _codesRef
        .doc(code)
        .snapshots()
        .map<CodeLookup>((snap) {
          if (!snap.exists) {
            return const CodeUnknown(
              'Aucun habitant ne porte ce code. Vérifiez la lecture de la '
              'chemise, caractère par caractère.',
            );
          }
          final d = snap.data()!;
          return CodeFound(
            uid: d['uid'] as String? ?? '',
            displayName: d['displayName'] as String? ?? 'Habitant',
          );
        })
        .handleError((Object e) {
          developer.log('watchCode', name: 'DossierService', error: e);
        });
  }

  // -----------------------------------------------------------------------
  // Guichet
  // -----------------------------------------------------------------------

  /// Enregistre un dossier au moment où il arrive au guichet.
  ///
  /// C'est le geste qui déclenche tout le suivi : à partir de là, le
  /// propriétaire voit son dossier dans l'app et sera prévenu à chaque
  /// changement.
  Future<Dossier> receiveDossier({
    required String ownerUid,
    required String ownerName,
    required String trackingCode,
    required String structureUid,
    required String structureName,
    required String title,
    String? demarcheId,
    String? reference,
  }) async {
    final ref = _dossiersRef.doc();
    final now = DateTime.now();
    final event = DossierEvent(
      status: DossierStatus.receptionne,
      at: now,
      byName: structureName,
    );

    await ref.set({
      'ownerUid': ownerUid,
      'ownerName': ownerName,
      'trackingCode': trackingCode,
      'structureUid': structureUid,
      'structureName': structureName,
      'title': title.trim(),
      'demarcheId': ?demarcheId,
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
      'status': DossierStatus.receptionne.name,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'events': [event.toMap()],
    });

    return Dossier(
      id: ref.id,
      ownerUid: ownerUid,
      ownerName: ownerName,
      trackingCode: trackingCode,
      structureUid: structureUid,
      structureName: structureName,
      title: title.trim(),
      demarcheId: demarcheId,
      reference: reference,
      status: DossierStatus.receptionne,
      createdAt: now,
      updatedAt: now,
      events: [event],
    );
  }

  /// Fait avancer un dossier. La notification part d'une Cloud Function
  /// (`onDossierUpdated`), pas d'ici : elle doit partir même si l'agent
  /// ferme l'app dans la seconde.
  Future<void> advance({
    required Dossier dossier,
    required DossierStatus status,
    String? note,
  }) async {
    final now = DateTime.now();
    final event = DossierEvent(
      status: status,
      at: now,
      note: note?.trim(),
      byName: dossier.structureName,
    );

    await _dossiersRef.doc(dossier.id).update({
      'status': status.name,
      'updatedAt': Timestamp.fromDate(now),
      // `arrayUnion` plutôt qu'une réécriture du tableau : deux agents du
      // même service peuvent enregistrer une étape en même temps, et une
      // réécriture ferait disparaître celle de l'autre.
      'events': FieldValue.arrayUnion([event.toMap()]),
    });
  }

  // -----------------------------------------------------------------------
  // Lectures
  // -----------------------------------------------------------------------

  /// Les dossiers d'un habitant, du plus récent au plus ancien, suivis en
  /// direct : c'est ce qui fait qu'un changement au guichet apparaît sur
  /// son téléphone sans qu'il ait à rafraîchir.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMine({
    required String uid,
    required void Function(List<Dossier>) onData,
    void Function(Object error)? onError,
  }) {
    return _dossiersRef
        .where('ownerUid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snap) => onData(snap.docs.map(Dossier.fromDoc).toList()),
          onError: (Object e) {
            developer.log('watchMine', name: 'DossierService', error: e);
            onError?.call(e);
          },
        );
  }

  /// Les dossiers reçus par une structure.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchStructure({
    required String structureUid,
    required void Function(List<Dossier>) onData,
    void Function(Object error)? onError,
  }) {
    return _dossiersRef
        .where('structureUid', isEqualTo: structureUid)
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .listen(
          (snap) => onData(snap.docs.map(Dossier.fromDoc).toList()),
          onError: (Object e) {
            developer.log('watchStructure', name: 'DossierService', error: e);
            onError?.call(e);
          },
        );
  }

  /// Écoute un dossier précis.
  ///
  /// L'écran de détail peut rester ouvert pendant que le guichet fait
  /// avancer le dossier : sans cette écoute, on lirait un état périmé en
  /// ayant reçu la notification qui dit le contraire.
  Stream<Dossier?> watchOne(String id) => _dossiersRef
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? Dossier.fromDoc(doc) : null);

  Future<Dossier?> getById(String id) async {
    final doc = await _dossiersRef.doc(id).get();
    return doc.exists ? Dossier.fromDoc(doc) : null;
  }
}
