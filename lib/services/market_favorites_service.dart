import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/market_item.dart';

/// Favoris du marché — `users/{uid}/marketFavorites/{itemId}`.
///
/// Purement personnel : personne d'autre ne peut lire ce qu'un habitant a
/// mis de côté. Le compteur `favoritesCount` sur l'annonce en est le seul
/// reflet public, et sert au vendeur à mesurer l'intérêt réel.
///
/// Les ids sont gardés en mémoire ([ids]) pour que le cœur d'une carte
/// s'affiche déjà rempli au premier rendu, sans une lecture par annonce.
class MarketFavoritesService {
  final _db = FirebaseFirestore.instance;

  /// Ids des annonces mises de côté par l'utilisateur courant.
  final ids = <String>{};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('marketFavorites');

  bool isFavorite(String itemId) => ids.contains(itemId);

  /// Suit la liste de l'utilisateur connecté. [onChanged] permet à la
  /// grille de se redessiner quand un favori est posé depuis un autre
  /// écran (le détail, par exemple).
  void watch({required String uid, void Function()? onChanged}) {
    if (_uid == uid && _sub != null) return;
    _sub?.cancel();
    _uid = uid;
    _sub = _ref(uid).snapshots().listen((snap) {
      ids
        ..clear()
        ..addAll(snap.docs.map((d) => d.id));
      onChanged?.call();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    ids.clear();
  }

  /// Pose ou retire le favori. Renvoie l'état final.
  ///
  /// Le compteur public est mis à jour dans la foulée mais son échec
  /// n'annule pas le favori : le favori est la vérité, le compteur n'en
  /// est qu'un résumé.
  Future<bool> toggle({required String uid, required MarketItem item}) async {
    final wanted = !ids.contains(item.id);
    if (wanted) {
      ids.add(item.id);
      await _ref(uid).doc(item.id).set({
        'title': item.title,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      ids.remove(item.id);
      await _ref(uid).doc(item.id).delete();
    }

    try {
      await _db.collection('market').doc(item.id).update({
        'favoritesCount': FieldValue.increment(wanted ? 1 : -1),
      });
    } on FirebaseException catch (_) {
      // compteur indicatif
    }
    return wanted;
  }

  /// Charge les annonces mises de côté, les plus récemment ajoutées
  /// d'abord. Les favoris pointant vers une annonce supprimée sont
  /// nettoyés au passage — sinon la liste se remplirait de trous.
  Future<List<MarketItem>> fetchFavorites({
    required String uid,
    required MarketItem? Function(DocumentSnapshot<Map<String, dynamic>>) parse,
  }) async {
    final snap = await _ref(
      uid,
    ).orderBy('createdAt', descending: true).limit(100).get();
    final ordered = snap.docs.map((d) => d.id).toList();
    if (ordered.isEmpty) return [];

    final found = <String, MarketItem>{};
    // `whereIn` accepte 30 valeurs : on interroge par lots plutôt qu'une
    // lecture par favori.
    for (var i = 0; i < ordered.length; i += 30) {
      final chunk = ordered.sublist(i, (i + 30).clamp(0, ordered.length));
      final docs = await _db
          .collection('market')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in docs.docs) {
        final item = parse(doc);
        if (item != null) found[doc.id] = item;
      }
    }

    final missing = ordered.where((id) => !found.containsKey(id));
    for (final id in missing) {
      ids.remove(id);
      unawaited(_ref(uid).doc(id).delete().catchError((_) {}));
    }

    return [
      for (final id in ordered)
        if (found[id] != null) found[id]!,
    ];
  }
}
