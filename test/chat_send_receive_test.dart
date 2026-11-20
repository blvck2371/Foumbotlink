import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/chat_attachment.dart';
import 'package:foumbotlik/models/chat_message.dart';

/// Ce qu'un message devient en traversant Firestore : les maps imbriquées
/// reviennent en `Map<String, dynamic>`, quel qu'ait été leur type à
/// l'écriture.
Map<String, dynamic> _throughFirestore(Map<String, dynamic> map) {
  Object? walk(Object? v) => switch (v) {
    Map() => {for (final e in v.entries) e.key as String: walk(e.value)},
    List() => [for (final x in v) walk(x)],
    _ => v,
  };
  return walk(map)! as Map<String, dynamic>;
}

/// Envoi par l'expéditeur puis réception par le destinataire, sans réseau :
/// ce que l'un écrit (`toMap`) est exactement ce que l'autre relit
/// (`fromMap`).
ChatMessage _sendAndReceive(ChatMessage sent) =>
    ChatMessage.fromMap(sent.id, _throughFirestore(sent.toMap()));

void main() {
  final at = DateTime(2026, 11, 20, 14, 30);

  ChatMessage message(
    MessageType type,
    String content, {
    String? fileName,
    int? durationMs,
    String? thumbUrl,
    bool viewOnce = false,
    String? replyToId,
    String? replyToText,
    DateTime? expiresAt,
  }) => ChatMessage(
    id: 'm_${type.name}',
    senderUid: 'alice',
    type: type,
    content: content,
    fileName: fileName,
    durationMs: durationMs,
    thumbUrl: thumbUrl,
    viewOnce: viewOnce,
    createdAt: at,
    expiresAt: expiresAt,
    replyToId: replyToId,
    replyToSenderUid: replyToId == null ? null : 'bob',
    replyToText: replyToText,
  );

  group('envoi → réception, chaque type de message', () {
    test('texte', () {
      final got = _sendAndReceive(message(MessageType.text, 'Bonjour 👋'));
      expect(got.type, MessageType.text);
      expect(got.content, 'Bonjour 👋');
      expect(got.senderUid, 'alice');
      expect(got.createdAt, at);
      expect(got.hasServerTimestamp, isTrue);
      expect(got.isRead, isFalse);
      expect(got.shortPreview, 'Bonjour 👋');
    });

    test('photo', () {
      final got = _sendAndReceive(
        message(MessageType.image, 'https://cdn.test/a.jpg'),
      );
      expect(got.type, MessageType.image);
      expect(got.content, 'https://cdn.test/a.jpg');
      expect(got.isMediaBubble, isTrue);
      expect(got.shortPreview, '📷 Photo');
    });

    test('vidéo : durée et vignette arrivent avec le message', () {
      final got = _sendAndReceive(
        message(
          MessageType.video,
          'https://cdn.test/v.mp4',
          durationMs: 42000,
          thumbUrl: 'https://cdn.test/v_thumb.jpg',
        ),
      );
      expect(got.type, MessageType.video);
      expect(got.durationMs, 42000);
      expect(got.thumbUrl, 'https://cdn.test/v_thumb.jpg');
      expect(got.durationLabel, '0:42');
      expect(got.shortPreview, '🎥 Vidéo');
    });

    test('message vocal : la durée est conservée', () {
      final got = _sendAndReceive(
        message(MessageType.voice, 'https://cdn.test/a.m4a', durationMs: 7000),
      );
      expect(got.type, MessageType.voice);
      expect(got.durationMs, 7000);
      expect(got.shortPreview, '🎤 Message vocal');
    });

    test('document PDF : le nom d’origine voyage avec le message', () {
      final got = _sendAndReceive(
        message(
          MessageType.document,
          'https://cdn.test/docs/x_Facture_mars.pdf',
          fileName: 'Facture mars #2.pdf',
        ),
      );
      expect(got.type, MessageType.document);
      expect(got.fileName, 'Facture mars #2.pdf');
      expect(got.shortPreview, '📎 Facture mars #2.pdf');
    });

    test('sticker', () {
      final got = _sendAndReceive(message(MessageType.sticker, '🎉'));
      expect(got.type, MessageType.sticker);
      expect(got.shortPreview, '🎉');
    });

    test('réponse : la citation est relue par le destinataire', () {
      final got = _sendAndReceive(
        message(
          MessageType.text,
          'Oui !',
          replyToId: 'm0',
          replyToText: 'On se voit demain ?',
        ),
      );
      expect(got.isReply, isTrue);
      expect(got.replyToId, 'm0');
      expect(got.replyToSenderUid, 'bob');
      expect(got.replyToText, 'On se voit demain ?');
    });

    test('vue unique : le type est annoncé, jamais le contenu', () {
      final got = _sendAndReceive(
        message(MessageType.image, 'https://cdn.test/s.jpg', viewOnce: true),
      );
      expect(got.viewOnce, isTrue);
      expect(got.viewOnceConsumed, isFalse);
      expect(got.shortPreview, '👁 Photo · vue unique');
    });

    test('message éphémère : l’échéance est transmise', () {
      final got = _sendAndReceive(
        message(
          MessageType.text,
          'Secret',
          expiresAt: at.add(const Duration(hours: 24)),
        ),
      );
      expect(got.expiresAt, at.add(const Duration(hours: 24)));
    });

    test('un type inconnu (version plus récente) retombe sur du texte', () {
      final got = ChatMessage.fromMap('x', {
        'senderUid': 'alice',
        'type': 'sondage',
        'content': 'Quel jour ?',
        'createdAt': Timestamp.fromDate(at),
      });
      expect(got.type, MessageType.text);
      expect(got.content, 'Quel jour ?');
    });

    test('un message sans horodatage serveur reste lisible', () {
      final got = ChatMessage.fromMap('x', {
        'senderUid': 'alice',
        'type': 'text',
        'content': 'Hors ligne',
      });
      expect(got.hasServerTimestamp, isFalse);
      expect(got.content, 'Hors ligne');
    });
  });

  group('après réception', () {
    test('lu, réactions et suppression sont relus', () {
      final got = ChatMessage.fromMap('x', {
        'senderUid': 'alice',
        'type': 'image',
        'content': '',
        'createdAt': Timestamp.fromDate(at),
        'readAt': Timestamp.fromDate(at.add(const Duration(minutes: 1))),
        'deleted': true,
        'reactions': {'bob': '❤️'},
        'hiddenFor': ['bob'],
      });
      expect(got.isRead, isTrue);
      expect(got.deleted, isTrue);
      expect(got.shortPreview, 'Message supprimé');
      expect(got.isHiddenFor('bob'), isTrue);
      expect(got.isHiddenFor('alice'), isFalse);
    });

    test('vue unique ouverte : le contenu a disparu', () {
      final got = ChatMessage.fromMap('x', {
        'senderUid': 'alice',
        'type': 'voice',
        'content': '',
        'viewOnce': true,
        'viewOnceOpenedAt': Timestamp.fromDate(at),
        'createdAt': Timestamp.fromDate(at),
      });
      expect(got.viewOnceConsumed, isTrue);
      expect(got.canOpenViewOnce('bob'), isFalse);
      expect(got.shortPreview, '👁 Message vocal ouvert');
    });

    test('seul l’expéditeur supprime pour tous, et dans le délai', () {
      final msg = message(MessageType.text, 'Oups');
      expect(msg.canDeleteForEveryone('alice', now: at), isTrue);
      expect(msg.canDeleteForEveryone('bob', now: at), isFalse);
      expect(
        msg.canDeleteForEveryone(
          'alice',
          now: at.add(ChatMessage.deleteForEveryoneWindow).add(
            const Duration(minutes: 1),
          ),
        ),
        isFalse,
      );
    });
  });

  group('pièces jointes', () {
    test('le type MIME suit le fichier', () {
      expect(ChatAttachment.contentTypeFor('Rapport.PDF'), 'application/pdf');
      expect(
        ChatAttachment.contentTypeFor('cv.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(ChatAttachment.contentTypeFor('compta.xlsx'), contains('sheet'));
      expect(ChatAttachment.contentTypeFor('voix.m4a'), 'audio/mp4');
      expect(ChatAttachment.contentTypeFor('clip.mov'), 'video/quicktime');
      expect(
        ChatAttachment.contentTypeFor('sans_extension'),
        'application/octet-stream',
      );
    });

    test('une photo PNG n’est pas annoncée en JPEG', () {
      expect(ChatAttachment.imageContentTypeFor('/tmp/capture.png'), 'image/png');
      expect(ChatAttachment.imageContentTypeFor('/tmp/a.jpg'), 'image/jpeg');
      expect(ChatAttachment.imageContentTypeFor('/tmp/inconnu'), 'image/jpeg');
    });

    test('le nom de stockage ne casse pas l’URL', () {
      expect(
        ChatAttachment.safeStorageName('Facture mars #2?.pdf'),
        'Facture_mars_2.pdf',
      );
      expect(ChatAttachment.safeStorageName('../../etc/passwd'), 'passwd');
      expect(ChatAttachment.safeStorageName('Été 2026.PDF'), 'Ete_2026.pdf');
      expect(ChatAttachment.safeStorageName('###.pdf'), 'document.pdf');
      expect(ChatAttachment.safeStorageName('.pdf'), 'pdf');
      final long = ChatAttachment.safeStorageName('${'a' * 200}.pdf');
      expect(long.length, lessThanOrEqualTo(64));
      expect(long, endsWith('.pdf'));
    });

    test('le téléchargement garde le nom d’origine, accents compris', () {
      final header = ChatAttachment.contentDispositionFor('Reçu été.pdf');
      expect(header, startsWith('inline;'));
      expect(header, contains("filename*=UTF-8''Re%C3%A7u%20%C3%A9t%C3%A9.pdf"));
    });

    test('badge et taille lisibles', () {
      expect(ChatAttachment.badgeFor('contrat.pdf'), 'PDF');
      expect(ChatAttachment.badgeFor('archive.tar.gz'), 'GZ');
      expect(ChatAttachment.badgeFor(null), 'FICHIER');
      expect(ChatAttachment.sizeLabel(500), '1 Ko');
      expect(ChatAttachment.sizeLabel(1536 * 1024), '1,5 Mo');
      expect(ChatAttachment.sizeLabel(25 * 1024 * 1024), '25 Mo');
    });

    test('un fichier trop lourd s’explique en clair', () {
      const e = ChatFileTooLarge(
        bytes: 25 * 1024 * 1024,
        maxBytes: ChatAttachment.maxFileBytes,
        what: 'Document',
      );
      expect(e.toString(), 'Document de 25 Mo : le maximum est 20 Mo.');
    });
  });

  group('aperçu de la liste des conversations', () {
    ChatMessage m(
      MessageType type,
      String content, {
      DateTime? expiresAt,
      bool viewOnce = false,
      String? fileName,
    }) => ChatMessage(
      id: 'x',
      senderUid: 'alice',
      type: type,
      content: content,
      fileName: fileName,
      viewOnce: viewOnce,
      createdAt: at,
      expiresAt: expiresAt,
    );

    test('un message éphémère ne livre jamais son contenu', () {
      final later = at.add(const Duration(seconds: 30));
      expect(
        m(MessageType.text, 'Mon code : 4512', expiresAt: later).listPreview,
        '⏱ Message éphémère',
      );
      expect(
        m(
          MessageType.document,
          'https://cdn.test/d.pdf',
          fileName: 'Relevé bancaire.pdf',
          expiresAt: later,
        ).listPreview,
        '⏱ Message éphémère',
      );
    });

    test('les autres messages gardent leur aperçu habituel', () {
      expect(m(MessageType.text, 'Salut').listPreview, 'Salut');
      expect(
        m(MessageType.text, 'a' * 100).listPreview,
        '${'a' * 80}…',
      );
      expect(
        m(MessageType.document, 'u', fileName: 'cv.pdf').listPreview,
        '📎 cv.pdf',
      );
      expect(
        m(MessageType.image, 'u', viewOnce: true).listPreview,
        '👁 Photo · vue unique',
      );
      expect(m(MessageType.voice, 'u').listPreview, '🎤 Message vocal');
    });

    test('un message expiré est reconnu comme tel', () {
      final past = ChatMessage(
        id: 'x',
        senderUid: 'alice',
        type: MessageType.text,
        content: 'parti',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(past.isExpired, isTrue);
    });
  });
}
