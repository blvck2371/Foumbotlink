import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';
import 'package:foumbotlik/services/feed_service.dart';

FeedItem post(String id, DateTime at, {String author = 'alice'}) => FeedItem(
      id: id,
      type: FeedType.post,
      title: id,
      body: '',
      authorUid: author,
      authorName: author,
      authorSubtitle: '',
      publishedAt: at,
    );

void main() {
  // Repère fixe : le fil se juge par rapport à « maintenant », les cas
  // doivent donc pouvoir décider eux-mêmes de l'heure qu'il est.
  final now = DateTime(2026, 9, 6, 12);
  FeedItem old(String id, {int days = 5}) =>
      post(id, now.subtract(Duration(days: days)));
  FeedItem fresh(String id, {int hours = 1}) =>
      post(id, now.subtract(Duration(hours: hours)));

  group('FeedService.rotate', () {
    test('les publications récentes restent en tête, dans l’ordre', () {
      final result = FeedService.rotate(
        [old('vieux1'), fresh('recent-1h', hours: 1),
            old('vieux2'), fresh('recent-5h', hours: 5)],
        random: Random(1),
        now: now,
      );

      expect(result.take(2).map((e) => e.id), ['recent-1h', 'recent-5h']);
      expect(result.skip(2).map((e) => e.id).toSet(), {'vieux1', 'vieux2'});
    });

    test('aucune publication n’est perdue ni dupliquée', () {
      final input = [
        for (var i = 0; i < 12; i++) old('p$i', days: i + 2),
        fresh('neuf'),
      ];
      final result = FeedService.rotate(input, random: Random(7), now: now);

      expect(result.length, input.length);
      expect(result.map((e) => e.id).toSet(),
          input.map((e) => e.id).toSet());
    });

    test('deux graines différentes donnent des ordres différents', () {
      final input = [for (var i = 0; i < 20; i++) old('p$i', days: i + 2)];
      final a = FeedService.rotate(input, random: Random(1), now: now)
          .map((e) => e.id)
          .toList();
      final b = FeedService.rotate(input, random: Random(2), now: now)
          .map((e) => e.id)
          .toList();

      // C'est tout l'objet de la rotation : sans nouvelle publication, le
      // fil ne doit pas se présenter deux fois de la même façon.
      expect(a, isNot(equals(b)));
    });

    test('la même graine redonne exactement le même ordre', () {
      final input = [for (var i = 0; i < 20; i++) old('p$i', days: i + 2)];
      final a = FeedService.rotate(input, random: Random(42), now: now);
      final b = FeedService.rotate(input, random: Random(42), now: now);

      // La stabilité compte autant que la variété : l'ordre ne doit pas
      // bouger sous les doigts pendant qu'on fait défiler.
      expect(a.map((e) => e.id), b.map((e) => e.id));
    });

    test('un fil entièrement récent garde l’ordre chronologique', () {
      final result = FeedService.rotate(
        [fresh('h9', hours: 9), fresh('h1', hours: 1), fresh('h5', hours: 5)],
        random: Random(3),
        now: now,
      );

      expect(result.map((e) => e.id), ['h1', 'h5', 'h9']);
    });

    test('la limite de fraîcheur se règle', () {
      final result = FeedService.rotate(
        [post('j2', now.subtract(const Duration(days: 2)))],
        freshWindow: const Duration(days: 7),
        random: Random(1),
        now: now,
      );

      // Avec une fenêtre de 7 jours, une publication de 2 jours est encore
      // « fraîche » : elle reste en tête au lieu d'entrer en rotation.
      expect(result.single.id, 'j2');
    });

    test('une liste vide ne casse rien', () {
      expect(FeedService.rotate(const [], now: now), isEmpty);
    });

    test('la première page est plus large que les suivantes', () {
      // La rotation n'a d'effet visible que si le premier écran porte sur
      // assez de publications : sur huit, le haut du fil resterait occupé
      // par les mêmes d'une visite à l'autre.
      expect(FeedService.firstPageSize, greaterThan(FeedService.pageSize));
    });
  });
}
