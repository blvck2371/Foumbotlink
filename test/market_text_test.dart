import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/market_text.dart';

void main() {
  group('marketKeywords', () {
    test('minuscules, sans accents, mots de 3 lettres et plus', () {
      expect(
        marketKeywords('Moto Véhicule à vendre État neuf',
            'Très bon état, négociable'),
        ['moto', 'vehicule', 'vendre', 'etat', 'neuf', 'tres', 'bon',
            'negociable'],
      );
    });

    test('déduplique et ignore la ponctuation', () {
      expect(
        marketKeywords('Terrain terrain, TERRAIN !', ''),
        ['terrain'],
      );
    });

    test('borne à 40 jetons', () {
      final many = List.generate(60, (i) => 'mot$i').join(' ');
      expect(marketKeywords(many, '').length, 40);
    });
  });

  group('searchTokens', () {
    test('normalise la requête comme les jetons indexés', () {
      expect(searchTokens('Véhicule NEUF'), ['vehicule', 'neuf']);
    });

    test('écarte les mots trop courts', () {
      expect(searchTokens('un a de la moto'), ['moto']);
    });
  });

  group('formatAmount', () {
    test('sépare les milliers', () {
      expect(formatAmount(1250000), '1 250 000');
      expect(formatAmount(500), '500');
    });
  });
}
