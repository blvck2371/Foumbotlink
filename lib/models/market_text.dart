/// Outils de texte partagés par le marché : normalisation pour la
/// recherche et formatage des montants.
///
/// La tokenisation doit rester **identique** à celle de
/// `functions/index.js` (`marketKeywords`) : les jetons écrits à la
/// publication sont ceux que la recherche interroge, et une divergence
/// entre les deux rendrait silencieusement des annonces introuvables.
library;

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
};

/// Minuscules sans accents — « Véhicule » et « vehicule » doivent tomber
/// sur le même jeton, sinon la recherche dépend de la façon dont chacun
/// tape sur son clavier.
String normalizeSearch(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

/// Jetons indexés pour une annonce. Les mots de moins de 3 lettres sont
/// écartés : ils n'apportent rien à la recherche et gonflent le document.
List<String> marketKeywords(String title, String description) {
  final source = normalizeSearch('$title $description');
  final words = source
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3)
      .toSet()
      .toList();
  // Firestore plafonne un `array-contains` à 20 000 valeurs, mais un
  // document reste limité à 1 Mio : on borne à 40 jetons, largement de
  // quoi couvrir un titre et une description d'annonce.
  return words.take(40).toList();
}

/// Jetons d'une requête de recherche. Le premier sert au filtre serveur
/// (`array-contains`), les suivants affinent côté client.
List<String> searchTokens(String query) => normalizeSearch(query)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length >= 3)
    .toList();

/// « 1 250 000 » — séparateur de milliers par espace insécable fine, la
/// convention francophone.
String formatAmount(int amount) => amount.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
