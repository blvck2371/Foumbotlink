import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';

import '../models/live_session.dart';
import '../services/live_service.dart';
import '../services/moderation_service.dart';

/// Qui je suis dans un live.
class LiveMe {
  const LiveMe({required this.uid, required this.name, this.photo});
  final String uid;
  final String name;
  final String? photo;
}

/// Spectateur présent, tel que listé à l'hôte.
class LiveViewer {
  const LiveViewer({required this.uid, required this.name, this.photo});
  final String uid;
  final String name;
  final String? photo;
}

/// Tout le temps réel d'un live, côté hôte comme côté spectateur :
/// l'état du live, les commentaires, les arrivées, les cœurs, et la
/// présence (`onDisconnect`) qui fait qu'un téléphone qui perd le réseau
/// disparaît de lui-même du compteur — ou, pour l'hôte, met le live en
/// attente.
///
/// À n'ouvrir qu'**après** `joinLive`/`startLive` : ce sont eux qui
/// inscrivent le compte dans `liveMembers`, sans quoi les règles refusent
/// commentaires et cœurs.
class LiveFeed {
  LiveFeed({required this.liveId, required this.me, required this.isHost});

  final String liveId;
  final LiveMe me;
  final bool isHost;

  LiveService get _service => Get.find<LiveService>();
  ModerationService? get _moderation => Get.isRegistered<ModerationService>()
      ? Get.find<ModerationService>()
      : null;

  /// Dernier état connu du live.
  final live = Rxn<LiveSession>();

  /// Le live a disparu de la base : terminé par l'hôte, coupé par la
  /// modération ou clos par le ménage du serveur.
  final ended = false.obs;

  /// Ce qui défile en bas à gauche, du plus ancien au plus récent.
  final items = <LiveFeedItem>[].obs;

  /// Spectateurs présents (pour la liste de l'hôte).
  final viewers = <String, LiveViewer>{}.obs;

  final _hearts = StreamController<int>.broadcast();

  /// Rafales de cœurs à animer : les miens au toucher, ceux des autres à
  /// l'arrivée du compteur.
  Stream<int> get hearts => _hearts.stream;

  final _batcher = HeartBatcher();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _heartTimer;
  DateTime _lastComment = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastLikes;
  bool _closed = false;

  bool _hides(String uid) =>
      uid != me.uid && (_moderation?.hides(uid) ?? false);

  Future<void> start() async {
    final liveRef = _service.liveRef(liveId);
    _subs.add(
      liveRef.onValue.listen((e) {
        final s = LiveSession.fromMap(liveId, e.snapshot.value);
        if (s == null) {
          _markEnded();
          return;
        }
        final prev = _lastLikes;
        _lastLikes = s.likes;
        if (prev != null) {
          final others = _batcher.othersIn(s.likes - prev);
          // Une rafale de 200 cœurs n'en dessine pas 200.
          if (others > 0 && !_hearts.isClosed) _hearts.add(min(others, 12));
        }
        live.value = s;
      }, onError: (Object _) => _markEnded()),
    );

    final comments = _service
        .commentsRef(liveId)
        .orderByChild('at')
        .limitToLast(50);
    _subs
      ..add(
        comments.onChildAdded.listen((e) {
          final c = LiveComment.fromMap(e.snapshot.key ?? '', e.snapshot.value);
          if (c == null || _hides(c.uid)) return;
          _push(LiveCommentItem(c));
        }, onError: (Object _) {}),
      )
      ..add(
        comments.onChildRemoved.listen((e) {
          items.removeWhere(
            (i) => i is LiveCommentItem && i.comment.id == e.snapshot.key,
          );
        }, onError: (Object _) {}),
      );

    // Spectateurs déjà là : listés, mais pas annoncés comme arrivants.
    final viewersRef = _service.viewersRef(liveId);
    Set<String> already = const {};
    try {
      final snap = await viewersRef.get();
      final raw = snap.value;
      if (raw is Map) already = raw.keys.whereType<String>().toSet();
    } catch (_) {}
    if (_closed) return;
    _subs
      ..add(
        viewersRef.onChildAdded.listen((e) {
          final uid = e.snapshot.key;
          final raw = e.snapshot.value;
          if (uid == null || raw is! Map || _hides(uid)) return;
          final name = raw['name'] is String
              ? raw['name'] as String
              : 'Habitant';
          final photo = raw['photo'] is String ? raw['photo'] as String : null;
          viewers[uid] = LiveViewer(uid: uid, name: name, photo: photo);
          if (!already.contains(uid) && uid != me.uid) {
            _push(LiveJoinItem(uid: uid, name: name, at: DateTime.now()));
          }
        }, onError: (Object _) {}),
      )
      ..add(
        viewersRef.onChildRemoved.listen((e) {
          viewers.remove(e.snapshot.key);
        }, onError: (Object _) {}),
      );

    // Présence, réarmée à chaque reconnexion : un `onDisconnect` ne sert
    // qu'une fois.
    _subs.add(
      _service.connectedRef.onValue.listen((e) {
        if (e.snapshot.value == true && !_closed && !ended.value) {
          unawaited(_armPresence().catchError((Object _) {}));
        }
      }),
    );
  }

  Future<void> _armPresence() async {
    if (isHost) {
      final ref = _service.liveRef(liveId);
      await ref.onDisconnect().update({
        'hostOnline': false,
        'hostSeenAt': ServerValue.timestamp,
      });
      await ref.update({
        'hostOnline': true,
        'hostSeenAt': ServerValue.timestamp,
      });
    } else {
      final ref = _service.viewersRef(liveId).child(me.uid);
      await ref.onDisconnect().remove();
      await ref.set({
        'name': me.name,
        'photo': ?me.photo,
        'at': ServerValue.timestamp,
      });
    }
  }

  void _push(LiveFeedItem item) {
    items.add(item);
    final extra = items.length - LiveRules.maxFeedItems;
    if (extra > 0) items.removeRange(0, extra);
  }

  void _markEnded() {
    if (ended.value) return;
    ended.value = true;
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  /// Envoie un commentaire. Renvoie un message à montrer en cas de refus.
  Future<String?> sendComment(String raw) async {
    final text = LiveRules.cleanComment(raw);
    if (text == null || ended.value) return null;
    final now = DateTime.now();
    if (now.difference(_lastComment) < LiveRules.commentCooldown) {
      return 'Doucement : laissez passer une seconde entre deux messages.';
    }
    _lastComment = now;
    try {
      await _service.commentsRef(liveId).push().set({
        'uid': me.uid,
        'name': me.name,
        'photo': ?me.photo,
        'text': text,
        'at': ServerValue.timestamp,
      });
      return null;
    } catch (_) {
      return 'Message non envoyé.';
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      await _service.commentsRef(liveId).child(commentId).remove();
    } catch (_) {}
  }

  /// Un cœur : animé tout de suite, envoyé groupé.
  void tapHeart() {
    if (ended.value || _closed) return;
    if (!_hearts.isClosed) _hearts.add(1);
    _batcher.tap();
    _heartTimer ??= Timer(const Duration(milliseconds: 700), _flushHearts);
  }

  void _flushHearts() {
    _heartTimer = null;
    while (_batcher.hasPending) {
      final n = _batcher.take();
      _service
          .liveRef(liveId)
          .child('likes')
          .set(ServerValue.increment(n))
          .catchError((Object _) => _batcher.failed(n));
    }
  }

  /// Quitte le live : cœurs en attente envoyés, présence retirée, et
  /// `onDisconnect` annulé — sans quoi il réécrirait plus tard dans un
  /// live déjà clos.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartTimer?.cancel();
    if (!ended.value) _flushHearts();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      if (isHost) {
        await _service.liveRef(liveId).onDisconnect().cancel();
      } else {
        final ref = _service.viewersRef(liveId).child(me.uid);
        await ref.onDisconnect().cancel();
        if (!ended.value) await ref.remove();
      }
    } catch (_) {}
    await _hearts.close();
  }
}
