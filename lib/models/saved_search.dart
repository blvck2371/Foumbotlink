import 'package:cloud_firestore/cloud_firestore.dart';

import 'market_item.dart';

/// Recherche enregistrée — `users/{uid}/savedSearches/{id}`.
///
/// C'est la fonction qui fait revenir les gens : plutôt que d'ouvrir
/// l'app tous les jours pour voir si une moto est passée, on décrit une
/// fois ce qu'on cherche et on reçoit une notification quand ça arrive.
/// Le rapprochement se fait côté serveur (`onMarketItemCreated`), qui
/// relit les recherches actives à chaque nouvelle annonce.
class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.label,
    required this.createdAt,
    this.query = '',
    this.category,
    this.listingType,
    this.place,
    this.maxPrice,
    this.active = true,
  });

  final String id;

  /// Nom donné par l'utilisateur, ou résumé auto des critères.
  final String label;

  final String query;
  final MarketCategory? category;
  final MarketListingType? listingType;
  final String? place;
  final int? maxPrice;
  final bool active;
  final DateTime createdAt;

  factory SavedSearch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SavedSearch(
      id: doc.id,
      label: d['label'] as String? ?? 'Recherche',
      query: d['query'] as String? ?? '',
      category: d['category'] != null
          ? MarketCategory.parse(d['category'] as String?)
          : null,
      listingType: d['listingType'] != null
          ? MarketListingType.parse(d['listingType'] as String?)
          : null,
      place: d['place'] as String?,
      maxPrice: (d['maxPrice'] as num?)?.toInt(),
      active: d['active'] as bool? ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'query': query.trim(),
        'category': category?.name,
        'listingType': listingType?.name,
        'place': place,
        'maxPrice': maxPrice,
        'active': active,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Résumé lisible des critères, pour la liste des alertes.
  String get criteriaLabel {
    final parts = <String>[
      if (query.trim().isNotEmpty) '« ${query.trim()} »',
      if (category != null) category!.label,
      if (listingType != null)
        listingType == MarketListingType.vente ? 'Ventes' : 'Recherches',
      if (place != null && place!.isNotEmpty) place!,
      if (maxPrice != null) 'jusqu’à $maxPrice FCFA',
    ];
    return parts.isEmpty ? 'Toutes les annonces' : parts.join(' · ');
  }
}
