/// Texte de la recherche globale : normalisation et jetons.
///
/// Doit rester **identique** à `functions/search_index.js` : le serveur
/// indexe les débuts de mots ainsi normalisés (champ `search`), et l'app
/// interroge avec les mêmes jetons. Une divergence rendrait des documents
/// introuvables sans rien signaler — `test/search_text_test.dart` le
/// vérifie sur des cas réels.
library;

/// Plus court début de mot indexé côté serveur.
const searchMinPrefix = 2;

/// Plus long début de mot indexé côté serveur.
const searchMaxPrefix = 15;

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

/// Minuscules sans accents : « Écòle » → « ecole ».
String normalizeForSearch(String input) {
  final lower = input.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

final _separators = RegExp(r'[^a-z0-9]+');

/// Mots normalisés d'un texte, dans l'ordre.
List<String> searchWords(String text) => normalizeForSearch(
  text,
).split(_separators).where((w) => w.isNotEmpty).toList();

/// Jetons d'une saisie : chaque mot, tronqué à [searchMaxPrefix] (le
/// serveur n'indexe pas plus long). Les lettres isolées sont ignorées ;
/// les chiffres isolés gardés (« studio 2 pièces »).
List<String> searchQueryTokens(String query) {
  final out = <String>[];
  for (final w in searchWords(query)) {
    if (w.length < searchMinPrefix && !RegExp(r'^[0-9]$').hasMatch(w)) {
      continue;
    }
    final t = w.length > searchMaxPrefix ? w.substring(0, searchMaxPrefix) : w;
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// Distance d'édition entre deux mots — insertion, suppression,
/// remplacement, et inversion de deux lettres voisines (« abdle » →
/// « abdel » : une seule faute, la plus fréquente au clavier). Renvoie
/// `max + 1` dès qu'on la dépasse, pour rester rapide.
int boundedEditDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  final d = List.generate(
    a.length + 1,
    (i) => List<int>.filled(b.length + 1, 0)..[0] = i,
  );
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    var rowMin = d[i][0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          d[i - 2][j - 2] + 1 < v) {
        v = d[i - 2][j - 2] + 1;
      }
      d[i][j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
  }
  return d[a.length][b.length];
}

/// Qualité de la correspondance d'un jeton avec un mot :
/// 3 = mot identique, 2 = début du mot, 1 = faute de frappe tolérée
/// (une faute dès 4 lettres, deux dès 8), 0 = rien.
int tokenMatch(String token, String word) {
  if (word == token) return 3;
  if (word.startsWith(token)) return 2;
  if (token.length < 4) return 0;
  final allowed = token.length >= 8 ? 2 : 1;
  // Le mot peut être plus long que la saisie (on tape encore) : on le
  // compare à ses débuts de longueur voisine, ce qui tolère une lettre
  // en trop ou en moins.
  for (var len = token.length - allowed; len <= token.length + allowed; len++) {
    if (len < 1 || len > word.length) continue;
    final head = word.substring(0, len);
    if (boundedEditDistance(token, head, allowed) <= allowed) return 1;
  }
  return 0;
}

/// Note de correspondance de [tokens] avec [text] : chaque jeton doit
/// trouver un mot, sinon 0. Plus la correspondance est franche (mot
/// entier, début de mot, puis faute tolérée), plus la note est haute ; un
/// texte qui *commence* par la saisie est favorisé.
double matchScore(List<String> tokens, String text) {
  if (tokens.isEmpty) return 0;
  final words = searchWords(text);
  if (words.isEmpty) return 0;
  var total = 0.0;
  for (final t in tokens) {
    var best = 0;
    for (final w in words) {
      final m = tokenMatch(t, w);
      if (m > best) best = m;
      if (best == 3) break;
    }
    if (best == 0) return 0;
    total += best;
  }
  var score = total / (3 * tokens.length);
  if (tokenMatch(tokens.first, words.first) >= 2) score += 0.35;
  return score;
}

/// Débuts de mots indexés pour des textes — miroir exact de
/// `searchPrefixes` dans `functions/search_index.js` (60 mots au plus).
/// L'app n'écrit pas l'index ; cette version sert à vérifier que les
/// deux côtés restent d'accord.
List<String> searchPrefixesOf(List<String> texts) {
  final out = <String>{};
  var count = 0;
  for (final text in texts) {
    for (final w in searchWords(text).toSet()) {
      if (count++ >= 60) return out.toList();
      if (w.length < searchMinPrefix) {
        if (RegExp(r'^[0-9]$').hasMatch(w)) out.add(w);
        continue;
      }
      final top = w.length < searchMaxPrefix ? w.length : searchMaxPrefix;
      for (var n = searchMinPrefix; n <= top; n++) {
        out.add(w.substring(0, n));
      }
    }
  }
  return out.toList();
}
