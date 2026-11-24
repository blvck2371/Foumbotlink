import 'market_item.dart';

/// Critères de la grille — ce que l'utilisateur a choisi dans la barre de
/// filtres et la feuille « Filtrer ».
///
/// Immuable et comparable : le contrôleur remplace l'objet entier plutôt
/// que d'exposer une dizaine de `Rx` séparés, et un `==` suffit à savoir
/// si un rechargement est nécessaire.
class MarketFilters {
  const MarketFilters({
    this.category,
    this.listingType,
    this.query = '',
    this.place,
    this.condition,
    this.minPrice,
    this.maxPrice,
    this.sort = MarketSort.aleatoire,
  });

  final MarketCategory? category;
  final MarketListingType? listingType;
  final String query;
  final String? place;
  final ItemCondition? condition;
  final int? minPrice;
  final int? maxPrice;
  final MarketSort sort;

  /// Filtres qui exigent une nouvelle requête serveur. Le tri, le prix,
  /// l'état et le lieu s'appliquent sur la fenêtre déjà chargée : les
  /// ajouter à la requête Firestore imposerait un index composite par
  /// combinaison, pour un gain nul à l'échelle de la commune.
  bool sameQueryAs(MarketFilters other) =>
      category == other.category &&
      listingType == other.listingType &&
      query.trim() == other.query.trim();

  bool get hasRefinements =>
      place != null ||
      condition != null ||
      minPrice != null ||
      maxPrice != null;

  /// Nombre de filtres actifs, affiché en pastille sur le bouton
  /// « Filtrer ».
  int get activeCount => [
    category != null,
    listingType != null,
    place != null,
    condition != null,
    minPrice != null,
    maxPrice != null,
  ].where((e) => e).length;

  /// Vrai si [item] satisfait les critères appliqués côté client.
  bool matches(MarketItem item) {
    if (place != null && item.location != place) return false;
    if (condition != null && item.condition != condition) return false;
    // Une annonce « prix à discuter » n'a pas de montant comparable : on
    // la garde tant qu'aucune fourchette n'est demandée, et on l'écarte
    // dès que l'utilisateur raisonne en prix.
    if (minPrice != null || maxPrice != null) {
      if (item.priceOnRequest) return false;
      if (minPrice != null && item.price < minPrice!) return false;
      if (maxPrice != null && item.price > maxPrice!) return false;
    }
    return true;
  }

  MarketFilters copyWith({
    MarketCategory? category,
    bool clearCategory = false,
    MarketListingType? listingType,
    bool clearListingType = false,
    String? query,
    String? place,
    bool clearPlace = false,
    ItemCondition? condition,
    bool clearCondition = false,
    int? minPrice,
    bool clearMinPrice = false,
    int? maxPrice,
    bool clearMaxPrice = false,
    MarketSort? sort,
  }) => MarketFilters(
    category: clearCategory ? null : (category ?? this.category),
    listingType: clearListingType ? null : (listingType ?? this.listingType),
    query: query ?? this.query,
    place: clearPlace ? null : (place ?? this.place),
    condition: clearCondition ? null : (condition ?? this.condition),
    minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
    maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
    sort: sort ?? this.sort,
  );

  /// Remet à zéro tout sauf le tri, que l'utilisateur a choisi à part.
  MarketFilters cleared() => MarketFilters(sort: sort);

  @override
  bool operator ==(Object other) =>
      other is MarketFilters &&
      other.category == category &&
      other.listingType == listingType &&
      other.query.trim() == query.trim() &&
      other.place == place &&
      other.condition == condition &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    category,
    listingType,
    query.trim(),
    place,
    condition,
    minPrice,
    maxPrice,
    sort,
  );
}
