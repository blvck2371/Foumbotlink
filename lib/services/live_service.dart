import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';

import '../models/live_session.dart';

/// Ce que renvoient `startLive` et `joinLive` : de quoi entrer dans la
/// salle LiveKit du live.
class LiveTicket {
  const LiveTicket({
    required this.liveId,
    required this.url,
    required this.token,
    required this.isHost,
    this.title,
  });

  final String liveId;
  final String url;
  final String token;
  final bool isHost;
  final String? title;

  static LiveTicket fromMap(Map<Object?, Object?> m) => LiveTicket(
    liveId: m['liveId'] as String,
    url: m['url'] as String,
    token: m['token'] as String,
    isHost: m['role'] == 'host',
    title: m['title'] as String?,
  );
}

/// Refus lisible d'une fonction de live (« Ce live est terminé. »…).
class LiveException implements Exception {
  const LiveException(this.message, {this.ended = false});
  final String message;

  /// Le live n'existe plus.
  final bool ended;
  @override
  String toString() => message;
}

/// Accès aux lives : Realtime Database pour tout ce qui est temps réel,
/// fonctions serveur pour entrer dans une salle LiveKit (seules à
/// pouvoir signer un jeton).
class LiveService extends GetxService {
  /// Instance RTDB du projet (Belgique). Écrite en dur : le fichier
  /// `firebase_options.dart` a été généré avant sa création.
  static const databaseUrl =
      'https://foumbotlink-default-rtdb.europe-west1.firebasedatabase.app';

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: databaseUrl,
  );
  FirebaseFunctions get _functions => FirebaseFunctions.instance;

  DatabaseReference liveRef(String id) => _db.ref('lives/$id');
  DatabaseReference commentsRef(String id) => _db.ref('liveComments/$id');
  DatabaseReference viewersRef(String id) => _db.ref('liveViewers/$id');
  DatabaseReference get connectedRef => _db.ref('.info/connected');

  /// Lives en cours, en direct. Vide tant qu'on n'est pas connecté.
  final RxList<LiveSession> lives = <LiveSession>[].obs;

  StreamSubscription<DatabaseEvent>? _livesSub;

  /// Suit la session : la liste ne se lit qu'avec un compte (règle RTDB).
  void bindAuth(Rxn<User> user) {
    void apply(User? u) => u == null ? _stop() : _watch();
    apply(user.value);
    ever<User?>(user, apply);
  }

  void _watch() {
    _livesSub?.cancel();
    _livesSub = _db
        .ref('lives')
        .orderByChild('startedAt')
        .limitToLast(100)
        .onValue
        .listen(
          (e) => lives.assignAll(LiveSession.listFrom(e.snapshot.value)),
          onError: (Object _) => lives.clear(),
        );
  }

  void _stop() {
    _livesSub?.cancel();
    _livesSub = null;
    lives.clear();
  }

  @override
  void onClose() {
    _stop();
    super.onClose();
  }

  /// Un live précis, même absent de la liste (ouvert depuis une
  /// notification avant que la liste n'arrive).
  Future<LiveSession?> fetch(String id) async {
    final snap = await liveRef(id).get();
    return LiveSession.fromMap(id, snap.value);
  }

  // -----------------------------------------------------------------------
  // Fonctions serveur
  // -----------------------------------------------------------------------

  Future<LiveTicket> start(String title) =>
      _call('startLive', {'title': title}).then(LiveTicket.fromMap);

  Future<LiveTicket> join(String liveId) =>
      _call('joinLive', {'liveId': liveId}).then(LiveTicket.fromMap);

  Future<void> end(String liveId) => _call('endLive', {'liveId': liveId});

  Future<void> expel(String liveId, String uid) =>
      _call('expelFromLive', {'liveId': liveId, 'uid': uid});

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final res = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
          )
          .call<Object?>(data);
      final value = res.data;
      return value is Map ? value.cast<Object?, Object?>() : const {};
    } on FirebaseFunctionsException catch (e) {
      throw LiveException(_message(e), ended: e.code == 'not-found');
    } catch (_) {
      throw const LiveException(
        'Connexion impossible. Vérifiez votre réseau et réessayez.',
      );
    }
  }

  static String _message(FirebaseFunctionsException e) {
    final m = e.message;
    // Les refus du serveur sont déjà rédigés pour l'utilisateur ; les
    // erreurs techniques (« INTERNAL »…) ne le sont pas.
    if (m != null && m.isNotEmpty && m != m.toUpperCase()) return m;
    return switch (e.code) {
      'unavailable' || 'deadline-exceeded' =>
        'Le réseau est trop lent. Réessayez dans un instant.',
      'unauthenticated' => 'Connectez-vous pour accéder aux lives.',
      _ => 'Le live n’a pas pu démarrer. Réessayez.',
    };
  }
}
