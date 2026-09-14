import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../models/account_type.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'dossier_service.dart';

/// Lit/écrit le profil Firestore (`users/{uid}`) associé au compte
/// Firebase Auth courant : type de compte, nom affiché.
class UserProfileService extends GetxService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final profile = Rxn<UserProfile>();

  /// `true` tant que l'état du profil de l'utilisateur courant n'est pas
  /// encore connu (juste après une connexion, ou au démarrage pour une
  /// session déjà active). Tant que c'est `true`, `hasProfile == false`
  /// ne veut PAS dire "pas de profil" — juste "pas encore vérifié". Un
  /// code qui ignore ça peut renvoyer un utilisateur déjà inscrit vers
  /// l'écran de configuration de compte, ou le déconnecter à tort.
  final isLoading = true.obs;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  AuthService get _auth => Get.find<AuthService>();

  @override
  void onInit() {
    super.onInit();
    // Recharge le profil à chaque changement de session (connexion,
    // déconnexion, changement de compte). On annule systématiquement
    // l'écoute précédente : sinon, à la déconnexion, l'ancien listener
    // continue de tourner et se fait rejeter par les règles Firestore
    // (auth devenu null) — une erreur non gérée qui plantait l'app.
    ever(_auth.firebaseUser, (user) {
      _sub?.cancel();
      _sub = null;
      if (user == null) {
        profile.value = null;
        isLoading.value = false;
      } else {
        isLoading.value = true;
        _watch(user.uid);
      }
    });
    if (_auth.isSignedIn) {
      _watch(_auth.uid);
    } else {
      isLoading.value = false;
    }
  }

  void _watch(String uid) {
    _sub = _usersRef
        .doc(uid)
        .snapshots()
        .listen(
          (doc) {
            profile.value = doc.exists
                ? UserProfile.fromMap(uid, doc.data()!)
                : null;
            isLoading.value = false;
          },
          onError: (Object _) {
            // Session expirée ou déconnexion en cours : on efface juste le
            // profil localement, jamais d'exception non gérée.
            profile.value = null;
            isLoading.value = false;
          },
        );
  }

  /// Attend que l'état du profil de l'utilisateur courant soit connu
  /// (chargé ou confirmé absent). À utiliser avant toute décision basée
  /// sur `hasProfile` qui ne suit pas immédiatement une connexion — ex.
  /// au démarrage de l'app pour une session déjà active.
  Future<void> waitUntilLoaded() async {
    if (!isLoading.value) return;
    final completer = Completer<void>();
    late final Worker worker;
    worker = ever<bool>(isLoading, (loading) {
      if (!loading) {
        worker.dispose();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  /// Lecture directe et immédiate du profil de l'utilisateur courant
  /// (une seule requête, pas d'attente sur le listener réactif) —
  /// utilisée juste après une connexion/inscription pour décider tout
  /// de suite, sans latence ni ambiguïté, si le profil existe déjà.
  Future<bool> ensureLoaded() async {
    final uid = _auth.firebaseUser.value?.uid;
    if (uid == null) return false;
    final doc = await _usersRef.doc(uid).get();
    isLoading.value = false;
    if (doc.exists) {
      profile.value = UserProfile.fromMap(uid, doc.data()!);
      return true;
    }
    profile.value = null;
    return false;
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _db.collection('users');

  /// Crée le profil juste après l'inscription — étape obligatoire avant
  /// de pouvoir publier, aimer ou commenter.
  Future<UserProfile> createProfile({
    required AccountType accountType,
    required String displayName,
    String? email,
    String? phoneNumber,
  }) async {
    final user = _auth.firebaseUser.value!;
    final doc = await _usersRef.doc(user.uid).get();
    if (doc.exists) {
      final existing = UserProfile.fromMap(user.uid, doc.data()!);
      profile.value = existing;
      isLoading.value = false;
      return existing;
    }
    final created = UserProfile(
      uid: user.uid,
      accountType: accountType,
      displayName: displayName.trim(),
      email: email,
      phoneNumber: phoneNumber,
      createdAt: DateTime.now(),
    );
    await _usersRef.doc(user.uid).set(created.toMap());
    profile.value = created;
    isLoading.value = false;

    // Code de suivi attribué dès la création : il doit être là au premier
    // passage au guichet, sans qu'on ait eu à ouvrir l'écran des
    // démarches auparavant.
    //
    // Volontairement **non bloquant** : un échec réseau ne doit pas faire
    // rater une inscription réussie. Les comptes sans code — ceux créés
    // avant cette fonctionnalité, et ceux dont l'attribution a échoué —
    // en reçoivent un à la première ouverture du suivi
    // (`DossierService.ensureTrackingCode`, qui ne fait rien si le code
    // existe déjà).
    unawaited(
      Get.find<DossierService>()
          .ensureTrackingCode(uid: user.uid, displayName: created.displayName)
          .catchError((Object e) {
            developer.log(
              'Attribution du code de suivi',
              name: 'UserProfileService',
              error: e,
            );
            return '';
          }),
    );

    return created;
  }

  bool get hasProfile => profile.value != null;

  /// Statut « compte certifié » des *autres* utilisateurs, mémorisé le
  /// temps de la session. Le fil transporte bien un `authorVerified`, mais
  /// c'est une copie figée à la publication : un compte certifié après coup
  /// (ou avant l'ajout du champ) resterait sans badge sur ses anciens
  /// posts. On relit donc la source de vérité, `users/{uid}.verified`.
  final _verifiedCache = <String, bool>{};

  /// Résout le statut certifié de [uids] en groupant les lectures par 10
  /// (limite d'un `whereIn`), sans jamais relire un uid déjà connu.
  ///
  /// Ne renvoie que ce qui a pu être lu : en cas d'échec réseau ou de
  /// permission, les uids concernés sont simplement absents de la map
  /// (l'appelant garde alors la valeur transportée par le post) et seront
  /// retentés au prochain appel.
  Future<Map<String, bool>> verifiedFor(Iterable<String> uids) async {
    final wanted = uids.where((uid) => uid.isNotEmpty).toSet();
    if (wanted.isEmpty) return const {};

    final known = <String, bool>{
      for (final uid in wanted)
        if (_verifiedCache.containsKey(uid)) uid: _verifiedCache[uid]!,
    };
    final missing = wanted.difference(known.keys.toSet()).toList();

    // Le profil de la session est déjà suivi en temps réel : inutile de
    // le relire, et sa valeur est plus fraîche que n'importe quel cache.
    final me = profile.value;
    if (me != null && missing.remove(me.uid)) {
      known[me.uid] = me.verified;
    }

    for (var i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, (i + 10).clamp(0, missing.length));
      try {
        final snap = await _usersRef
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final verified = doc.data()['verified'] as bool? ?? false;
          _verifiedCache[doc.id] = verified;
          known[doc.id] = verified;
        }
        // Un uid sans document (compte supprimé) n'est pas certifié : on
        // le mémorise aussi, sinon on le relirait à chaque page du fil.
        for (final uid in chunk) {
          if (!known.containsKey(uid)) {
            _verifiedCache[uid] = false;
            known[uid] = false;
          }
        }
      } on FirebaseException catch (_) {
        // Rien à mettre en cache : on retentera plus tard.
      }
    }
    return known;
  }

  /// Nom affiché et photo de plusieurs comptes, en une lecture groupée.
  ///
  /// Employé par la feuille de transfert du chat, qui liste des
  /// conversations dont les documents ne portent ni nom ni photo.
  Future<Map<String, ({String name, String? photoUrl})>> summariesFor(
    Iterable<String> uids,
  ) async {
    final wanted = uids.where((uid) => uid.isNotEmpty).toSet().toList();
    if (wanted.isEmpty) return const {};

    final result = <String, ({String name, String? photoUrl})>{};
    for (var i = 0; i < wanted.length; i += 10) {
      final chunk = wanted.sublist(i, (i + 10).clamp(0, wanted.length));
      try {
        final snap = await _usersRef
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          result[doc.id] = (
            name: d['displayName'] as String? ?? 'Utilisateur',
            photoUrl: d['photoUrl'] as String?,
          );
        }
      } on FirebaseException catch (_) {
        // Lecture partielle : la feuille affichera « Utilisateur » pour
        // ceux qu'elle n'a pas pu résoudre, plutôt que rien du tout.
      }
    }
    return result;
  }

  /// Oublie les statuts mémorisés — à appeler quand la session change,
  /// pour ne pas traîner d'un compte à l'autre des lectures faites sous
  /// une autre identité.
  void clearVerifiedCache() => _verifiedCache.clear();

  /// Envoie une photo de profil compressée (voir l'appelant : `maxWidth`
  /// 512 côté `ImagePicker`) vers `profiles/{uid}/avatar.jpg`, puis met
  /// à jour `photoUrl` sur le document utilisateur.
  Future<String> uploadProfilePhoto(String filePath) async {
    final uid = _auth.uid;
    final ref = _storage.ref('profiles/$uid/avatar.jpg');
    await ref.putFile(
      File(filePath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();
    await _usersRef.doc(uid).set({'photoUrl': url}, SetOptions(merge: true));
    return url;
  }

  /// Supprime la photo de profil (Storage + champ Firestore).
  Future<void> removeProfilePhoto() async {
    final uid = _auth.uid;
    try {
      await _storage.ref('profiles/$uid/avatar.jpg').delete();
    } on FirebaseException catch (_) {
      // Déjà absente ou accès refusé : on efface quand même l'URL côté profil.
    }
    await _usersRef.doc(uid).update({'photoUrl': FieldValue.delete()});
  }
}
