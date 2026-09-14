import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/market_filters.dart';
import 'package:foumbotlik/models/market_item.dart';
import 'package:foumbotlik/services/scam_guard.dart';

MarketItem item({
  int price = 100000,
  bool priceOnRequest = false,
  bool sold = false,
  bool hidden = false,
  String location = 'Foumbot centre',
  ItemCondition? condition,
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final created = createdAt ?? DateTime.now();
  return MarketItem(
    id: 'a1',
    listingType: MarketListingType.vente,
    category: MarketCategory.vehicules,
    title: 'Moto',
    sellerUid: 'v',
    sellerName: 'Vendeur',
    location: location,
    createdAt: created,
    expiresAt: expiresAt,
    price: price,
    priceOnRequest: priceOnRequest,
    sold: sold,
    hidden: hidden,
    condition: condition,
  );
}

void main() {
  group('MarketItem — visibilité publique', () {
    test('une annonce fraîche est publique', () {
      expect(item().isPublic, isTrue);
    });

    test('une annonce vendue quitte la grille publique', () {
      expect(item(sold: true).isPublic, isFalse);
    });

    test('une annonce masquée par la modération est retirée', () {
      expect(item(hidden: true).isPublic, isFalse);
    });

    test('une annonce expirée est retirée', () {
      final old = DateTime.now().subtract(const Duration(days: 90));
      final listing = item(
        createdAt: old,
        expiresAt: old.add(kListingLifetime),
      );
      expect(listing.isExpired, isTrue);
      expect(listing.isPublic, isFalse);
    });

    test('la durée de vie par défaut part de la publication', () {
      final created = DateTime(2026, 1, 1);
      expect(
        item(createdAt: created).expiresAt,
        created.add(kListingLifetime),
      );
    });

    test('bumpedAt vaut createdAt tant qu’il n’y a pas eu de relance', () {
      final created = DateTime(2026, 1, 1);
      expect(item(createdAt: created).bumpedAt, created);
    });
  });

  group('MarketFilters.matches', () {
    test('sans critère, tout passe', () {
      expect(const MarketFilters().matches(item()), isTrue);
    });

    test('filtre par lieu', () {
      const f = MarketFilters(place: 'Koutaba');
      expect(f.matches(item(location: 'Koutaba')), isTrue);
      expect(f.matches(item(location: 'Foumbot centre')), isFalse);
    });

    test('filtre par état', () {
      const f = MarketFilters(condition: ItemCondition.neuf);
      expect(f.matches(item(condition: ItemCondition.neuf)), isTrue);
      expect(f.matches(item(condition: ItemCondition.occasion)), isFalse);
    });

    test('fourchette de prix, bornes incluses', () {
      const f = MarketFilters(minPrice: 100, maxPrice: 200);
      expect(f.matches(item(price: 100)), isTrue);
      expect(f.matches(item(price: 200)), isTrue);
      expect(f.matches(item(price: 99)), isFalse);
      expect(f.matches(item(price: 201)), isFalse);
    });

    test(
      '« prix à discuter » est écarté dès qu’une fourchette est demandée',
      () {
        final sansMontant = item(priceOnRequest: true, price: 0);
        expect(const MarketFilters().matches(sansMontant), isTrue);
        expect(
          const MarketFilters(maxPrice: 500000).matches(sansMontant),
          isFalse,
        );
      },
    );
  });

  group('MarketFilters — rechargement', () {
    test('changer de tri ne change pas la requête serveur', () {
      const a = MarketFilters(category: MarketCategory.vehicules);
      final b = a.copyWith(sort: MarketSort.prixCroissant);
      expect(a.sameQueryAs(b), isTrue);
      expect(a == b, isFalse);
    });

    test('changer de catégorie change la requête serveur', () {
      const a = MarketFilters(category: MarketCategory.vehicules);
      final b = a.copyWith(category: MarketCategory.immobilier);
      expect(a.sameQueryAs(b), isFalse);
    });

    test('activeCount compte les filtres posés, pas le tri', () {
      const f = MarketFilters(
        category: MarketCategory.vehicules,
        place: 'Koutaba',
        maxPrice: 500000,
        sort: MarketSort.recent,
      );
      expect(f.activeCount, 3);
    });

    test('cleared() garde le tri choisi', () {
      const f = MarketFilters(
        category: MarketCategory.vehicules,
        sort: MarketSort.prixCroissant,
      );
      final cleared = f.cleared();
      expect(cleared.category, isNull);
      expect(cleared.sort, MarketSort.prixCroissant);
    });
  });

  group('ScamGuard', () {
    test('un message ordinaire ne déclenche rien', () {
      expect(ScamGuard.isSuspicious('Bonjour, la moto est disponible ?'),
          isFalse);
      expect(ScamGuard.warningFor('On se voit demain au marché'), isNull);
    });

    test('une demande d’acompte est repérée', () {
      expect(
        ScamGuard.analyze('Envoie un acompte avant que je réserve'),
        contains(ScamSignal.avance),
      );
    });

    test('un transfert Mobile Money est repéré, accents compris', () {
      expect(
        ScamGuard.analyze('Fais le dépôt par Orange Money'),
        contains(ScamSignal.transfert),
      );
    });

    test('un envoi à distance est repéré', () {
      expect(
        ScamGuard.analyze('Je suis en voyage, je te l’expédie par bus'),
        contains(ScamSignal.livraisonDistante),
      );
    });

    test('une demande de code est repérée', () {
      expect(
        ScamGuard.analyze('Donne-moi ton code de vérification'),
        contains(ScamSignal.donneesPersonnelles),
      );
    });

    test(
      'les mots courts ne se déclenchent pas dans un autre mot',
      () {
        // « om » et « pin » sont cherchés comme mots entiers : sans cette
        // précaution, l’alerte se déclencherait sur « ombre » ou
        // « pinceau » et perdrait tout crédit.
        expect(ScamGuard.isSuspicious('Il y a de l’ombre sur la photo'),
            isFalse);
        expect(ScamGuard.isSuspicious('Je vends un pinceau'), isFalse);
      },
    );

    test('l’avertissement se limite à deux signaux', () {
      final warning = ScamGuard.warningFor(
        'Envoie un acompte par Orange Money, je suis en voyage, '
        'donne ton code de vérification, urgent urgent',
      );
      expect(warning, isNotNull);
      expect(warning!.split('\n\n').length, 2);
    });
  });
}
