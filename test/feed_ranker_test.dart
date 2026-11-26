import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';
import 'package:foumbotlik/services/feed_ranker.dart';

final now = DateTime(2026, 11, 26, 12);

FeedItem post(
  String id, {
  String author = 'alice',
  double hours = 10,
  int likes = 0,
  int comments = 0,
  String? repostOf,
  FeedType type = FeedType.post,
}) => FeedItem(
  id: id,
  type: type,
  title: id,
  body: '',
  authorUid: author,
  authorName: author,
  authorSubtitle: '',
  publishedAt: now.subtract(Duration(minutes: (hours * 60).round())),
  likesCount: likes,
  commentsCount: comments,
  repostOfId: repostOf,
);

/// Position moyenne de [id] sur de nombreux tirages : le hasard fait
/// partie du classement, on juge donc des tendances, pas un tirage.
double meanRank(
  List<FeedItem> posts,
  FeedViewer viewer,
  String id, {
  int runs = 300,
}) {
  var total = 0;
  for (var seed = 0; seed < runs; seed++) {
    final ranked = FeedRanker.rank(
      posts,
      viewer,
      random: Random(seed),
      now: now,
    );
    total += ranked.indexWhere((e) => e.id == id);
  }
  return total / runs;
}

void main() {
  // Dix auteurs différents, même âge, même intérêt : seul le critère testé
  // les départage.
  List<FeedItem> crowd({double hours = 10}) => [
    for (var i = 0; i < 10; i++) post('p$i', author: 'u$i', hours: hours),
  ];

  test('aucune publication perdue ni dupliquée', () {
    final posts = [
      for (var i = 0; i < 40; i++)
        post('p$i', author: 'u${i % 5}', hours: i * 7.0, likes: i % 4),
    ];
    final ranked = FeedRanker.rank(
      posts,
      const FeedViewer(),
      random: Random(1),
      now: now,
    );
    expect(ranked.length, posts.length);
    expect(ranked.map((e) => e.id).toSet().length, posts.length);
  });

  test('une publication récente passe avant une vieille', () {
    final posts = [...crowd(hours: 24 * 20), post('neuve', hours: 2)];
    expect(meanRank(posts, const FeedViewer(), 'neuve'), lessThan(1.5));
  });

  test('une publication déjà vue recule nettement', () {
    final posts = crowd();
    final viewer = FeedViewer(
      seen: {'p0': SeenMark(1, now.subtract(const Duration(days: 1)))},
    );
    expect(meanRank(posts, viewer, 'p0'), greaterThan(8));
  });

  test('les comptes suivis et les auteurs appréciés remontent', () {
    final posts = crowd();
    expect(
      meanRank(posts, const FeedViewer(following: {'u3'}), 'p3'),
      lessThan(2.5),
    );
    expect(
      meanRank(posts, const FeedViewer(affinity: {'u7': 12}), 'p7'),
      lessThan(2.5),
    );
  });

  test('l’intérêt suscité compte, sans tout écraser', () {
    final posts = [...crowd(), post('debat', author: 'z', comments: 8)];
    expect(meanRank(posts, const FeedViewer(), 'debat'), lessThan(2));
    // Une très populaire mais vieille d'un mois ne passe pas devant des
    // publications du jour.
    final old = [
      ...crowd(hours: 3),
      post('star', author: 'z', hours: 24 * 30, likes: 40, comments: 10),
    ];
    expect(meanRank(old, const FeedViewer(), 'star'), greaterThan(5));
  });

  test('sa propre publication de l’instant ouvre le fil', () {
    final posts = [...crowd(hours: 1), post('moi', author: 'me', hours: 0.1)];
    final ranked = FeedRanker.rank(
      posts,
      const FeedViewer(uid: 'me'),
      random: Random(3),
      now: now,
    );
    expect(ranked.first.id, 'moi');
  });

  test('deux personnes ne voient pas le même fil', () {
    final posts = [
      for (var i = 0; i < 30; i++)
        post('p$i', author: 'u${i % 10}', hours: i * 5.0),
    ];
    final a = FeedRanker.rank(
      posts,
      const FeedViewer(uid: 'a', following: {'u1', 'u2'}),
      random: Random(10),
      now: now,
    );
    final b = FeedRanker.rank(
      posts,
      const FeedViewer(uid: 'b', affinity: {'u8': 10, 'u9': 6}),
      random: Random(20),
      now: now,
    );
    expect(
      a.take(5).map((e) => e.id).toList(),
      isNot(b.take(5).map((e) => e.id).toList()),
    );
  });

  test('deux visites de suite ne donnent pas le même fil', () {
    final posts = crowd();
    final first = FeedRanker.rank(
      posts,
      const FeedViewer(),
      random: Random(1),
      now: now,
    );
    // Seconde visite : les cinq premières ont été vues.
    final viewer = FeedViewer(
      seen: {
        for (final p in first.take(5)) p.id: SeenMark(1, now),
      },
    );
    final second = FeedRanker.rank(
      posts,
      viewer,
      random: Random(2),
      now: now,
    );
    expect(
      second.take(5).map((e) => e.id).toSet(),
      isNot(containsAll(first.take(5).map((e) => e.id))),
    );
  });

  test('jamais le même auteur deux fois de suite quand on peut l’éviter', () {
    final posts = [
      for (var i = 0; i < 6; i++) post('a$i', author: 'a', hours: 1, likes: 9),
      for (var i = 0; i < 6; i++) post('b$i', author: 'b', hours: 50),
      for (var i = 0; i < 6; i++) post('c$i', author: 'c', hours: 90),
    ];
    final ranked = FeedRanker.rank(
      posts,
      const FeedViewer(),
      random: Random(5),
      now: now,
    );
    for (var i = 1; i < 12; i++) {
      expect(
        ranked[i].authorUid,
        isNot(ranked[i - 1].authorUid),
        reason: 'positions ${i - 1} et $i',
      );
    }
  });

  test('une republication et son original ne sont pas servis ensemble', () {
    final posts = [
      post('orig', author: 'a'),
      post('rep', author: 'b', repostOf: 'orig'),
      post('autre', author: 'c'),
    ];
    final ranked = FeedRanker.rank(
      posts,
      const FeedViewer(),
      random: Random(1),
      now: now,
    );
    expect(ranked.where((e) => e.id == 'orig' || e.id == 'rep').length, 1);
  });

  test('même graine, même ordre : le fil ne bouge pas sous le doigt', () {
    final posts = crowd();
    List<String> ids(int seed) => FeedRanker.rank(
      posts,
      const FeedViewer(),
      random: Random(seed),
      now: now,
    ).map((e) => e.id).toList();
    expect(ids(42), ids(42));
  });
}
