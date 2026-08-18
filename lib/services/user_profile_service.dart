import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/account_type.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

/// Lit/écrit le profil Firestore (`users/{uid}`) associé au compte
/// Firebase Auth courant : type de compte, nom affiché.
class UserProfileService extends GetxService {
  final _db = FirebaseFirestore.instance;

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
    _sub = _usersRef.doc(uid).snapshots().listen(
      (doc) {
        profile.value =
            doc.exists ? UserProfile.fromMap(uid, doc.data()!) : null;
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
    return created;
  }

  bool get hasProfile => profile.value != null;
}
