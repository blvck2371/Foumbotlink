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
    this.isGuest = false,
    this.title,
  });

  final String liveId;
  final String url;
  final String token;
  final bool isHost;

  /// Spectateur monté sur le panel : il peut émettre.
  final bool isGuest;
  final String? title;

  static LiveTicket fromMap(Map<Object?, Object?> m) => LiveTicket(
    liveId: m['liveId'] as String,
    url: m['url'] as String,
    token: m['token'] as String,
    isHost: m['role'] == 'host',
    isGuest: m['role'] == 'guest',
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
  DatabaseReference guestsRef(String id) => _db.ref('liveGuests/$id');
  DatabaseReference get connectedRef => _db.ref('.info/connected');

  /// Lives en cours, en direct. Vide tant qu'on n'est pas connecté.
  final RxList<LiveSession> lives = <LiveSession>[].obs;

  StreamSubscription<DatabaseEvent>? _livesSub;
  String _uid = '';

  /// Jetons d'entrée préparés à l'avance, pour qu'ouvrir un live soit
  /// immédiat, comme sur TikTok : celui du live en tête de liste dès qu'il
  /// apparaît, puis ceux des lives voisins pendant qu'on en regarde un.
  /// Chacun ne sert qu'une fois — revenir dans un live redemande un jeton,
  /// ce qui garde l'exclusion par l'hôte effective.
  final _tickets = <String, ({Future<LiveTicket> ticket, DateTime at})>{};
  final _prefetched = <String>{};

  /// Un jeton LiveKit vaut 6 h ; on n'en sert pas un de plus de 5 h.
  static const _ticketMaxAge = Duration(hours: 5);

  /// Suit la session : la liste ne se lit qu'avec un compte (règle RTDB).
  void bindAuth(Rxn<User> user) {
    void apply(User? u) {
      if (u?.uid != _uid) {
        _tickets.clear();
        _prefetched.clear();
      }
      _uid = u?.uid ?? '';
      u == null ? _stop() : _watch();
    }

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
        .listen((e) {
          lives.assignAll(LiveSession.listFrom(e.snapshot.value));
          _onLives();
        }, onError: (Object _) => lives.clear());
  }

  /// Jetons des lives finis oubliés ; celui du live en tête préparé.
  void _onLives() {
    final ids = lives.map((l) => l.id).toSet();
    _tickets.removeWhere((id, _) => !ids.contains(id));
    final top = lives.firstWhereOrNull((l) => l.hostUid != _uid);
    if (top != null && _prefetched.add(top.id)) prefetch(top.id);
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

  /// Entrer dans un live : le jeton préparé s'il y en a un (consommé),
  /// sinon un neuf. [fresh] en impose un neuf — pour monter sur le panel,
  /// où le jeton doit porter le droit d'émettre.
  Future<LiveTicket> join(String liveId, {bool fresh = false}) {
    final cached = _tickets.remove(liveId);
    if (!fresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _ticketMaxAge) {
      // Préparation ratée (réseau…) : on retente plutôt que d'échouer.
      return cached.ticket.catchError((Object _) => _join(liveId));
    }
    return _join(liveId);
  }

  Future<LiveTicket> _join(String liveId) =>
      _call('joinLive', {'liveId': liveId}).then(LiveTicket.fromMap);

  /// Prépare en silence le jeton d'un live qu'on va sans doute ouvrir.
  void prefetch(String liveId) {
    if (_uid.isEmpty || _tickets.containsKey(liveId)) return;
    final ticket = _join(liveId);
    // Un refus (bloqué, exclu…) ressortira à l'ouverture, pas ici.
    unawaited(ticket.then((_) {}, onError: (Object _) {}));
    _tickets[liveId] = (ticket: ticket, at: DateTime.now());
  }

  Future<void> end(String liveId) => _call('endLive', {'liveId': liveId});

  Future<void> expel(String liveId, String uid) =>
      _call('expelFromLive', {'liveId': liveId, 'uid': uid});

  /// Le panel : `invite`, `approve`, `reject`, `remove`, `mute`, `unmute`
  /// (hôte, avec [uid]) ; `request`, `accept`, `leave` (soi-même).
  Future<void> stage(String liveId, String action, {String? uid}) =>
      _call('liveStage', {'liveId': liveId, 'action': action, 'uid': ?uid});

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
