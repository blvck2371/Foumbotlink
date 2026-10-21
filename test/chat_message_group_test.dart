import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/chat_message.dart';

void main() {
  final base = DateTime(2026, 9, 5, 14, 0);

  ChatMessage msg(
    String id, {
    String sender = 'moi',
    MessageType type = MessageType.image,
    MessageDeliveryStatus status = MessageDeliveryStatus.sent,
    Duration offset = Duration.zero,
    String? replyToId,
    bool deleted = false,
  }) => ChatMessage(
    id: id,
    senderUid: sender,
    type: type,
    content: 'https://exemple.test/$id.jpg',
    createdAt: base.add(offset),
    status: status,
    replyToId: replyToId,
    deleted: deleted,
  );

  group('groupChatMessages', () {
    test('réunit les photos consécutives d’un même expéditeur', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('b', offset: const Duration(seconds: 2)),
        msg('c', offset: const Duration(seconds: 4)),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.map((m) => m.id), ['a', 'b', 'c']);
    });

    test('ne mélange pas deux expéditeurs', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('b', sender: 'autre', offset: const Duration(seconds: 2)),
      ]);

      expect(groups.map((g) => g.length), [1, 1]);
    });

    test('un message texte coupe l’album', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('t', type: MessageType.text, offset: const Duration(seconds: 1)),
        msg('b', offset: const Duration(seconds: 2)),
      ]);

      expect(groups.map((g) => g.map((m) => m.id).toList()), [
        ['a'],
        ['t'],
        ['b'],
      ]);
    });

    test('laisse seule une photo encore en cours d’envoi', () {
      final groups = groupChatMessages([
        msg('a'),
        msg(
          'b',
          status: MessageDeliveryStatus.sending,
          offset: const Duration(seconds: 1),
        ),
        msg(
          'c',
          status: MessageDeliveryStatus.failed,
          offset: const Duration(seconds: 2),
        ),
      ]);

      expect(groups.map((g) => g.map((m) => m.id).toList()), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('une photo trop éloignée dans le temps ouvre un nouvel album', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('b', offset: const Duration(minutes: 5)),
      ]);

      expect(groups.map((g) => g.length), [1, 1]);
    });

    test('une photo qui cite un message reste seule', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('b', offset: const Duration(seconds: 1), replyToId: 'x'),
        msg('c', offset: const Duration(seconds: 2)),
      ]);

      expect(groups.map((g) => g.map((m) => m.id).toList()), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('un album est borné : au-delà, un second commence', () {
      final groups = groupChatMessages([
        for (var i = 0; i < 12; i++) msg('p$i', offset: Duration(seconds: i)),
      ], maxPerAlbum: 10);

      expect(groups.map((g) => g.length), [10, 2]);
    });

    test('une photo supprimée ne rejoint jamais un album', () {
      final groups = groupChatMessages([
        msg('a'),
        msg('b', offset: const Duration(seconds: 1), deleted: true),
        msg('c', offset: const Duration(seconds: 2)),
      ]);

      expect(groups.map((g) => g.map((m) => m.id).toList()), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('une liste vide ne produit aucun groupe', () {
      expect(groupChatMessages([]), isEmpty);
    });
  });

  group('ChatMessage — suppression et réactions', () {
    ChatMessage build({
      bool deleted = false,
      Map<String, String> reactions = const {},
      MessageType type = MessageType.text,
    }) => ChatMessage(
      id: 'm1',
      senderUid: 'moi',
      type: type,
      content: 'Bonjour',
      createdAt: base,
      deleted: deleted,
      reactions: reactions,
    );

    test('un message supprimé s’annonce comme tel dans les aperçus', () {
      expect(build(deleted: true).shortPreview, 'Message supprimé');
      expect(build().shortPreview, 'Bonjour');
    });

    test('l’aperçu d’une photo supprimée ne dit plus « Photo »', () {
      expect(
        build(deleted: true, type: MessageType.image).shortPreview,
        'Message supprimé',
      );
    });

    test('les réactions sont comptées par emoji, la plus posée d’abord', () {
      final counts = build(
        reactions: {'a': '👍', 'b': '❤️', 'c': '👍', 'd': '👍'},
      ).reactionCounts;

      expect(counts.first.emoji, '👍');
      expect(counts.first.count, 3);
      expect(counts.last.emoji, '❤️');
      expect(counts.last.count, 1);
    });

    test('sans réaction, la liste est vide', () {
      expect(build().reactionCounts, isEmpty);
    });

    test('copyWith conserve suppression et réactions', () {
      final updated = build(
        deleted: true,
        reactions: {'a': '🙏'},
      ).copyWith(status: MessageDeliveryStatus.failed);

      expect(updated.deleted, true);
      expect(updated.reactions, {'a': '🙏'});
      expect(updated.status, MessageDeliveryStatus.failed);
    });
  });

  group('Suppression pour moi / pour tout le monde', () {
    ChatMessage sent({
      String sender = 'moi',
      Duration age = Duration.zero,
      bool deleted = false,
      List<String> hiddenFor = const [],
    }) => ChatMessage(
      id: 'm1',
      senderUid: sender,
      type: MessageType.text,
      content: 'Bonjour',
      createdAt: base.subtract(age),
      deleted: deleted,
      hiddenFor: hiddenFor,
    );

    test('l’auteur peut retirer à tous un message récent', () {
      expect(
        sent(
          age: const Duration(hours: 1),
        ).canDeleteForEveryone('moi', now: base),
        true,
      );
    });

    test('passé la fenêtre, la suppression pour tous n’est plus offerte', () {
      final tooOld =
          ChatMessage.deleteForEveryoneWindow + const Duration(minutes: 1);
      expect(sent(age: tooOld).canDeleteForEveryone('moi', now: base), false);
    });

    test('juste avant la limite, elle l’est encore', () {
      expect(
        sent(
          age: ChatMessage.deleteForEveryoneWindow,
        ).canDeleteForEveryone('moi', now: base),
        true,
      );
    });

    test('on ne retire pas à tous le message de quelqu’un d’autre', () {
      expect(
        sent(sender: 'autre').canDeleteForEveryone('moi', now: base),
        false,
      );
    });

    test('un message déjà supprimé ne se resupprime pas', () {
      expect(sent(deleted: true).canDeleteForEveryone('moi', now: base), false);
    });

    test('« supprimé pour moi » ne vise que la personne concernée', () {
      final msg = sent(hiddenFor: ['moi']);
      expect(msg.isHiddenFor('moi'), true);
      expect(msg.isHiddenFor('autre'), false);
    });

    test('copyWith conserve les masquages personnels', () {
      final updated = sent(
        hiddenFor: ['moi'],
      ).copyWith(status: MessageDeliveryStatus.sent);
      expect(updated.hiddenFor, ['moi']);
    });
  });
  group('vidéo', () {
    ChatMessage video({Duration offset = Duration.zero, int? durationMs}) =>
        ChatMessage(
          id: 'v',
          senderUid: 'moi',
          type: MessageType.video,
          content: 'https://exemple.test/v.mp4',
          durationMs: durationMs,
          createdAt: base.add(offset),
        );

    test('une vidéo ne rejoint pas un album de photos', () {
      final groups = groupChatMessages([
        msg('a'),
        video(offset: const Duration(seconds: 1)),
        msg('b', offset: const Duration(seconds: 2)),
      ]);

      expect(groups.map((g) => g.map((m) => m.id).toList()), [
        ['a'],
        ['v'],
        ['b'],
      ]);
    });

    test('la bulle vidéo se dessine comme une photo, bord à bord', () {
      expect(video().isMediaBubble, true);
      expect(msg('a').isMediaBubble, true);
      expect(msg('t', type: MessageType.text).isMediaBubble, false);
      expect(msg('d', type: MessageType.document).isMediaBubble, false);
    });

    test('l’aperçu d’une ligne annonce une vidéo', () {
      expect(video().shortPreview, '🎥 Vidéo');
    });

    test('une vidéo supprimée n’annonce plus son type', () {
      final removed = ChatMessage(
        id: 'v',
        senderUid: 'moi',
        type: MessageType.video,
        content: '',
        createdAt: base,
        deleted: true,
      );
      expect(removed.shortPreview, 'Message supprimé');
    });

    test('la durée se lit en m:ss, et vaut 0:00 sans durée connue', () {
      expect(video(durationMs: 42000).durationLabel, '0:42');
      expect(video(durationMs: 95000).durationLabel, '1:35');
      expect(video().durationLabel, '0:00');
    });
  });

  group('vue unique', () {
    ChatMessage sealed({
      MessageType type = MessageType.image,
      String sender = 'moi',
      DateTime? openedAt,
      bool deleted = false,
    }) => ChatMessage(
      id: 'u',
      senderUid: sender,
      type: type,
      content: openedAt == null ? 'https://exemple.test/u.jpg' : '',
      viewOnce: true,
      viewOnceOpenedAt: openedAt,
      deleted: deleted,
      createdAt: base,
    );

    test('seul le destinataire peut ouvrir, et une seule fois', () {
      expect(sealed().canOpenViewOnce('autre'), true);
      expect(sealed().canOpenViewOnce('moi'), false, reason: 'l’expéditeur');
      expect(sealed(openedAt: base).canOpenViewOnce('autre'), false);
      expect(sealed(deleted: true).canOpenViewOnce('autre'), false);
    });

    test('un message ordinaire ne s’ouvre pas comme une vue unique', () {
      expect(msg('a').canOpenViewOnce('autre'), false);
    });

    test('l’aperçu tait le contenu, avant comme après ouverture', () {
      expect(sealed().shortPreview, '👁 Photo · vue unique');
      expect(sealed(openedAt: base).shortPreview, '👁 Photo ouvert');
      expect(
        sealed(type: MessageType.voice).shortPreview,
        '👁 Message vocal · vue unique',
      );
      expect(sealed(type: MessageType.video).shortPreview, '👁 Vidéo · vue unique');
    });

    test('seuls les types qui s’ouvrent acceptent la vue unique', () {
      expect(sealed(type: MessageType.image).supportsViewOnce, true);
      expect(sealed(type: MessageType.video).supportsViewOnce, true);
      expect(sealed(type: MessageType.voice).supportsViewOnce, true);
      expect(msg('t', type: MessageType.text).supportsViewOnce, false);
      expect(msg('d', type: MessageType.document).supportsViewOnce, false);
    });

    test('la bulle reste une ligne de texte, pas un média bord à bord', () {
      expect(sealed().isMediaBubble, false);
      expect(sealed(type: MessageType.video).isMediaBubble, false);
    });

    test('une photo à vue unique ne rejoint pas un album', () {
      final groups = groupChatMessages([
        msg('a'),
        sealed(),
        msg('b', offset: const Duration(seconds: 2)),
      ]);
      expect(groups.map((g) => g.length), [1, 1, 1]);
    });

    test('copyWith conserve la vue unique et la vignette', () {
      final pending = ChatMessage(
        id: 'v',
        senderUid: 'moi',
        type: MessageType.video,
        content: '/tmp/v.mp4',
        thumbUrl: '/tmp/v.jpg',
        viewOnce: true,
        createdAt: base,
        status: MessageDeliveryStatus.sending,
      ).copyWith(status: MessageDeliveryStatus.failed);

      expect(pending.viewOnce, true);
      expect(pending.thumbUrl, '/tmp/v.jpg');
      expect(pending.status, MessageDeliveryStatus.failed);
    });

    test('le drapeau et la vignette font l’aller-retour par toMap', () {
      final map = ChatMessage(
        id: 'v',
        senderUid: 'moi',
        type: MessageType.video,
        content: 'https://exemple.test/v.mp4',
        thumbUrl: 'https://exemple.test/v.jpg',
        viewOnce: true,
        createdAt: base,
      ).toMap();

      expect(map['viewOnce'], true);
      expect(map['thumbUrl'], 'https://exemple.test/v.jpg');
      // Un message ordinaire n'écrit ni l'un ni l'autre : inutile de
      // porter `viewOnce: false` sur chaque message de la base.
      final plain = msg('a').toMap();
      expect(plain.containsKey('viewOnce'), false);
      expect(plain.containsKey('thumbUrl'), false);
    });
  });

  group('capture d’écran signalée', () {
    ChatMessage shot({DateTime? at}) => ChatMessage(
      id: 'u',
      senderUid: 'moi',
      type: MessageType.image,
      content: '',
      viewOnce: true,
      viewOnceOpenedAt: base,
      screenshotAt: at,
      createdAt: base,
    );

    test('le drapeau suit la présence de l’horodatage', () {
      expect(shot().wasScreenshotted, false);
      expect(shot(at: base).wasScreenshotted, true);
    });

    test('copyWith ne perd pas le signalement', () {
      final updated = shot(
        at: base,
      ).copyWith(status: MessageDeliveryStatus.sent);
      expect(updated.screenshotAt, base);
      expect(updated.wasScreenshotted, true);
    });

    test('rien n’est écrit à l’envoi : c’est le destinataire qui pose', () {
      expect(shot(at: base).toMap().containsKey('screenshotAt'), false);
    });
  });

}
