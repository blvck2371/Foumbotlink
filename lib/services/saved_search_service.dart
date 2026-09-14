import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/market_filters.dart';
import '../models/saved_search.dart';

/// Recherches enregistrées et alertes — `users/{uid}/savedSearches`.
///
/// Le rapprochement annonce ↔ recherche est fait côté serveur par
/// `onMarketItemCreated` : à chaque publication il relit les recherches
/// actives et notifie celles qui correspondent. Le client ne fait donc
/// que du CRUD ici.
class SavedSearchService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('savedSearches');

  Future<List<SavedSearch>> fetch(String uid) async {
    final snap = await _ref(
      uid,
    ).orderBy('createdAt', descending: true).limit(30).get();
    return snap.docs.map(SavedSearch.fromDoc).toList();
  }

  Stream<List<SavedSearch>> watch(String uid) => _ref(uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(SavedSearch.fromDoc).toList());

  /// Enregistre les filtres courants comme alerte. [label] par défaut est
  /// le résumé des critères, que l'utilisateur peut renommer ensuite.
  Future<SavedSearch> create({
    required String uid,
    required MarketFilters filters,
    String? label,
  }) async {
    final draft = SavedSearch(
      id: '_',
      label: '',
      createdAt: DateTime.now(),
      query: filters.query,
      category: filters.category,
      listingType: filters.listingType,
      place: filters.place,
      maxPrice: filters.maxPrice,
    );
    final resolved = label?.trim().isNotEmpty == true
        ? label!.trim()
        : draft.criteriaLabel;

    final doc = await _ref(uid).add({...draft.toMap(), 'label': resolved});
    return SavedSearch(
      id: doc.id,
      label: resolved,
      createdAt: DateTime.now(),
      query: filters.query,
      category: filters.category,
      listingType: filters.listingType,
      place: filters.place,
      maxPrice: filters.maxPrice,
    );
  }

  Future<void> setActive({
    required String uid,
    required String id,
    required bool active,
  }) => _ref(uid).doc(id).update({'active': active});

  Future<void> delete({required String uid, required String id}) =>
      _ref(uid).doc(id).delete();
}
