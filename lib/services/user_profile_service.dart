import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../models/account_type.dart';
import '../models/phone_contact.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'dossier_service.dart';

/// Lit/écrit le profil Firestore (`users/{uid}`) associé au compte
/// Firebase Auth courant : type de compte, nom affiché.
class UserProfileService extends GetxService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final profile = Rxn<UserProfile>();

  /// Coordonnées de connexion, gardées le temps que le profil soit créé :
  /// une inscription ne crée plus le profil tout de suite (ProfileGate).
  String? signInEmail;
  String? signInPhone;

  void rememberSignInContact({String? email, String? phoneNumber}) {
    if (email != null && email.isNotEmpty) signInEmail = email;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      signInPhone = phoneNumber;
    }
  }

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
    // Coordonnées hors du document public — voir UserProfile.toMap.
    if ((email != null && email.isNotEmpty) ||
        (phoneNumber != null && phoneNumber.isNotEmpty)) {
      unawaited(
        _privateContactRef(user.uid).set({
          if (email != null && email.isNotEmpty) 'email': email,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phoneNumber': phoneNumber,
        }, SetOptions(merge: true)).catchError((Object e) {
          developer.log(
            'Coordonnées privées',
            name: 'UserProfileService',
            error: e,
          );
        }),
      );
    }
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

  // -----------------------------------------------------------------------
  // Coordonnées privées et annuaire d'empreintes
  // -----------------------------------------------------------------------

  /// `users/{uid}/private/contact` — e-mail et téléphone, lisibles par
  /// leur seul propriétaire.
  DocumentReference<Map<String, dynamic>> _privateContactRef(String uid) =>
      _usersRef.doc(uid).collection('private').doc('contact');

  /// `phoneDirectory/{empreinte}` — l'annuaire qui permet de retrouver
  /// quelqu'un à partir d'un numéro de son répertoire.
  ///
  /// **Aucun client ne peut le lire** : seule la Cloud Function
  /// `matchContacts` y accède, avec les droits de l'Admin SDK. Sans quoi
  /// il suffirait de générer les quelques dizaines de millions de numéros
  /// camerounais possibles pour reconstituer l'annuaire de la commune.
  DocumentReference<Map<String, dynamic>> _phoneDirectoryRef(String hash) =>
      _db.collection('phoneDirectory').doc(hash);

  /// Les coordonnées privées de la session.
  Future<({String? email, String? phoneNumber})> loadContact() async {
    final uid = _auth.isSignedIn ? _auth.uid : null;
    if (uid == null) return (email: null, phoneNumber: null);
    try {
      final snap = await _privateContactRef(uid).get();
      final d = snap.data();
      return (
        email: d?['email'] as String?,
        phoneNumber: d?['phoneNumber'] as String?,
      );
    } on FirebaseException catch (e) {
      developer.log('loadContact', name: 'UserProfileService', error: e);
      return (email: null, phoneNumber: null);
    }
  }

  /// Enregistre le numéro de la session, et inscrit son empreinte dans
  /// l'annuaire pour que ceux qui l'ont dans leur répertoire puissent le
  /// retrouver.
  ///
  /// Renvoie le numéro sous forme canonique, ou `null` si ce n'en est pas
  /// un — l'appelant affiche alors son propre message.
  ///
  /// L'ancienne empreinte est retirée : sans ça, changer de numéro
  /// laisserait l'ancien pointer indéfiniment sur le compte, et son
  /// nouveau propriétaire serait proposé aux contacts de l'ancien.
  Future<String?> savePhoneNumber(String raw) async {
    final uid = _auth.uid;
    final e164 = PhoneContact.normalize(raw);
    if (e164 == null) return null;

    final previous = (await loadContact()).phoneNumber;
    final hash = PhoneContact.hashOf(e164);

    await _privateContactRef(uid).set({
      'phoneNumber': e164,
    }, SetOptions(merge: true));

    await _phoneDirectoryRef(hash).set({
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (previous != null && previous != e164) {
      final oldHash = PhoneContact.hashOf(previous);
      await _phoneDirectoryRef(oldHash).delete().catchError((Object e) {
        developer.log(
          'Retrait de l’ancienne empreinte',
          name: 'UserProfileService',
          error: e,
        );
      });
    }

    return e164;
  }

  /// Retire le numéro : il disparaît des coordonnées **et** de
  /// l'annuaire. Quelqu'un qui retire son numéro cesse d'être trouvable,
  /// c'est tout l'intérêt du geste.
  Future<void> removePhoneNumber() async {
    final uid = _auth.uid;
    final current = (await loadContact()).phoneNumber;
    await _privateContactRef(uid).set({
      'phoneNumber': FieldValue.delete(),
    }, SetOptions(merge: true));
    if (current == null) return;
    await _phoneDirectoryRef(
      PhoneContact.hashOf(current),
    ).delete().catchError((Object e) {
      developer.log('removePhoneNumber', name: 'UserProfileService', error: e);
    });
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
    _syncCopies();
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
    _syncCopies();
  }

  /// Change le nom affiché. Rend un message d'erreur lisible, ou `null`.
  Future<String?> updateDisplayName(String raw) async {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) return 'Ce nom est trop court.';
    if (name.length > 60) return 'Ce nom est trop long (60 caractères au plus).';
    if (name == profile.value?.displayName) return null;
    try {
      await _usersRef.doc(_auth.uid).update({'displayName': name});
    } on FirebaseException catch (e) {
      return e.message ?? 'Enregistrement impossible.';
    }
    _syncCopies();
    return null;
  }

  /// Recopie nom et photo sur les publications, commentaires, statuts,
  /// annonces et le code de suivi des démarches du compte (Cloud Function `syncProfileCopies`). En arrière-
  /// plan : un échec n'annule pas la modification, les anciennes copies
  /// gardent juste l'ancien nom.
  void _syncCopies() {
    unawaited(
      FirebaseFunctions.instance
          .httpsCallable(
            'syncProfileCopies',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call<Object?>()
          .then<void>((_) {}, onError: (Object e) {
            developer.log(
              'Recopie du profil',
              name: 'UserProfileService',
              error: e,
            );
          }),
    );
  }
}
