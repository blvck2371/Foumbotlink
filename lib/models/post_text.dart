import 'search_text.dart';

/// Ce qu'une @mention désigne.
enum MentionKind {
  /// Compte personnel ou structure (mairie, association…) : ouvre le
  /// profil.
  user,

  /// Fiche de l'annuaire des professionnels : ouvre la fiche.
  pro;

  static MentionKind fromName(String? name) =>
      name == 'pro' ? MentionKind.pro : MentionKind.user;
}

/// Une @mention dans une publication.
///
/// Le texte du message garde « @Nom » en clair (lisible partout, y compris
/// dans une notification ou une version de l'app qui ignore les
/// mentions) ; la liste `mentions` du document dit à qui chaque « @Nom »
/// renvoie. Le rendu relie l'un à l'autre (voir [splitPostText]).
class PostMention {
  const PostMention({
    required this.kind,
    required this.id,
    required this.name,
  });

  final MentionKind kind;

  /// Uid du compte — y compris pour une fiche pro, dont l'id *est*
  /// l'uid de son propriétaire.
  final String id;

  /// Nom tel qu'il apparaît après le « @ » dans le texte.
  final String name;

  String get token => '@$name';

  factory PostMention.fromMap(Map<String, dynamic> m) => PostMention(
    kind: MentionKind.fromName(m['kind'] as String?),
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {'kind': kind.name, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is PostMention && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// `#mot` : lettres (accents compris), chiffres et `_`, au moins deux
/// caractères, précédé d'un début de texte ou d'un blanc — « C#7 » ou une
/// ancre d'URL ne sont pas des hashtags.
final hashtagPattern = RegExp(
  r'(?<!\S)#([\p{L}\p{N}_]{2,40})',
  unicode: true,
);

/// Forme stockée et recherchée d'un hashtag : minuscules sans accents,
/// « #Fête_Foumbot » → « fete_foumbot ».
String normalizeHashtag(String tag) {
  final raw = tag.startsWith('#') ? tag.substring(1) : tag;
  return normalizeForSearch(raw).replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// Hashtags d'un texte, normalisés, sans doublons, dans l'ordre.
List<String> extractHashtags(String text) {
  final out = <String>[];
  for (final m in hashtagPattern.allMatches(text)) {
    final tag = normalizeHashtag(m.group(1)!);
    if (tag.length >= 2 && !out.contains(tag)) out.add(tag);
  }
  return out.take(20).toList();
}

/// Ne garde que les mentions encore présentes dans le texte : effacer
/// « @Nom » pendant la rédaction retire la mention.
List<PostMention> mentionsStillIn(String text, Iterable<PostMention> all) {
  final out = <PostMention>[];
  for (final m in all) {
    if (m.name.isNotEmpty && text.contains(m.token) && !out.contains(m)) {
      out.add(m);
    }
  }
  return out.take(20).toList();
}

/// Morceau de texte d'une publication, pour le rendu.
sealed class PostTextPart {
  const PostTextPart(this.text);
  final String text;
}

class PlainPart extends PostTextPart {
  const PlainPart(super.text);
}

class MentionPart extends PostTextPart {
  const MentionPart(super.text, this.mention);
  final PostMention mention;
}

class HashtagPart extends PostTextPart {
  const HashtagPart(super.text, this.tag);

  /// Forme normalisée, celle qu'on recherche.
  final String tag;
}

/// Découpe un message en texte simple, @mentions et #hashtags.
///
/// Les mentions les plus longues passent d'abord : « @Jean Paul » ne doit
/// pas être pris pour « @Jean » quand les deux existent.
List<PostTextPart> splitPostText(String text, List<PostMention> mentions) {
  final spans = <(int, int, PostTextPart)>[];
  final sorted = [...mentions]
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  bool overlaps(int s, int e) => spans.any((x) => s < x.$2 && e > x.$1);

  for (final m in sorted) {
    if (m.name.isEmpty) continue;
    var from = 0;
    while (true) {
      final i = text.indexOf(m.token, from);
      if (i < 0) break;
      final end = i + m.token.length;
      if (!overlaps(i, end)) spans.add((i, end, MentionPart(m.token, m)));
      from = end;
    }
  }
  for (final h in hashtagPattern.allMatches(text)) {
    if (overlaps(h.start, h.end)) continue;
    final tag = normalizeHashtag(h.group(1)!);
    if (tag.length < 2) continue;
    spans.add((h.start, h.end, HashtagPart(h.group(0)!, tag)));
  }
  spans.sort((a, b) => a.$1.compareTo(b.$1));

  final out = <PostTextPart>[];
  var pos = 0;
  for (final (start, end, part) in spans) {
    if (start > pos) out.add(PlainPart(text.substring(pos, start)));
    out.add(part);
    pos = end;
  }
  if (pos < text.length) out.add(PlainPart(text.substring(pos)));
  return out;
}

/// Saisie en cours juste avant le curseur : « @jea » ou « #fet ».
/// `null` si le curseur n'est pas dans un mot qui commence par @ ou #.
({String trigger, String query, int start})? activeTrigger(
  String text,
  int cursor,
) {
  if (cursor < 0 || cursor > text.length) return null;
  var i = cursor - 1;
  while (i >= 0) {
    final ch = text[i];
    if (ch == '@' || ch == '#') {
      final before = i == 0 ? ' ' : text[i - 1];
      if (before.trim().isNotEmpty) return null;
      final query = text.substring(i + 1, cursor);
      // Un nom peut contenir une espace (« @Mairie de… ») : on tolère
      // jusqu'à deux mots pour une mention, aucun pour un hashtag.
      final words = query.split(' ').length;
      if (ch == '#' && words > 1) return null;
      if (ch == '@' && (words > 3 || query.length > 40)) return null;
      return (trigger: ch, query: query, start: i);
    }
    if (ch == '\n') return null;
    i--;
  }
  return null;
}
