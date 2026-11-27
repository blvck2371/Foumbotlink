import 'market_text.dart';

enum MarketCategory {
  immobilier,
  vehicules,
  electronique,
  agriculture,
  alimentation,
  vetements,
  services,
  divers;

  String get label => switch (this) {
    MarketCategory.immobilier => 'Immobilier',
    MarketCategory.vehicules => 'Véhicules',
    MarketCategory.electronique => 'Électronique',
    MarketCategory.agriculture => 'Agriculture',
    MarketCategory.alimentation => 'Alimentation',
    MarketCategory.vetements => 'Vêtements',
    MarketCategory.services => 'Services',
    MarketCategory.divers => 'Divers',
  };

  String get icon => switch (this) {
    MarketCategory.immobilier => '\u{1f3e0}',
    MarketCategory.vehicules => '\u{1f3cd}',
    MarketCategory.electronique => '\u{1f4f1}',
    MarketCategory.agriculture => '\u{1f33e}',
    MarketCategory.alimentation => '\u{1f34e}',
    MarketCategory.vetements => '\u{1f455}',
    MarketCategory.services => '\u{1f527}',
    MarketCategory.divers => '\u{1f4e6}',
  };

  static MarketCategory parse(String? name) => MarketCategory.values.firstWhere(
    (c) => c.name == name,
    orElse: () => MarketCategory.divers,
  );
}

enum MarketListingType {
  vente,
  achat,

  /// Mise en location : maison, chambre, véhicule, matériel, salle… Le
  /// prix s'entend par [RentalUnit] (heure, jour ou mois).
  location;

  /// Libellé d'une annonce de ce type.
  String get label => switch (this) {
    MarketListingType.vente => 'Vente',
    MarketListingType.achat => 'Recherche',
    MarketListingType.location => 'Location',
  };

  /// Libellé d'un filtre ou d'une alerte (pluriel).
  String get pluralLabel => switch (this) {
    MarketListingType.vente => 'Ventes',
    MarketListingType.achat => 'Recherches',
    MarketListingType.location => 'Locations',
  };

  static MarketListingType parse(String? name) => MarketListingType.values
      .firstWhere((t) => t.name == name, orElse: () => MarketListingType.vente);
}

/// Unité de temps d'une location : le prix est « par heure », « par
/// jour » ou « par mois », et la durée minimale se compte dans la même
/// unité.
enum RentalUnit {
  heure,
  jour,
  mois;

  /// « heure », pour « 2 000 FCFA / heure ».
  String get label => switch (this) {
    RentalUnit.heure => 'heure',
    RentalUnit.jour => 'jour',
    RentalUnit.mois => 'mois',
  };

  /// « Par heure », pour le sélecteur du formulaire.
  String get perLabel => switch (this) {
    RentalUnit.heure => 'Par heure',
    RentalUnit.jour => 'Par jour',
    RentalUnit.mois => 'Par mois',
  };

  /// « 3 heures », « 1 jour », « 6 mois » (« mois » est invariable).
  String count(int n) => switch (this) {
    RentalUnit.heure => n > 1 ? '$n heures' : '$n heure',
    RentalUnit.jour => n > 1 ? '$n jours' : '$n jour',
    RentalUnit.mois => '$n mois',
  };

  static RentalUnit? parse(String? name) {
    if (name == null) return null;
    for (final u in RentalUnit.values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

enum ItemCondition {
  neuf,
  bonEtat,
  occasion;

  String get label => switch (this) {
    ItemCondition.neuf => 'Neuf',
    ItemCondition.bonEtat => 'Bon état',
    ItemCondition.occasion => 'Occasion',
  };

  static ItemCondition? parse(String? name) {
    if (name == null) return null;
    return ItemCondition.values.firstWhere(
      (c) => c.name == name,
      orElse: () => ItemCondition.bonEtat,
    );
  }
}

/// Ordre d'affichage de la grille.
///
/// `aleatoire` est le défaut, et c'est un choix de fond : personne à
/// Foumbot ne paiera pour remonter en tête de liste. Sans remontée
/// payante, le tri chronologique donnerait toute la visibilité au dernier
/// qui a publié. Le mélange rend cette visibilité à tout le monde.
enum MarketSort {
  aleatoire,
  recent,
  prixCroissant,
  prixDecroissant;

  String get label => switch (this) {
    MarketSort.aleatoire => 'Au hasard',
    MarketSort.recent => 'Plus récentes',
    MarketSort.prixCroissant => 'Prix croissant',
    MarketSort.prixDecroissant => 'Prix décroissant',
  };
}

/// Localités proposées à la publication.
///
/// Liste fermée (plus « Autre » en saisie libre) : un champ texte libre
/// rendait le filtre par lieu inutilisable, chacun écrivant le même
/// quartier de trois façons. Les noms sont ceux des chefferies de 3ᵉ
/// degré et des villages de la commune de Foumbot recensés par le CVUC
/// (Communes et Villes Unies du Cameroun), précédés des deux repères
/// urbains que tout le monde emploie, et suivis des trois villes avec
/// lesquelles Foumbot commerce le plus.
abstract final class MarketPlaces {
  static const values = <String>[
    // Repères urbains
    'Foumbot centre',
    'Marché de Foumbot',

    // Chefferies et villages de la commune
    'Njimbot I',
    'Njimbot II',
    'Njimbot Fongué',
    'Mbantou',
    'Mbanjou',
    'Njincha',
    'Koundoumbain',
    'Compagny',
    'Fochiéya',
    'Fossett',
    'Fossang',
    'Baïgom',
    'Kouffen',
    'Koukpa',
    'Kouondja',
    'Kwetvu',
    'Maka',
    'Machouen',
    'Mangoum',
    'Mawouon',
    'Momoé',
    'Nkouonja',
    'Soukpen',
    'Tenjouonoun',

    // Axes de commerce voisins
    'Foumban',
    'Koutaba',
    'Bafoussam',
  ];

  /// Valeur retenue quand l'utilisateur saisit son lieu à la main.
  static const autre = 'Autre';
}

/// Durée de vie d'une annonce avant expiration automatique. Passé ce
/// délai elle sort de la grille publique ; son auteur la relance en un
/// geste depuis « Mes annonces ».
const kListingLifetime = Duration(days: 60);

/// Nombre maximum d'annonces qu'un compte peut publier par jour.
/// Contrôlé côté client pour le confort, et *appliqué* côté serveur
/// (`onMarketItemCreated` supprime les annonces au-delà du quota) :
/// c'est la barrière principale contre l'inondation de la grille par un
/// compte d'arnaqueur.
const kDailyListingLimit = 5;

class MarketItem {
  MarketItem({
    required this.id,
    required this.listingType,
    required this.category,
    required this.title,
    required this.sellerUid,
    required this.sellerName,
    required this.location,
    required this.createdAt,
    DateTime? bumpedAt,
    DateTime? expiresAt,
    this.description = '',
    this.price = 0,
    this.negotiable = false,
    this.priceOnRequest = false,
    this.condition,
    this.rentalUnit,
    this.rentalMinDuration,
    this.sold = false,
    this.soldAt,
    this.hasPhone = false,
    this.legacyPhone = '',
    this.hidden = false,
    this.viewsCount = 0,
    this.favoritesCount = 0,
    this.contactsCount = 0,
    List<String>? imageUrls,
    List<String>? keywords,
  }) : bumpedAt = bumpedAt ?? createdAt,
       expiresAt = expiresAt ?? createdAt.add(kListingLifetime),
       imageUrls = imageUrls ?? [],
       keywords = keywords ?? [];

  final String id;
  final MarketListingType listingType;
  final MarketCategory category;
  final String title;
  final String description;
  final int price;
  final bool negotiable;
  final bool priceOnRequest;
  final ItemCondition? condition;

  /// Location seulement : unité du prix (par heure, jour ou mois).
  final RentalUnit? rentalUnit;

  /// Location seulement : durée minimale, dans [rentalUnit] — `null` si
  /// le loueur n'en impose pas.
  final int? rentalMinDuration;

  final String sellerUid;
  final String sellerName;
  final String location;

  /// Date de publication d'origine — n'est jamais réécrite, y compris
  /// après une relance.
  final DateTime createdAt;

  /// Date de la dernière relance (= [createdAt] tant qu'il n'y en a pas
  /// eu). C'est le champ sur lequel la grille est triée : une annonce
  /// relancée remonte, sans perdre pour autant sa date réelle.
  final DateTime bumpedAt;

  /// Fin de validité. Passée cette date l'annonce n'apparaît plus dans la
  /// grille publique, mais reste dans « Mes annonces » pour être relancée.
  final DateTime expiresAt;

  /// `true` une fois l'article vendu / la recherche aboutie. L'annonce
  /// **disparaît alors de la grille publique** : à Foumbot, une grille
  /// pleine d'articles déjà vendus fait perdre son temps à tout le monde.
  /// Son auteur la retrouve dans « Mes annonces » et peut la remettre en
  /// vente.
  final bool sold;
  final DateTime? soldAt;

  /// Le vendeur a laissé un numéro. Le numéro lui-même **n'est pas dans
  /// ce document** : il vit dans `market/{id}/contact/info`, lisible
  /// seulement par un compte connecté (voir firestore.rules). Sans ça,
  /// une seule requête suffisait à aspirer tous les numéros de la
  /// commune.
  final bool hasPhone;

  /// Numéro des annonces publiées avant le déplacement du téléphone en
  /// sous-collection. Uniquement lu, jamais écrit — les nouvelles
  /// annonces laissent ce champ vide.
  final String legacyPhone;

  /// Masquée automatiquement au-delà du seuil de signalements
  /// (`onReportCreated`). Filtrée côté client comme côté requête.
  final bool hidden;

  final int viewsCount;
  final int favoritesCount;

  /// Nombre de fois où le numéro a été révélé / une discussion ouverte.
  /// Affiché au vendeur seul, comme repère d'intérêt réel.
  final int contactsCount;

  final List<String> imageUrls;

  /// Jetons de recherche calculés à la publication (titre + description,
  /// sans accents ni casse). Permet une vraie recherche côté serveur via
  /// `array-contains`, au lieu d'un filtre sur la page déjà chargée.
  final List<String> keywords;

  bool get hasImages => imageUrls.isNotEmpty;
  bool get hasDescription => description.isNotEmpty;
  bool get isTextOnly => !hasImages;
  bool get isImageOnly => hasImages && !hasDescription;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Visible dans la grille publique. Une annonce vendue, masquée par la
  /// modération ou expirée n'y figure pas.
  bool get isPublic => !sold && !hidden && !isExpired;

  /// Bientôt expirée — sert à proposer la relance à son auteur avant
  /// qu'elle ne disparaisse.
  bool get expiresSoon =>
      !isExpired && expiresAt.difference(DateTime.now()).inDays <= 7;

  int get daysLeft => expiresAt.difference(DateTime.now()).inDays;

  bool get isRental => listingType == MarketListingType.location;

  /// Unité effective d'une location (le jour si elle manque).
  RentalUnit get rentalUnitOrDefault => rentalUnit ?? RentalUnit.jour;

  /// « 25 000 FCFA », ou pour une location « 25 000 FCFA / mois ».
  String get priceLabel {
    if (priceOnRequest) return 'Prix à discuter';
    if (price == 0) return 'Gratuit';
    final amount = '${formatAmount(price)} FCFA';
    return isRental ? '$amount / ${rentalUnitOrDefault.label}' : amount;
  }

  /// « 3 mois minimum », ou vide.
  String get rentalDurationLabel {
    final n = rentalMinDuration;
    if (!isRental || n == null || n <= 0) return '';
    return '${rentalUnitOrDefault.count(n)} minimum';
  }

  String get typeLabel => listingType.label;

  /// Bandeau d'une annonce close : une location n'est pas « vendue ».
  String get closedLabel => switch (listingType) {
    MarketListingType.vente => 'Vendu',
    MarketListingType.achat => 'Trouvé',
    MarketListingType.location => 'Loué',
  };

  /// Action inverse : « Remettre en vente », « … en location ».
  String get reopenLabel => switch (listingType) {
    MarketListingType.vente => 'Remettre en vente',
    MarketListingType.achat => 'Relancer la recherche',
    MarketListingType.location => 'Remettre en location',
  };

  /// Message sous une annonce close.
  String get closedMessage => switch (listingType) {
    MarketListingType.vente => 'Cet article a été vendu',
    MarketListingType.achat => 'Cette recherche a abouti',
    MarketListingType.location => 'Ce bien est déjà loué',
  };

  /// Texte prêt à partager (bouton « Partager » du détail).
  String get shareText {
    final lines = <String>[
      title,
      priceLabel,
      if (rentalDurationLabel.isNotEmpty) rentalDurationLabel,
      if (location.isNotEmpty) '📍 $location',
      '',
      'Vu sur Foumbot Link',
    ];
    return lines.join('\n');
  }

  MarketItem copyWith({
    MarketListingType? listingType,
    MarketCategory? category,
    String? title,
    String? description,
    int? price,
    bool? negotiable,
    bool? priceOnRequest,
    ItemCondition? condition,
    bool clearCondition = false,
    RentalUnit? rentalUnit,
    int? rentalMinDuration,
    bool clearRental = false,
    String? location,
    DateTime? bumpedAt,
    DateTime? expiresAt,
    bool? sold,
    DateTime? soldAt,
    bool? hasPhone,
    bool? hidden,
    int? viewsCount,
    int? favoritesCount,
    int? contactsCount,
    List<String>? imageUrls,
    List<String>? keywords,
  }) => MarketItem(
    id: id,
    listingType: listingType ?? this.listingType,
    category: category ?? this.category,
    title: title ?? this.title,
    description: description ?? this.description,
    price: price ?? this.price,
    negotiable: negotiable ?? this.negotiable,
    priceOnRequest: priceOnRequest ?? this.priceOnRequest,
    condition: clearCondition ? null : (condition ?? this.condition),
    rentalUnit: clearRental ? null : (rentalUnit ?? this.rentalUnit),
    rentalMinDuration: clearRental
        ? null
        : (rentalMinDuration ?? this.rentalMinDuration),
    sellerUid: sellerUid,
    sellerName: sellerName,
    location: location ?? this.location,
    createdAt: createdAt,
    bumpedAt: bumpedAt ?? this.bumpedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    sold: sold ?? this.sold,
    soldAt: sold == false ? null : (soldAt ?? this.soldAt),
    hasPhone: hasPhone ?? this.hasPhone,
    legacyPhone: legacyPhone,
    hidden: hidden ?? this.hidden,
    viewsCount: viewsCount ?? this.viewsCount,
    favoritesCount: favoritesCount ?? this.favoritesCount,
    contactsCount: contactsCount ?? this.contactsCount,
    imageUrls: imageUrls ?? this.imageUrls,
    keywords: keywords ?? this.keywords,
  );
}

/// À quel point [candidate] ressemble à [reference], du point de vue de
/// quelqu'un qui regarde [reference].
///
/// Firestore ne sait pas faire ce classement : une requête n'accepte
/// qu'un seul `array-contains`, et ne pondère rien. On lit donc un vivier
/// par catégorie, et on le classe ici — ce qui a l'avantage de rendre la
/// notion de « similaire » lisible et vérifiable, au lieu de la laisser
/// implicite dans la forme d'une requête.
///
/// Les poids traduisent ce qui compte pour un acheteur de Foumbot, dans
/// cet ordre : les mots de l'annonce, puis l'intention (vendre ou
/// chercher), puis le prix, puis le lieu.
int marketSimilarityScore(MarketItem reference, MarketItem candidate) {
  var score = 0;

  // La catégorie est le socle. Comptée explicitement, même si le vivier
  // est déjà filtré dessus : la fonction doit pouvoir se juger seule.
  if (candidate.category == reference.category) score += 2;

  // Les mots partagés sont le signal le plus fort : deux annonces qui
  // disent « moto Sanili » se ressemblent davantage que deux annonces de
  // la même catégorie au hasard. Plafonné à trois mots — au-delà, c'est
  // souvent du remplissage commun à toutes les annonces.
  final shared = candidate.keywords
      .toSet()
      .intersection(reference.keywords.toSet())
      .length;
  score += 4 * (shared > 3 ? 3 : shared);

  // Vendre et chercher sont deux intentions opposées : proposer une
  // demande d'achat à quelqu'un qui regarde une vente est presque
  // toujours hors sujet.
  if (candidate.listingType == reference.listingType) {
    score += 3;
  } else {
    score -= 4;
  }

  // Le prix ne compte que si les deux annonces en affichent un : « prix à
  // discuter » n'est pas une information, ce n'est donc ni un
  // rapprochement ni un écart.
  if (!reference.priceOnRequest &&
      !candidate.priceOnRequest &&
      reference.price > 0 &&
      candidate.price > 0) {
    final ratio = candidate.price / reference.price;
    if (ratio >= 0.7 && ratio <= 1.3) {
      score += 3;
    } else if (ratio >= 0.4 && ratio <= 2.5) {
      score += 1;
    }
  }

  if (candidate.condition != null &&
      candidate.condition == reference.condition) {
    score += 1;
  }

  // Dans une commune, le quartier décide souvent de la rencontre.
  final place = reference.location.trim().toLowerCase();
  if (place.isNotEmpty && candidate.location.trim().toLowerCase() == place) {
    score += 2;
  }

  return score;
}
