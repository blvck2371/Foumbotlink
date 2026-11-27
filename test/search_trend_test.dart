import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/search_trend.dart';

SearchTrend t(String q, double hot, [int count = 3]) =>
    SearchTrend(query: q, count: count, hot: hot);

void main() {
  final trends = [
    t('acte de naissance', 10),
    t('télé samsung', 30),
    t('terrain à vendre', 20),
    t('mairie de foumbot', 5),
  ];

  test('pendant la frappe : récentes d’abord, puis tendances par chaleur', () {
    final s = rankSuggestions(
      query: 'te',
      recent: const ['tecno spark'],
      trends: trends,
    );
    expect(s.map((e) => e.text), [
      'tecno spark',
      'télé samsung',
      'terrain à vendre',
    ]);
    expect(s.first.isRecent, isTrue);
    expect(s[1].isRecent, isFalse);
  });

  test('chaque mot tapé doit compléter un mot de la suggestion', () {
    final s = rankSuggestions(
      query: 'acte na',
      recent: const [],
      trends: trends,
    );
    expect(s.map((e) => e.text), ['acte de naissance']);
    expect(
      rankSuggestions(query: 'acte voiture', recent: const [], trends: trends),
      isEmpty,
    );
  });

  test('accents et casse confondus, sans reproposer la saisie', () {
    final s = rankSuggestions(query: 'TELE', recent: const [], trends: trends);
    expect(s.map((e) => e.text), ['télé samsung']);
    expect(
      rankSuggestions(
        query: 'Télé Samsung',
        recent: const ['télé samsung'],
        trends: trends,
      ),
      isEmpty,
    );
  });

  test('pas de doublon entre récentes et tendances, limite respectée', () {
    final s = rankSuggestions(
      query: 'te',
      recent: const ['Terrain à vendre'],
      trends: trends,
      limit: 2,
    );
    expect(s.map((e) => e.text), ['Terrain à vendre', 'télé samsung']);
  });

  test('une tendance masquée par la modération n’est pas lue', () {
    expect(SearchTrend.fromMap({'query': 'x y', 'hidden': true}), isNull);
    expect(SearchTrend.fromMap({'query': '', 'hot': 1}), isNull);
    final ok = SearchTrend.fromMap({'query': 'riz', 'count': 4, 'hot': 2})!;
    expect((ok.query, ok.count, ok.hot), ('riz', 4, 2.0));
  });
}
