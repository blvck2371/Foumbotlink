import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';
import 'package:foumbotlik/services/feed_service.dart';

void main() {
  group('FeedItem', () {
    test('copyWith preserves fields', () {
      final item = FeedItem(
        id: '1',
        type: FeedType.info,
        title: 'Test',
        body: 'Body',
        authorUid: 'uid1',
        authorName: 'Alice',
        authorSubtitle: 'Citoyenne',
        publishedAt: DateTime(2026, 1, 1),
        likesCount: 5,
        likedByMe: false,
        commentsCount: 2,
      );

      final updated = item.copyWith(likedByMe: true, likesCount: 6);
      expect(updated.likedByMe, true);
      expect(updated.likesCount, 6);
      expect(updated.title, 'Test');
      expect(updated.commentsCount, 2);
    });

    test('isRepost is true when repostOfId is set', () {
      final item = FeedItem(
        id: '2',
        type: FeedType.post,
        title: 'T',
        body: 'B',
        authorUid: 'u2',
        authorName: 'Bob',
        authorSubtitle: 'Citoyen',
        publishedAt: DateTime.now(),
        repostOfId: 'original-1',
        repostOfAuthorUid: 'u1',
        repostOfAuthorName: 'Alice',
      );
      expect(item.isRepost, true);
    });

    test('typeLabel returns correct labels', () {
      expect(
        FeedItem(
          id: '1',
          type: FeedType.annonce,
          title: '',
          body: '',
          authorUid: '',
          authorName: '',
          authorSubtitle: '',
          publishedAt: DateTime.now(),
        ).typeLabel,
        'Annonce',
      );
      expect(
        FeedItem(
          id: '2',
          type: FeedType.post,
          title: '',
          body: '',
          authorUid: '',
          authorName: '',
          authorSubtitle: '',
          publishedAt: DateTime.now(),
        ).typeLabel,
        'Publication',
      );
    });

    test('hasImages works', () {
      final noImages = FeedItem(
        id: '1',
        type: FeedType.post,
        title: '',
        body: '',
        authorUid: '',
        authorName: '',
        authorSubtitle: '',
        publishedAt: DateTime.now(),
      );
      expect(noImages.hasImages, false);

      final withImages = FeedItem(
        id: '2',
        type: FeedType.post,
        title: '',
        body: '',
        authorUid: '',
        authorName: '',
        authorSubtitle: '',
        publishedAt: DateTime.now(),
        imageUrls: ['https://example.com/img.jpg'],
      );
      expect(withImages.hasImages, true);
    });
  });

  group('FeedComment', () {
    test('copyWith preserves fields', () {
      final comment = FeedComment(
        id: 'c1',
        authorUid: 'uid1',
        authorName: 'Bob',
        authorPhotoUrl: 'https://example.com/bob.jpg',
        text: 'Hello',
        createdAt: DateTime(2026, 1, 1),
        likesCount: 3,
        likedByMe: true,
      );

      final updated = comment.copyWith(likedByMe: false, likesCount: 2);
      expect(updated.likedByMe, false);
      expect(updated.likesCount, 2);
      expect(updated.authorName, 'Bob');
      expect(updated.text, 'Hello');
      // Un like ne doit pas faire retomber l'avatar sur les initiales.
      expect(updated.authorPhotoUrl, 'https://example.com/bob.jpg');
    });

    test('totalReplyCount counts recursively', () {
      final reply = FeedComment(
        id: 'r1',
        authorUid: 'u2',
        authorName: 'Eve',
        text: 'Reply',
        createdAt: DateTime.now(),
      );
      final comment = FeedComment(
        id: 'c1',
        authorUid: 'u1',
        authorName: 'Alice',
        text: 'Root',
        createdAt: DateTime.now(),
        replies: [
          FeedComment(
            id: 'c2',
            authorUid: 'u3',
            authorName: 'Bob',
            text: 'Child',
            createdAt: DateTime.now(),
            replies: [reply],
          ),
        ],
      );
      expect(comment.totalReplyCount, 2);
    });
  });

  group('Édition d’une publication', () {
    FeedItem base() => FeedItem(
      id: '1',
      type: FeedType.post,
      title: 'Titre',
      body: 'Corps',
      authorUid: 'uid1',
      authorName: 'Alice',
      authorSubtitle: 'Citoyenne',
      publishedAt: DateTime(2026, 1, 1),
      imageUrls: const ['a.jpg', 'b.jpg'],
    );

    test('copyWith réécrit titre, corps, type et images', () {
      final edited = base().copyWith(
        type: FeedType.annonce,
        title: 'Nouveau titre',
        body: 'Nouveau corps',
        imageUrls: const ['b.jpg'],
        editedAt: DateTime(2026, 2, 1),
      );

      expect(edited.title, 'Nouveau titre');
      expect(edited.body, 'Nouveau corps');
      expect(edited.type, FeedType.annonce);
      expect(edited.imageUrls, ['b.jpg']);
      // L'identité et l'auteur ne bougent jamais à l'édition.
      expect(edited.id, '1');
      expect(edited.authorUid, 'uid1');
      expect(edited.publishedAt, DateTime(2026, 1, 1));
    });

    test('isEdited ne bascule qu’après une modification', () {
      expect(base().isEdited, false);
      expect(base().copyWith(editedAt: DateTime(2026, 2, 1)).isEdited, true);
    });

    test('un like ne touche ni au contenu ni à la date de modification', () {
      final liked = base().copyWith(likedByMe: true, likesCount: 1);
      expect(liked.title, 'Titre');
      expect(liked.imageUrls, ['a.jpg', 'b.jpg']);
      expect(liked.isEdited, false);
    });

    test('commentsDisabled se bascule dans les deux sens', () {
      final closed = base().copyWith(commentsDisabled: true);
      expect(closed.commentsDisabled, true);
      expect(closed.copyWith(commentsDisabled: false).commentsDisabled, false);
    });

    test('shareText reprend titre, corps et auteur', () {
      final text = base().shareText;
      expect(text, contains('Titre'));
      expect(text, contains('Corps'));
      expect(text, contains('Alice'));
    });
  });

  group('Suppression d’un commentaire', () {
    test('la suppression douce vide le texte et conserve les réponses', () {
      final comment = FeedComment(
        id: 'c1',
        authorUid: 'u1',
        authorName: 'Alice',
        text: 'À supprimer',
        createdAt: DateTime(2026, 1, 1),
        likesCount: 4,
        replies: [
          FeedComment(
            id: 'r1',
            authorUid: 'u2',
            authorName: 'Bob',
            text: 'Réponse',
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      );

      final deleted = comment.copyWith(text: '', deleted: true, likesCount: 0);

      expect(deleted.deleted, true);
      expect(deleted.text, '');
      expect(deleted.likesCount, 0);
      // Le nœud subsiste précisément pour ne pas emporter son sous-arbre.
      expect(deleted.replies.length, 1);
      expect(deleted.totalReplyCount, 1);
    });

    test('un commentaire modifié est marqué comme tel', () {
      final comment = FeedComment(
        id: 'c1',
        authorUid: 'u1',
        authorName: 'Alice',
        text: 'Avant',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(comment.isEdited, false);

      final edited = comment.copyWith(
        text: 'Après',
        editedAt: DateTime(2026, 1, 2),
      );
      expect(edited.text, 'Après');
      expect(edited.isEdited, true);
      expect(edited.createdAt, DateTime(2026, 1, 1));
    });
  });

  group('FeedService.shuffledLatestPerAuthor', () {
    FeedItem post(
      String id,
      String author,
      DateTime at, {
      FeedType type = FeedType.post,
      bool hidden = false,
    }) => FeedItem(
      id: id,
      type: type,
      title: id,
      body: '',
      authorUid: author,
      authorName: author,
      authorSubtitle: '',
      publishedAt: at,
      hidden: hidden,
    );

    test('ne garde que la publication la plus récente de chaque compte', () {
      final result = FeedService.shuffledLatestPerAuthor([
        post('a-vieux', 'alice', DateTime(2026, 9, 1, 8)),
        post('a-recent', 'alice', DateTime(2026, 9, 1, 18)),
        post('b', 'bob', DateTime(2026, 9, 1, 12)),
      ]);

      expect(result.map((e) => e.id).toSet(), {'a-recent', 'b'});
    });

    test("l'ordre d'entrée ne décide pas de la publication retenue", () {
      final result = FeedService.shuffledLatestPerAuthor([
        post('a-recent', 'alice', DateTime(2026, 9, 1, 18)),
        post('a-vieux', 'alice', DateTime(2026, 9, 1, 8)),
      ]);

      expect(result.single.id, 'a-recent');
    });

    test('écarte les publications masquées par la modération', () {
      final result = FeedService.shuffledLatestPerAuthor([
        post('a-masque', 'alice', DateTime(2026, 9, 1, 18), hidden: true),
        post('a-visible', 'alice', DateTime(2026, 9, 1, 8)),
      ]);

      expect(result.single.id, 'a-visible');
    });

    test('respecte le filtre de type du fil', () {
      final posts = [
        post('info', 'alice', DateTime(2026, 9, 1, 18), type: FeedType.info),
        post(
          'annonce',
          'bob',
          DateTime(2026, 9, 1, 17),
          type: FeedType.annonce,
        ),
        post('population', 'carl', DateTime(2026, 9, 1, 16)),
      ];

      expect(
        FeedService.shuffledLatestPerAuthor(
          posts,
          filter: FeedFilter.population,
        ).single.id,
        'population',
      );
      expect(
        FeedService.shuffledLatestPerAuthor(
          posts,
          filter: FeedFilter.all,
        ).length,
        3,
      );
    });

    test('mélange : deux tirages ne donnent pas toujours le même ordre', () {
      final posts = [
        for (var i = 0; i < 12; i++)
          post('p$i', 'u$i', DateTime(2026, 9, 1, 8).add(Duration(minutes: i))),
      ];

      final a = FeedService.shuffledLatestPerAuthor(
        posts,
        random: Random(1),
      ).map((e) => e.id).toList();
      final b = FeedService.shuffledLatestPerAuthor(
        posts,
        random: Random(2),
      ).map((e) => e.id).toList();

      expect(a, isNot(equals(b)));
      expect(a.toSet(), b.toSet());
    });
  });
}
