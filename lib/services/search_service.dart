import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/demarche.dart';
import '../models/feed_item.dart';
import '../models/live_session.dart';
import '../models/market_item.dart';
import '../models/search_text.dart';
import '../models/search_trend.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'feed_memory.dart';
import 'feed_service.dart';
import 'live_service.dart';
import 'market_service.dart';
import 'moderation_service.dart';

/// Résultats d'une recherche, chaque famille déjà classée par pertinence.
class SearchResults {
  const SearchResults({
    this.query = '',
    this.users = const [],
    this.posts = const [],
    this.listings = const [],
    this.lives = const [],
    this.demarches = const [],
  });

  final String query;
  final List<UserProfile> users;
  final List<FeedItem> posts;
  final List<MarketItem> listings;
  final List<LiveSession> lives;
  final List<Demarche> demarches;

  bool get isEmpty =>
      users.isEmpty &&
      posts.isEmpty &&
      listings.isEmpty &&
      lives.isEmpty &&
      demarches.isEmpty;

  static const empty = SearchResults();
}

/// Recherche globale : comptes, publications, annonces, lives.
///
/// Les trois collections Firestore portent un champ `search` (débuts de
/// mots normalisés, tenu à jour par `functions/search_index.js`) : une
/// requête `array-contains` sur le jeton le plus précis de la saisie
/// ramène les candidats, puis l'app vérifie les autres mots et classe.
/// Les lives, eux, sont déjà en mémoire (temps réel) : filtrés sur place.
///
/// Le classement mêle la qualité de la correspondance (nom entier, début
/// de nom, faute de frappe tolérée) à des signaux propres à chaque
/// famille : abonnés et certification pour un compte, fraîcheur et
/// réactions pour une publication, fraîcheur pour une annonce — et la
/// proximité de la personne avec l'auteur, apprise dans le fil.
class SearchService extends GetxService {
  static const _userLimit = 40;
  static const _postLimit = 30;
  static const _listingLimit = 30;
  static const _maxRecent = 10;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  AuthService get _auth => Get.find<AuthService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  FeedService get _feed => Get.find<FeedService>();
  MarketService get _market => Get.find<MarketService>();
  LiveService get _lives => Get.find<LiveService>();

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  // ---------------------------------------------------------------------
  // Recherche
  // ---------------------------------------------------------------------

  Future<SearchResults> search(
    String query, {
    Set<String> following = const {},
  }) async {
    final tokens = searchQueryTokens(query);
    if (tokens.isEmpty) return SearchResults(query: query);
    final viewer = FeedMemory.instance.viewer(uid: _uid, following: following);

    final results = await Future.wait([
      _users(tokens, viewer.following, viewer.affinity),
      _posts(tokens, viewer.affinity),
      _listings(tokens),
      _demarches(tokens),
    ]);
    return SearchResults(
      query: query,
      users: results[0].cast<UserProfile>(),
      posts: results[1].cast<FeedItem>(),
      listings: results[2].cast<MarketItem>(),
      lives: searchLives(tokens),
      demarches: results[3].cast<Demarche>(),
    );
  }

  /// Le jeton qui filtre le mieux côté serveur : le plus long.
  static String _primary(List<String> tokens) =>
      tokens.reduce((a, b) => b.length > a.length ? b : a);

  /// Candidats d'une collection. Sans résultat, on élargit pas à pas
  /// (début du mot de plus en plus court, jusqu'à 2 lettres) pour
  /// rattraper une faute de frappe, même au milieu du mot (« fombot ») —
  /// le tri côté client ne garde ensuite que les correspondances tolérées.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _candidates(
    String collection,
    List<String> tokens,
    int limit,
  ) async {
    final primary = _primary(tokens);
    final attempts = <String>{
      primary,
      if (primary.length >= 4) ...[
        primary.substring(0, max(3, primary.length - 2)),
        primary.substring(0, 3),
        primary.substring(0, 2),
      ],
    };
    for (final prefix in attempts) {
      try {
        final snap = await _db
            .collection(collection)
            .where('search', arrayContains: prefix)
            .limit(prefix == primary ? limit : limit * 2)
            .get();
        if (snap.docs.isEmpty) continue;
        // Un repli large ramène aussi des documents sans rapport : on ne
        // s'arrête que si au moins un correspond vraiment.
        if (prefix == primary || snap.docs.any((d) => _anyMatch(tokens, d))) {
          return snap.docs;
        }
      } on FirebaseException catch (e) {
        developer.log('recherche $collection', name: 'Search', error: e);
        return const [];
      }
    }
    return const [];
  }

  /// Le document répond-il à tous les jetons, fautes tolérées ?
  static bool _anyMatch(
    List<String> tokens,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    if (d == null) return false;
    final text = [
      for (final k in const [
        'displayName',
        'title',
        'body',
        'authorName',
        'description',
        'location',
        'sellerName',
      ])
        if (d[k] is String) d[k] as String,
    ].join(' ');
    return matchScore(tokens, text) > 0;
  }

  Future<List<UserProfile>> _users(
    List<String> tokens,
    Set<String> following,
    Map<String, double> affinity,
  ) async {
    final docs = await _candidates('users', tokens, _userLimit);
    final scored = <(UserProfile, double)>[];
    for (final doc in docs) {
      final data = doc.data();
      if (data == null) continue;
      final UserProfile user;
      try {
        user = UserProfile.fromMap(doc.id, data);
      } catch (_) {
        continue;
      }
      if (_moderation.hides(user.uid)) continue;
      final match = matchScore(tokens, user.displayName);
      if (match == 0) continue;
      var s = match * 100;
      s += log(1 + user.followersCount) * 6;
      if (user.verified) s += 10;
      if (following.contains(user.uid)) s += 18;
      s += log(1 + (affinity[user.uid] ?? 0)) * 6;
      if (user.uid == _uid) s -= 15;
      scored.add((user, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  Future<List<FeedItem>> _posts(
    List<String> tokens,
    Map<String, double> affinity,
  ) async {
    final docs = await _candidates('posts', tokens, _postLimit);
    final now = DateTime.now();
    final scored = <(FeedItem, double)>[];
    for (final doc in docs) {
      if (doc.data() == null) continue;
      final post = _feed.parseDoc(doc);
      if (post.hidden || _moderation.hides(post.authorUid)) continue;
      final match = [
        matchScore(tokens, post.title),
        matchScore(tokens, '${post.title} ${post.body}') * 0.75,
        matchScore(tokens, post.authorName) * 0.7,
      ].reduce(max);
      if (match == 0) continue;
      final ageH = now.difference(post.publishedAt).inMinutes / 60;
      var s = match * 100;
      s += 30 * pow(1 + max(0, ageH) / 72, -0.7);
      s += log(1 + post.likesCount + 2 * post.commentsCount) * 5;
      s += log(1 + (affinity[post.authorUid] ?? 0)) * 4;
      scored.add((post, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return _oneStoryEach([for (final e in scored) e.$1]);
  }

  /// Une republication et son original ne s'affichent pas tous deux.
  static List<FeedItem> _oneStoryEach(List<FeedItem> ranked) {
    final seen = <String>{};
    return [
      for (final p in ranked)
        if (seen.add(p.repostOfId ?? p.id)) p,
    ];
  }

  Future<List<MarketItem>> _listings(List<String> tokens) async {
    final docs = await _candidates('market', tokens, _listingLimit);
    final now = DateTime.now();
    final scored = <(MarketItem, double)>[];
    for (final doc in docs) {
      final item = _market.parseDoc(doc);
      if (item == null || item.hidden || item.sold || item.isExpired) {
        continue;
      }
      if (_moderation.hides(item.sellerUid)) continue;
      final match = [
        matchScore(tokens, item.title),
        matchScore(tokens, '${item.title} ${item.description}') * 0.7,
        matchScore(tokens, item.location) * 0.6,
        matchScore(tokens, item.sellerName) * 0.6,
      ].reduce(max);
      if (match == 0) continue;
      final ageH = now.difference(item.bumpedAt).inMinutes / 60;
      var s = match * 100;
      s += 25 * pow(1 + max(0, ageH) / 96, -0.7);
      s += log(1 + item.favoritesCount) * 4;
      scored.add((item, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  /// Démarches publiées par les structures, lues une fois par session
  /// (quelques dizaines dans une commune). Chacune reste rattachée à sa
  /// structure.
  List<Demarche>? _publishedDemarches;

  Future<List<Demarche>> _demarches(List<String> tokens) async {
    if (_publishedDemarches == null) {
      try {
        final snap = await _db.collection('demarches').get();
        _publishedDemarches = snap.docs.map(Demarche.fromDoc).toList();
      } on FirebaseException catch (e) {
        developer.log('démarches', name: 'Search', error: e);
      }
    }
    final all = _publishedDemarches ?? const <Demarche>[];
    final scored = <(Demarche, double)>[];
    for (final d in all) {
      final match = [
        matchScore(tokens, d.title),
        matchScore(tokens, '${d.title} ${d.description}') * 0.7,
        matchScore(tokens, '${d.title} ${d.documents.join(' ')}') * 0.5,
        matchScore(tokens, d.category.label) * 0.6,
        matchScore(tokens, d.structureName) * 0.6,
      ].reduce(max);
      if (match == 0) continue;
      scored.add((d, match * 100));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  /// Lives en cours dont l'animateur ou le titre correspond.
  List<LiveSession> searchLives(List<String> tokens) {
    if (tokens.isEmpty) return const [];
    final scored = <(LiveSession, double)>[];
    for (final live in _lives.lives) {
      if (_moderation.hides(live.hostUid)) continue;
      final match = max(
        matchScore(tokens, live.hostName),
        matchScore(tokens, live.title) * 0.9,
      );
      if (match == 0) continue;
      scored.add((live, match * 100 + log(1 + live.viewers) * 5));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  /// Lives visibles en ce moment (suggestions sans saisie).
  List<LiveSession> get currentLives => [
    for (final l in _lives.lives)
      if (!_moderation.hides(l.hostUid)) l,
  ];

  // ---------------------------------------------------------------------
  // Suggestions
  // ---------------------------------------------------------------------

  /// Comptes les plus suivis de la commune, pour l'écran sans saisie.
  Future<List<UserProfile>> popularAccounts({int limit = 8}) async {
    try {
      final snap = await _db
          .collection('users')
          .orderBy('followersCount', descending: true)
          .limit(limit + 4)
          .get();
      final out = <UserProfile>[];
      for (final doc in snap.docs) {
        try {
          final u = UserProfile.fromMap(doc.id, doc.data());
          if (u.uid == _uid || _moderation.hides(u.uid)) continue;
          if (u.displayName.trim().isEmpty) continue;
          out.add(u);
        } catch (_) {}
      }
      return out.take(limit).toList();
    } on FirebaseException catch (e) {
      developer.log('comptes populaires', name: 'Search', error: e);
      return const [];
    }
  }

  // ---------------------------------------------------------------------
  // Tendances
  // ---------------------------------------------------------------------

  List<SearchTrend>? _trendsCache;
  DateTime? _trendsAt;
  final _recorded = <String>{};

  /// Les recherches les plus populaires du moment (gardées 5 minutes).
  Future<List<SearchTrend>> trending({int limit = 10}) async {
    final at = _trendsAt;
    if (_trendsCache != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return _trendsCache!;
    }
    try {
      final snap = await _db
          .collection('searchTrends')
          .where('hidden', isEqualTo: false)
          .orderBy('hot', descending: true)
          .limit(limit)
          .get();
      _trendsCache = [
        for (final doc in snap.docs) ?SearchTrend.fromMap(doc.data()),
      ];
      _trendsAt = DateTime.now();
      return _trendsCache!;
    } on FirebaseException catch (e) {
      developer.log('tendances', name: 'Search', error: e);
      return _trendsCache ?? const [];
    }
  }

  /// Tendances qui commencent comme la saisie — de quoi compléter
  /// pendant la frappe, au-delà des 10 premières tendances.
  Future<List<SearchTrend>> trendsMatching(String query) async {
    final tokens = searchQueryTokens(query);
    if (tokens.isEmpty) return const [];
    // Le mot le plus long départage le mieux ; tronqué comme à l'index.
    final word = (tokens.toList()..sort((a, b) => b.length - a.length)).first;
    final prefix = word.length > 15 ? word.substring(0, 15) : word;
    if (prefix.length < 2) return const [];
    try {
      final snap = await _db
          .collection('searchTrends')
          .where('prefixes', arrayContains: prefix)
          .where('hidden', isEqualTo: false)
          .orderBy('hot', descending: true)
          .limit(20)
          .get();
      return [for (final doc in snap.docs) ?SearchTrend.fromMap(doc.data())];
    } on FirebaseException catch (e) {
      developer.log('tendances (saisie)', name: 'Search', error: e);
      return const [];
    }
  }

  /// Compte une recherche aboutie dans les tendances. Le serveur ne la
  /// compte qu'une fois par jour et par compte ; ici, une fois par
  /// session suffit. Sans compte, rien n'est compté.
  void record(String query) {
    if (_uid == null) return;
    final key = searchWords(query).join(' ');
    if (key.length < 2 || !_recorded.add(key)) return;
    unawaited(
      FirebaseFunctions.instance
          .httpsCallable('recordSearch')
          .call<Map<String, dynamic>>({'query': query.trim()})
          .then((_) => _trendsAt = null)
          .catchError((Object e) {
            _recorded.remove(key);
            developer.log('recordSearch', name: 'Search', error: e);
            return null;
          }),
    );
  }

  // ---------------------------------------------------------------------
  // Historique
  // ---------------------------------------------------------------------

  String get _recentKey => 'search.recent.${_uid ?? '_'}';

  Future<List<String>> recentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? const [];
  }

  /// Ajoute [query] en tête de l'historique (sans doublon, casse et
  /// accents confondus).
  Future<List<String>> remember(String query) async {
    final q = query.trim();
    if (q.length < 2) return recentSearches();
    final prefs = await SharedPreferences.getInstance();
    final key = normalizeForSearch(q);
    final list = [
      q,
      for (final e in prefs.getStringList(_recentKey) ?? const <String>[])
        if (normalizeForSearch(e) != key) e,
    ].take(_maxRecent).toList();
    await prefs.setStringList(_recentKey, list);
    return list;
  }

  Future<List<String>> forget(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final e in prefs.getStringList(_recentKey) ?? const <String>[])
        if (e != query) e,
    ];
    await prefs.setStringList(_recentKey, list);
    return list;
  }

  Future<void> clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
  }
}
