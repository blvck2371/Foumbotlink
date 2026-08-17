import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';
import 'package:foumbotlik/services/feed_service.dart';

void main() {
  late FeedService service;
  late FeedItem post;

  setUp(() async {
    service = FeedService();
    final page = await service.fetchPage(page: 0, filter: FeedFilter.all);
    post = page.firstWhere((p) => p.comments.isEmpty);
  });

  group('addComment', () {
    test('un commentaire de premier niveau est ajouté en tête, sans mention', () {
      final updated = service.addComment(post.id, 'Salut Foumbot')!;

      expect(updated.comments, hasLength(1));
      final comment = updated.comments.first;
      expect(comment.text, 'Salut Foumbot');
      expect(comment.replyToName, isNull);
      expect(comment.replies, isEmpty);
    });

    test('les nouveaux commentaires de premier niveau apparaissent en tête (le plus récent en premier)', () {
      service.addComment(post.id, 'Premier');
      final updated = service.addComment(post.id, 'Deuxième')!;

      expect(updated.comments.map((c) => c.text), ['Deuxième', 'Premier']);
    });

    test('répondre à un commentaire racine mentionne son auteur et s\'attache dessous', () {
      final afterRoot = service.addComment(post.id, 'Racine')!;
      final root = afterRoot.comments.first;

      final updated = service.addComment(post.id, 'Réponse', parentCommentId: root.id)!;
      final reply = updated.comments.first.replies.single;

      expect(reply.replyToName, 'Vous');
      expect(reply.replies, isEmpty);
    });

    test('on peut répondre à une réponse : le fil s\'imbrique à volonté (comme TikTok)', () {
      final afterRoot = service.addComment(post.id, 'Niveau 0')!;
      final level0 = afterRoot.comments.first;

      final afterL1 = service.addComment(post.id, 'Niveau 1', parentCommentId: level0.id)!;
      final level1 = afterL1.comments.first.replies.single;

      final afterL2 = service.addComment(post.id, 'Niveau 2', parentCommentId: level1.id)!;
      final level2 = afterL2.comments.first.replies.single.replies.single;

      final afterL3 = service.addComment(post.id, 'Niveau 3', parentCommentId: level2.id)!;
      final root = afterL3.comments.first;

      // La réponse au niveau N vit SOUS le commentaire ciblé, pas
      // "remontée" à la racine : la structure est un vrai arbre.
      expect(root.replies, hasLength(1));
      expect(root.replies.single.text, 'Niveau 1');
      expect(root.replies.single.replies.single.text, 'Niveau 2');
      expect(root.replies.single.replies.single.replies.single.text, 'Niveau 3');
      expect(root.replies.single.replies.single.replies.single.replyToName, 'Vous');
    });

    test('un commentaire peut recevoir plusieurs réponses, chacune pouvant elle-même être imbriquée', () {
      final afterRoot = service.addComment(post.id, 'Racine')!;
      final rootId = afterRoot.comments.first.id;
      service.addComment(post.id, 'Réponse A', parentCommentId: rootId);
      final afterB = service.addComment(post.id, 'Réponse B', parentCommentId: rootId)!;
      final replyA = afterB.comments.first.replies[0];

      final updated = service.addComment(post.id, 'Sous-réponse de A', parentCommentId: replyA.id)!;
      final root = updated.comments.first;

      expect(root.replies, hasLength(2));
      expect(root.replies[0].text, 'Réponse A');
      expect(root.replies[0].replies.single.text, 'Sous-réponse de A');
      expect(root.replies[1].text, 'Réponse B');
      expect(root.replies[1].replies, isEmpty);
    });

    test('répondre avec un parentCommentId inconnu échoue proprement', () {
      final result = service.addComment(post.id, 'orphelin', parentCommentId: 'ne-existe-pas');
      expect(result, isNull);
    });

    test('un texte vide ou blanc est ignoré', () {
      expect(service.addComment(post.id, '   '), isNull);
      expect(service.getById(post.id)!.comments, isEmpty);
    });

    test('commentsCount compte tous les commentaires à toute profondeur', () {
      final afterRoot = service.addComment(post.id, 'Racine')!;
      final rootId = afterRoot.comments.first.id;
      final afterR1 = service.addComment(post.id, 'R1', parentCommentId: rootId)!;
      final r1Id = afterR1.comments.first.replies.single.id;
      final updated = service.addComment(post.id, 'R1-R1', parentCommentId: r1Id)!;

      expect(updated.commentsCount, 3);
    });
  });

  group('toggleCommentLike', () {
    test('like puis unlike un commentaire racine', () {
      final afterRoot = service.addComment(post.id, 'Racine')!;
      final rootId = afterRoot.comments.first.id;

      final liked = service.toggleCommentLike(post.id, rootId)!;
      expect(liked.comments.first.likedByMe, isTrue);
      expect(liked.comments.first.likesCount, 1);

      final unliked = service.toggleCommentLike(post.id, rootId)!;
      expect(unliked.comments.first.likedByMe, isFalse);
      expect(unliked.comments.first.likesCount, 0);
    });

    test('liker un commentaire imbriqué en profondeur ne touche pas ses ancêtres ni ses frères', () {
      final afterRoot = service.addComment(post.id, 'Racine')!;
      final rootId = afterRoot.comments.first.id;
      final afterR1 = service.addComment(post.id, 'R1', parentCommentId: rootId)!;
      final r1Id = afterR1.comments.first.replies.single.id;
      final afterR1R1 = service.addComment(post.id, 'R1-R1', parentCommentId: r1Id)!;
      final r1r1Id = afterR1R1.comments.first.replies.single.replies.single.id;

      final updated = service.toggleCommentLike(post.id, r1r1Id)!;
      final root = updated.comments.first;
      final r1 = root.replies.single;
      final r1r1 = r1.replies.single;

      expect(root.likedByMe, isFalse);
      expect(r1.likedByMe, isFalse);
      expect(r1r1.likedByMe, isTrue);
      expect(r1r1.likesCount, 1);
    });

    test('liker un id inconnu échoue proprement', () {
      expect(service.toggleCommentLike(post.id, 'inconnu'), isNull);
    });
  });

  group('toggleLike (post)', () {
    test('like puis unlike un post', () {
      final liked = service.toggleLike(post.id)!;
      expect(liked.likedByMe, isTrue);
      expect(liked.likesCount, post.likesCount + 1);

      final unliked = service.toggleLike(post.id)!;
      expect(unliked.likedByMe, isFalse);
      expect(unliked.likesCount, post.likesCount);
    });
  });

  group('images', () {
    test('une publication peut porter 0, 1 ou plusieurs photos, de façon déterministe', () async {
      final freshService = FeedService();
      final pageA = await freshService.fetchPage(page: 0, filter: FeedFilter.all);
      final pageB = await FeedService()
          .fetchPage(page: 0, filter: FeedFilter.all);

      // Même id -> mêmes images, à chaque fois (pas de flakiness visuelle).
      for (var i = 0; i < pageA.length; i++) {
        expect(pageA[i].imageUrls, pageB[i].imageUrls);
      }

      // Certaines publications ont des photos, d'autres non.
      expect(pageA.any((p) => p.hasImages), isTrue);
      expect(pageA.any((p) => !p.hasImages), isTrue);
    });

    test('le fil reste majoritairement textuel, comme un vrai fil Facebook', () async {
      final freshService = FeedService();
      final items = [
        ...await freshService.fetchPage(page: 0, filter: FeedFilter.all),
        ...await freshService.fetchPage(page: 1, filter: FeedFilter.all),
        ...await freshService.fetchPage(page: 2, filter: FeedFilter.all),
      ];

      final withImages = items.where((p) => p.hasImages).length;
      final textOnly = items.length - withImages;

      expect(textOnly, greaterThan(withImages));
    });

    test('liker ou commenter une publication ne fait pas disparaître ses photos', () async {
      final page = await service.fetchPage(page: 0, filter: FeedFilter.all);
      final withImages = page.firstWhere((p) => p.hasImages);
      final originalImages = withImages.imageUrls;

      final afterLike = service.toggleLike(withImages.id)!;
      expect(afterLike.imageUrls, originalImages);

      final afterComment = service.addComment(withImages.id, 'Belle photo !')!;
      expect(afterComment.imageUrls, originalImages);
    });
  });
}
