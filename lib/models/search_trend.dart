import 'search_text.dart';

/// Une recherche fréquente dans la commune, comptée côté serveur
/// (`searchTrends/{clé}`, voir `functions/search_trends.js`).
class SearchTrend {
  const SearchTrend({
    required this.query,
    required this.count,
    required this.hot,
  });

  /// La recherche telle qu'affichée (« acte de naissance »).
  final String query;

  /// Nombre de recherches comptées (un compte, un jour).
  final int count;

  /// Score de tendance : plus il est haut, plus la recherche est
  /// populaire **en ce moment** (il décroît avec le temps).
  final double hot;

  static SearchTrend? fromMap(Map<String, dynamic> d) {
    final q = (d['query'] as String? ?? '').trim();
    if (q.isEmpty || d['hidden'] == true) return null;
    return SearchTrend(
      query: q,
      count: (d['count'] as num?)?.toInt() ?? 0,
      hot: (d['hot'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Une suggestion proposée pendant la frappe.
class SearchSuggestion {
  const SearchSuggestion(this.text, {required this.isRecent, this.count = 0});

  final String text;

  /// Une de mes recherches récentes (sinon : une tendance de la commune).
  final bool isRecent;

  /// Pour une tendance : combien de fois elle a été cherchée.
  final int count;
}

/// Suggestions pour la saisie [query] : mes recherches récentes d'abord
/// (c'est le plus probable), puis les tendances, de la plus chaude à la
/// moins chaude. Une suggestion doit **compléter** la saisie : chaque mot
/// tapé doit retrouver un mot de la suggestion (faute de frappe tolérée),
/// et la saisie elle-même n'est pas reproposée.
List<SearchSuggestion> rankSuggestions({
  required String query,
  required List<String> recent,
  required List<SearchTrend> trends,
  int limit = 5,
}) {
  final tokens = searchQueryTokens(query);
  if (tokens.isEmpty) return const [];
  final typed = searchWords(query).join(' ');
  final seen = <String>{typed};
  final out = <SearchSuggestion>[];

  void consider(String text, {required bool isRecent, int count = 0}) {
    if (out.length >= limit) return;
    final key = searchWords(text).join(' ');
    if (key.isEmpty || !seen.add(key)) return;
    if (matchScore(tokens, text) <= 0) return;
    out.add(SearchSuggestion(text, isRecent: isRecent, count: count));
  }

  for (final r in recent) {
    consider(r, isRecent: true);
  }
  final sorted = [...trends]..sort((a, b) => b.hot.compareTo(a.hot));
  for (final t in sorted) {
    consider(t.query, isRecent: false, count: t.count);
  }
  return out;
}
