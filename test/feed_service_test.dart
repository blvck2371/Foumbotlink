import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/feed_item.dart';

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
}
