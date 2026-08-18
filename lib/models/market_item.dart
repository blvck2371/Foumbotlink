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
}

enum MarketListingType { vente, achat }

enum ItemCondition {
  neuf,
  bonEtat,
  occasion;

  String get label => switch (this) {
        ItemCondition.neuf => 'Neuf',
        ItemCondition.bonEtat => 'Bon état',
        ItemCondition.occasion => 'Occasion',
      };
}

class MarketItem {
  MarketItem({
    required this.id,
    required this.listingType,
    required this.category,
    required this.title,
    required this.sellerUid,
    required this.sellerName,
    required this.sellerPhone,
    required this.location,
    required this.createdAt,
    this.description = '',
    this.price = 0,
    this.negotiable = false,
    this.priceOnRequest = false,
    this.condition,
    List<String>? imageUrls,
  }) : imageUrls = imageUrls ?? [];

  final String id;
  final MarketListingType listingType;
  final MarketCategory category;
  final String title;
  final String description;
  final int price;
  final bool negotiable;
  final bool priceOnRequest;
  final ItemCondition? condition;
  final String sellerUid;
  final String sellerName;
  final String sellerPhone;
  final String location;
  final DateTime createdAt;
  final List<String> imageUrls;

  bool get hasImages => imageUrls.isNotEmpty;
  bool get hasDescription => description.isNotEmpty;
  bool get isTextOnly => !hasImages;
  bool get isImageOnly => hasImages && !hasDescription;

  String get priceLabel {
    if (priceOnRequest) return 'Prix à discuter';
    if (price == 0) return 'Gratuit';
    final formatted = price.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]} ',
        );
    return '$formatted FCFA';
  }

  String get typeLabel =>
      listingType == MarketListingType.vente ? 'Vente' : 'Recherche';
}
