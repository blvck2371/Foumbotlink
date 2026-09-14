import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/controllers/status_feed_controller.dart';
import 'package:foumbotlik/models/chat_message.dart';
import 'package:foumbotlik/models/user_status.dart';

UserStatus status(
  String id, {
  String author = 'alice',
  bool viewed = false,
  bool liked = false,
  int likes = 0,
  DateTime? at,
  String text = '',
  String? imageUrl,
  String? videoUrl,
  String? repostOfId,
  String? repostOfAuthorName,
}) {
  final created = at ?? DateTime(2026, 9, 7, 10);
  return UserStatus(
    id: id,
    authorUid: author,
    authorName: author,
    createdAt: created,
    expiresAt: created.add(UserStatus.lifetime),
    viewedByMe: viewed,
    likedByMe: liked,
    likesCount: likes,
    text: text,
    imageUrl: imageUrl,
    videoUrl: videoUrl,
    repostOfId: repostOfId,
    repostOfAuthorUid: repostOfId == null ? null : 'bob',
    repostOfAuthorName: repostOfAuthorName,
  );
}

void main() {
  group('StatusBubble', () {
    test('l’anneau reste allumé tant qu’un statut n’a pas été vu', () {
      final bubble = StatusBubble(
        authorUid: 'alice',
        authorName: 'Alice',
        statuses: [status('a', viewed: true), status('b')],
      );
      expect(bubble.hasUnseen, isTrue);
    });

    test('l’anneau s’éteint quand tout a été vu', () {
      final bubble = StatusBubble(
        authorUid: 'alice',
        authorName: 'Alice',
        statuses: [status('a', viewed: true), status('b', viewed: true)],
      );
      expect(bubble.hasUnseen, isFalse);
    });

    test('on reprend au premier statut non vu', () {
      final bubble = StatusBubble(
        authorUid: 'alice',
        authorName: 'Alice',
        statuses: [
          status('a', viewed: true),
          status('b', viewed: true),
          status('c'),
        ],
      );
      expect(bubble.startIndex, 2);
    });

    test('tout vu : on repart du début', () {
      final bubble = StatusBubble(
        authorUid: 'alice',
        authorName: 'Alice',
        statuses: [status('a', viewed: true), status('b', viewed: true)],
      );
      expect(bubble.startIndex, 0);
    });

    test('une pastille sans statut ne prétend pas en avoir', () {
      const bubble = StatusBubble(
        authorUid: 'moi',
        authorName: 'Moi',
        statuses: [],
        isMine: true,
      );
      expect(bubble.hasStatuses, isFalse);
      expect(bubble.hasUnseen, isFalse);
      expect(bubble.startIndex, 0);
    });
  });

  group('UserStatus — repartage et aperçu', () {
    test('un statut ordinaire n’est pas un repartage', () {
      expect(status('a').isRepost, isFalse);
    });

    test('un repartage cite son auteur d’origine', () {
      final s = status('a', repostOfId: 'src', repostOfAuthorName: 'Bob');
      expect(s.isRepost, isTrue);
      expect(s.repostOfAuthorName, 'Bob');
    });

    test('l’aperçu reprend le texte, tronqué', () {
      final s = status('a', text: 'x' * 200);
      expect(s.shortPreview.length, lessThanOrEqualTo(61));
      expect(s.shortPreview.endsWith('…'), isTrue);
    });

    test('sans texte, l’aperçu annonce le type de média', () {
      expect(status('a', imageUrl: 'http://x/p.jpg').shortPreview, '📷 Photo');
      expect(status('a', videoUrl: 'http://x/v.mp4').shortPreview, '🎬 Vidéo');
      expect(status('a').shortPreview, 'Statut');
    });

    test('le retrait d’un « j’aime » ne peut pas passer sous zéro', () {
      final s = status('a', liked: true, likes: 1);
      expect(s.copyWith(likedByMe: false, likesCount: 0).likesCount, 0);
    });
  });

  group('StatusRef — la citation portée par le message', () {
    test('aller-retour complet', () {
      const ref = StatusRef(
        statusId: 's1',
        authorUid: 'alice',
        previewUrl: 'http://x/p.jpg',
        text: 'Bonjour Foumbot',
        backgroundColor: 0xFF112233,
        isLike: true,
        isVideo: false,
      );
      final back = StatusRef.fromMap(ref.toMap())!;

      expect(back.statusId, 's1');
      expect(back.authorUid, 'alice');
      expect(back.previewUrl, 'http://x/p.jpg');
      expect(back.text, 'Bonjour Foumbot');
      expect(back.backgroundColor, 0xFF112233);
      expect(back.isLike, isTrue);
      expect(back.isVideo, isFalse);
    });

    test('une carte sans identifiant ne donne pas de citation', () {
      expect(StatusRef.fromMap(null), isNull);
      expect(StatusRef.fromMap(const {'authorUid': 'alice'}), isNull);
      expect(StatusRef.fromMap(const {'statusId': ''}), isNull);
    });
  });

  group('ChatMessage — réaction à un statut', () {
    ChatMessage message({required StatusRef ref, String content = 'Bravo !'}) =>
        ChatMessage(
          id: 'm1',
          senderUid: 'bob',
          type: MessageType.text,
          content: content,
          createdAt: DateTime(2026, 9, 7),
          statusRef: ref,
        );

    const likeRef = StatusRef(
      statusId: 's1',
      authorUid: 'alice',
      isLike: true,
    );
    const commentRef = StatusRef(statusId: 's1', authorUid: 'alice');

    test('un « j’aime » s’annonce comme tel dans la liste', () {
      expect(
        message(ref: likeRef, content: '❤️').shortPreview,
        '❤️ A aimé votre statut',
      );
    });

    test('un commentaire montre ce qui a été écrit', () {
      expect(message(ref: commentRef).shortPreview, '💬 Bravo !');
    });

    test('un message ordinaire n’est pas touché', () {
      final plain = ChatMessage(
        id: 'm2',
        senderUid: 'bob',
        type: MessageType.text,
        content: 'Salut',
        createdAt: DateTime(2026, 9, 7),
      );
      expect(plain.isStatusReply, isFalse);
      expect(plain.shortPreview, 'Salut');
    });

    test('la citation survit à la sérialisation du message', () {
      final map = message(ref: likeRef, content: '❤️').toMap();
      final ref = StatusRef.fromMap(
        map['statusRef'] as Map<String, dynamic>,
      );
      expect(ref, isNotNull);
      expect(ref!.isLike, isTrue);
      expect(ref.statusId, 's1');
    });

    test('un message supprimé n’expose plus la réaction', () {
      final deleted = ChatMessage(
        id: 'm3',
        senderUid: 'bob',
        type: MessageType.text,
        content: '❤️',
        createdAt: DateTime(2026, 9, 7),
        statusRef: likeRef,
        deleted: true,
      );
      expect(deleted.shortPreview, 'Message supprimé');
    });
  });
}
