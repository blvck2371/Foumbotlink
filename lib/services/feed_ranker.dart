import 'dart:math';

import '../models/feed_item.dart';

/// Ce que le classement sait de la personne qui regarde le fil.
///
/// Tout est local à son appareil : deux habitants n'ont ni les mêmes
/// abonnements, ni les mêmes affinités, ni les mêmes publications déjà
/// vues — c'est ce qui fait que leurs fils diffèrent.
class FeedViewer {
  const FeedViewer({
    this.uid,
    this.following = const {},
    this.affinity = const {},
    this.seen = const {},
    this.liked = const {},
  });

  final String? uid;

  /// Comptes suivis.
  final Set<String> following;

  /// Affinité par auteur (likes, commentaires, ouvertures, temps passé sur
  /// ses publications…), déjà amortie dans le temps — voir `FeedMemory`.
  final Map<String, double> affinity;

  /// Publications déjà vues : id → (nombre de fois, dernière fois).
  final Map<String, SeenMark> seen;

  /// Publications déjà aimées.
  final Set<String> liked;
}

class SeenMark {
  const SeenMark(this.count, this.at);
  final int count;
  final DateTime at;
}

/// Classement du fil d'actualité, façon Facebook.
///
/// Chaque publication reçoit une note qui combine :
/// - **la fraîcheur** — décroissance douce : une publication de la veille
///   passe avant celle du mois dernier, sans que les anciennes
///   disparaissent (une commune publie peu, il faut de la matière) ;
/// - **l'intérêt suscité** — j'aime et surtout commentaires, en log pour
///   qu'une publication très populaire n'écrase pas tout ;
/// - **le lien avec l'auteur** — abonnement et affinité apprise des gestes
///   de la personne (ce qu'elle aime, commente, ouvre, lit longtemps) ;
/// - **le déjà-vu** — une publication déjà montrée recule fortement, d'où
///   un fil qui se renouvelle à chaque visite ;
/// - **une part de hasard**, propre à chaque personne et à chaque visite,
///   pour départager les publications proches et ne jamais figer l'ordre.
///
/// Puis une passe de **diversité** : jamais deux publications du même
/// auteur coup sur coup quand il y a d'autres choix, et une republication
/// ne côtoie pas son original.
///
/// Fonctions pures — vérifiables sans Firestore, et reproductibles avec
/// une graine.
abstract final class FeedRanker {
  /// Demi-vie approximative de la fraîcheur, en heures.
  static const _freshnessHours = 30.0;

  /// Une publication de moins de [_justPublished] passe en tête si elle
  /// vient de la personne elle-même — elle veut la voir en ligne.
  static const _justPublished = Duration(minutes: 30);

  /// Écart du hasard, en log : ×/÷ ~1,4 en moyenne. Assez pour varier,
  /// pas assez pour faire remonter n'importe quoi.
  static const _noise = 0.35;

  /// Note d'une publication pour [viewer], sans le hasard.
  static double score(FeedItem p, FeedViewer viewer, DateTime now) {
    final ageH = max(0, now.difference(p.publishedAt).inMinutes) / 60.0;

    // Fraîcheur : 1 à l'instant, ~0,5 à 30 h, ~0,1 à 15 jours — mais
    // jamais nul : les anciennes restent classables entre elles.
    final freshness = pow(1 + ageH / _freshnessHours, -0.9).toDouble();

    final engagement = log(1 + p.likesCount + 2.5 * p.commentsCount);

    final author = p.authorUid;
    var bond = 0.0;
    if (viewer.following.contains(author)) bond += 1.2;
    bond += log(1 + (viewer.affinity[author] ?? 0)) * 0.8;

    var s = freshness * (1 + 0.45 * engagement) * (1 + bond);

    if (p.hasImages) s *= 1.15;
    // Communications officielles de la mairie : un peu plus visibles.
    if (p.type != FeedType.post) s *= 1.25;

    final mine = viewer.uid != null && author == viewer.uid;
    if (mine) {
      if (now.difference(p.publishedAt) < _justPublished) return 1e6;
      // Facebook montre peu ses propres anciennes publications à soi-même.
      s *= 0.3;
    }

    final seen = viewer.seen[p.id];
    if (seen != null) {
      // Déjà vue : recule nettement, d'autant plus qu'elle a été vue
      // souvent et récemment. Elle reste dans le fil, plus bas.
      final hoursSince = max(0, now.difference(seen.at).inMinutes) / 60.0;
      final recent = hoursSince < 6 ? 0.4 : 1.0;
      s *= 0.08 * recent / seen.count;
    }

    if (viewer.liked.contains(p.id)) s *= 0.6;

    return s;
  }

  /// Ordonne [posts] pour [viewer]. [random] porte le hasard de la visite.
  static List<FeedItem> rank(
    Iterable<FeedItem> posts,
    FeedViewer viewer, {
    required Random random,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final unique = _dropRepostDuplicates(posts.toList(), viewer, at);
    final scored = [
      for (final p in unique)
        (p, log(max(score(p, viewer, at), 1e-12)) + _noise * _gauss(random)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return diversify([for (final e in scored) e.$1]);
  }

  /// Passe de diversité : prend toujours la mieux classée, sauf si son
  /// auteur vient d'apparaître dans les [window] dernières — on prend alors
  /// la suivante d'un autre auteur, si elle n'est pas trop loin.
  static List<FeedItem> diversify(
    List<FeedItem> ranked, {
    int window = 2,
    int lookahead = 6,
    Iterable<FeedItem> before = const [],
  }) {
    final rest = [...ranked];
    final out = <FeedItem>[];
    final recentAuthors = [
      for (final p in before.toList().reversed.take(window).toList().reversed)
        p.authorUid,
    ];
    while (rest.isNotEmpty) {
      var pick = 0;
      for (var i = 0; i < min(lookahead, rest.length); i++) {
        if (!recentAuthors.contains(rest[i].authorUid)) {
          pick = i;
          break;
        }
      }
      final p = rest.removeAt(pick);
      out.add(p);
      recentAuthors.add(p.authorUid);
      if (recentAuthors.length > window) recentAuthors.removeAt(0);
    }
    return out;
  }

  /// Une republication et son original n'apparaissent pas tous les deux :
  /// on garde la mieux notée.
  static List<FeedItem> _dropRepostDuplicates(
    List<FeedItem> posts,
    FeedViewer viewer,
    DateTime now,
  ) {
    final byStory = <String, FeedItem>{};
    for (final p in posts) {
      final story = p.repostOfId ?? p.id;
      final kept = byStory[story];
      if (kept == null || score(p, viewer, now) > score(kept, viewer, now)) {
        byStory[story] = p;
      }
    }
    final keep = byStory.values.map((e) => e.id).toSet();
    return [
      for (final p in posts)
        if (keep.contains(p.id)) p,
    ];
  }

  /// Tirage gaussien (Box-Muller).
  static double _gauss(Random r) {
    final u = 1 - r.nextDouble();
    final v = r.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }
}
