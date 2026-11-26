import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'feed_ranker.dart';

/// Ce que l'appareil retient du comportement de la personne dans le fil,
/// pour personnaliser le classement ([FeedRanker]) :
///
/// - les publications **vues** (affichées au moins une seconde à
///   l'écran), pour ne pas resservir le même fil à chaque visite ;
/// - l'**affinité** avec chaque auteur, nourrie par ses gestes — aimer,
///   commenter, ouvrir, republier, enregistrer, s'attarder sur une
///   publication. Elle s'amortit avec le temps (demi-vie 14 jours) : on
///   suit les goûts du moment, pas ceux d'il y a six mois.
///
/// Stocké par compte (deux comptes sur un même téléphone ne se mélangent
/// pas), borné en taille, écrit en différé pour ne pas solliciter le
/// disque à chaque geste. Fonctionne aussi sur le web.
class FeedMemory {
  FeedMemory._();

  static final instance = FeedMemory._();

  /// Poids des gestes sur l'affinité avec l'auteur.
  static const like = 3.0;
  static const unlike = -2.0;
  static const comment = 4.0;
  static const open = 2.0;
  static const repost = 4.0;
  static const save = 3.0;
  static const dwell = 1.0;
  static const profileVisit = 1.5;

  static const _maxSeen = 2000;
  static const _maxAuthors = 400;
  static const _halfLifeDays = 14.0;

  String _account = '_';
  SharedPreferences? _prefs;
  Future<void>? _loading;
  Timer? _flush;

  /// id → [nombre de vues, dernière vue en ms].
  final _seen = <String, List<int>>{};

  /// auteur → [affinité, date de la valeur en ms].
  final _affinity = <String, List<num>>{};

  /// Publications déjà comptées comme vues pendant cette session : une
  /// même carte qui repasse à l'écran au fil du défilement ne compte
  /// qu'une fois par visite.
  final _seenThisSession = <String>{};

  /// Charge la mémoire du compte [uid] (`null` = visiteur non connecté).
  Future<void> use(String? uid) {
    final account = uid ?? '_';
    if (account == _account && _loading != null) return _loading!;
    _flushNow();
    _account = account;
    _seen.clear();
    _affinity.clear();
    _seenThisSession.clear();
    return _loading = _load();
  }

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final seen = _prefs!.getString('feed.seen.$_account');
      if (seen != null) {
        (jsonDecode(seen) as Map<String, dynamic>).forEach((k, v) {
          _seen[k] = (v as List).cast<num>().map((e) => e.toInt()).toList();
        });
      }
      final aff = _prefs!.getString('feed.affinity.$_account');
      if (aff != null) {
        (jsonDecode(aff) as Map<String, dynamic>).forEach((k, v) {
          _affinity[k] = (v as List).cast<num>();
        });
      }
    } catch (_) {
      // Mémoire illisible (format changé, stockage plein) : on repart de
      // zéro plutôt que de bloquer le fil.
      _seen.clear();
      _affinity.clear();
    }
  }

  /// Instantané pour le classement.
  FeedViewer viewer({
    String? uid,
    Set<String> following = const {},
    Set<String> liked = const {},
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return FeedViewer(
      uid: uid,
      following: following,
      liked: liked,
      seen: {
        for (final e in _seen.entries)
          e.key: SeenMark(
            e.value[0],
            DateTime.fromMillisecondsSinceEpoch(e.value[1]),
          ),
      },
      affinity: {
        for (final e in _affinity.entries) e.key: _decayed(e.value, at),
      },
    );
  }

  bool seenBefore(String postId) => _seen.containsKey(postId);

  /// La carte [postId] est restée visible : elle compte comme vue.
  void markSeen(String postId) {
    if (!_seenThisSession.add(postId)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _seen.remove(postId);
    // Réinsérée en fin : l'ordre d'insertion sert à évincer les plus
    // anciennes vues quand la mémoire déborde.
    _seen[postId] = [(prev?[0] ?? 0) + 1, now];
    while (_seen.length > _maxSeen) {
      _seen.remove(_seen.keys.first);
    }
    _scheduleFlush();
  }

  /// Un geste envers une publication de [authorUid].
  void bump(String? authorUid, double weight) {
    if (authorUid == null || authorUid.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = _affinity.remove(authorUid);
    final value = current == null ? 0.0 : _decayed(current, now);
    _affinity[authorUid] = [max(0, value + weight), now];
    while (_affinity.length > _maxAuthors) {
      _affinity.remove(_affinity.keys.first);
    }
    _scheduleFlush();
  }

  static double _decayed(List<num> entry, int nowMs) {
    final days = max(0, nowMs - entry[1]) / Duration.millisecondsPerDay;
    return (entry[0] * pow(0.5, days / _halfLifeDays)).toDouble();
  }

  void _scheduleFlush() {
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 2), _flushNow);
  }

  void _flushNow() {
    _flush?.cancel();
    _flush = null;
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setString('feed.seen.$_account', jsonEncode(_seen)));
    unawaited(
      prefs.setString('feed.affinity.$_account', jsonEncode(_affinity)),
    );
  }
}
