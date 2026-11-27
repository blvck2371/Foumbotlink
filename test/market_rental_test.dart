import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/market_item.dart';

MarketItem _item(MarketListingType type, {RentalUnit? unit, int? min}) =>
    MarketItem(
      id: 'x',
      listingType: type,
      category: MarketCategory.immobilier,
      title: 'Studio',
      sellerUid: 'u',
      sellerName: 'A',
      location: 'Foumbot centre',
      createdAt: DateTime(2026, 11, 27),
      price: 25000,
      rentalUnit: unit,
      rentalMinDuration: min,
    );

void main() {
  test('le prix d’une location précise l’unité', () {
    expect(
      _item(MarketListingType.location, unit: RentalUnit.mois).priceLabel,
      '25 000 FCFA / mois',
    );
    expect(
      _item(MarketListingType.location, unit: RentalUnit.heure).priceLabel,
      endsWith('/ heure'),
    );
    // Sans unité enregistrée, le jour par défaut.
    expect(_item(MarketListingType.location).priceLabel, endsWith('/ jour'));
    expect(_item(MarketListingType.vente).priceLabel, '25 000 FCFA');
  });

  test('durée minimale', () {
    expect(
      _item(MarketListingType.location, unit: RentalUnit.mois, min: 6)
          .rentalDurationLabel,
      '6 mois minimum',
    );
    expect(
      _item(MarketListingType.location, unit: RentalUnit.jour, min: 3)
          .rentalDurationLabel,
      '3 jours minimum',
    );
    expect(
      _item(MarketListingType.location, unit: RentalUnit.heure, min: 1)
          .rentalDurationLabel,
      '1 heure minimum',
    );
    expect(_item(MarketListingType.location).rentalDurationLabel, '');
    expect(
      _item(MarketListingType.vente, min: 3).rentalDurationLabel,
      '',
    );
  });

  test('libellés de type et d’état', () {
    final l = _item(MarketListingType.location);
    expect(l.typeLabel, 'Location');
    expect(l.closedLabel, 'Loué');
    expect(MarketListingType.parse('location'), MarketListingType.location);
    expect(RentalUnit.parse('mois'), RentalUnit.mois);
    expect(RentalUnit.parse('semaine'), isNull);
  });
}
