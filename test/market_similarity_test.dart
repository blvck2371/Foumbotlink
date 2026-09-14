import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/market_item.dart';

void main() {
  final now = DateTime(2026, 9, 13);

  MarketItem item({
    String id = 'x',
    MarketCategory category = MarketCategory.vehicules,
    MarketListingType type = MarketListingType.vente,
    int price = 500000,
    bool priceOnRequest = false,
    ItemCondition? condition = ItemCondition.bonEtat,
    String location = 'Foumbot Centre',
    List<String> keywords = const ['moto', 'sanili'],
    String sellerUid = 's1',
  }) => MarketItem(
    id: id,
    listingType: type,
    category: category,
    title: 'Annonce $id',
    description: '',
    price: price,
    negotiable: false,
    priceOnRequest: priceOnRequest,
    condition: condition,
    sellerUid: sellerUid,
    sellerName: 'Vendeur',
    location: location,
    createdAt: now,
    bumpedAt: now,
    expiresAt: now.add(const Duration(days: 30)),
    keywords: keywords,
  );

  group('marketSimilarityScore', () {
    test('deux annonces quasi identiques obtiennent un score élevé', () {
      final reference = item();
      final twin = item(id: 'y', sellerUid: 's2');

      // Catégorie + 2 mots + même type + prix identique + état + lieu.
      expect(marketSimilarityScore(reference, twin), greaterThanOrEqualTo(15));
    });

    test('les mots partagés pèsent plus que tout le reste', () {
      final reference = item();
      final sameWords = item(
        id: 'mots',
        price: 5000000,
        condition: ItemCondition.neuf,
        location: 'Ailleurs',
      );
      final nothingShared = item(id: 'rien', keywords: const ['table', 'bois']);

      expect(
        marketSimilarityScore(reference, sameWords),
        greaterThan(marketSimilarityScore(reference, nothingShared)),
      );
    });

    test('une intention opposée est pénalisée, pas ignorée', () {
      // Proposer une demande d'achat à quelqu'un qui regarde une vente
      // est presque toujours hors sujet.
      final reference = item();
      final sameIntent = item(id: 'vente');
      final opposite = item(id: 'achat', type: MarketListingType.achat);

      expect(
        marketSimilarityScore(reference, opposite),
        lessThan(marketSimilarityScore(reference, sameIntent)),
      );
    });

    test('un prix voisin rapproche, un prix très éloigné non', () {
      final reference = item(price: 500000);
      final close = item(id: 'proche', price: 550000);
      final far = item(id: 'loin', price: 50000000);

      expect(
        marketSimilarityScore(reference, close),
        greaterThan(marketSimilarityScore(reference, far)),
      );
    });

    test('« prix à discuter » n’est ni un rapprochement ni un écart', () {
      // Ce n'est pas une information : la traiter comme un prix de zéro
      // ferait passer toutes ces annonces pour des occasions.
      final reference = item(price: 500000);
      final onRequest = item(id: 'discuter', priceOnRequest: true, price: 0);
      final samePriceless = item(id: 'ni-l-un-ni-l-autre', price: 500000);

      final withPrice = marketSimilarityScore(reference, samePriceless);
      final without = marketSimilarityScore(reference, onRequest);
      expect(without, lessThan(withPrice));
      expect(without, greaterThan(0));
    });

    test('une autre catégorie perd le socle', () {
      final reference = item();
      final other = item(
        id: 'autre',
        category: MarketCategory.immobilier,
        keywords: const [],
      );

      expect(
        marketSimilarityScore(reference, other),
        lessThan(marketSimilarityScore(reference, item(id: 'meme'))),
      );
    });

    test('le même quartier compte', () {
      final reference = item(location: 'Foumbot Centre');
      final sameArea = item(id: 'ici', location: 'foumbot centre');
      final elsewhere = item(id: 'ailleurs', location: 'Koutaba');

      expect(
        marketSimilarityScore(reference, sameArea),
        greaterThan(marketSimilarityScore(reference, elsewhere)),
      );
    });

    test('le classement met les plus proches en tête', () {
      final reference = item();
      final candidates =
          [
            item(
              id: 'hors-sujet',
              keywords: const ['savon'],
              type: MarketListingType.achat,
            ),
            item(id: 'proche', price: 520000),
            item(id: 'moyen', keywords: const ['moto'], price: 9000000),
          ]..sort(
            (a, b) => marketSimilarityScore(
              reference,
              b,
            ).compareTo(marketSimilarityScore(reference, a)),
          );

      expect(candidates.first.id, 'proche');
      expect(candidates.last.id, 'hors-sujet');
    });
  });
}
