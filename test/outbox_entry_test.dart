import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/chat_message.dart';
import 'package:foumbotlik/models/outbox_entry.dart';

void main() {
  final at = DateTime(2026, 11, 20, 18, 5);

  ChatMessage pending(
    MessageType type, {
    bool viewOnce = false,
    String? thumb,
    MessageDeliveryStatus status = MessageDeliveryStatus.sending,
  }) => ChatMessage(
    id: 'm1',
    senderUid: 'alice',
    type: type,
    content: '/app/chat_outbox/m1.mp4',
    fileName: type == MessageType.document ? 'Contrat été.pdf' : null,
    durationMs: 42000,
    thumbUrl: thumb,
    viewOnce: viewOnce,
    createdAt: at,
    expiresAt: at.add(const Duration(days: 1)),
    replyToId: 'm0',
    replyToSenderUid: 'bob',
    replyToText: 'Envoie la vidéo',
    status: status,
    hasServerTimestamp: false,
  );

  List<OutboxEntry> roundTrip(List<OutboxEntry> entries) =>
      OutboxEntry.decodeAll(OutboxEntry.encodeAll(entries));

  group('file d’envoi : sauvegarde puis relecture au redémarrage', () {
    test('une vidéo HD revient avec tout ce qu’il faut pour repartir', () {
      final back = roundTrip([
        OutboxEntry(
          conversationId: 'alice_bob',
          message: pending(
            MessageType.video,
            thumb: '/app/chat_outbox/m1_thumb.jpg',
          ),
          videoQuality: 'hd',
        ),
      ]).single;
      final m = back.message;
      expect(back.conversationId, 'alice_bob');
      expect(back.videoQuality, 'hd');
      expect(m.id, 'm1');
      expect(m.senderUid, 'alice');
      expect(m.type, MessageType.video);
      expect(m.content, '/app/chat_outbox/m1.mp4');
      expect(m.thumbUrl, '/app/chat_outbox/m1_thumb.jpg');
      expect(m.durationMs, 42000);
      expect(m.createdAt, at);
      expect(m.expiresAt, at.add(const Duration(days: 1)));
      expect(m.replyToId, 'm0');
      expect(m.replyToText, 'Envoie la vidéo');
    });

    test('la vue unique n’est jamais perdue en route', () {
      final back = roundTrip([
        OutboxEntry(
          conversationId: 'alice_bob',
          message: pending(MessageType.image, viewOnce: true),
        ),
      ]).single;
      expect(back.message.viewOnce, isTrue);
    });

    test('le nom d’origine d’un document est gardé', () {
      final back = roundTrip([
        OutboxEntry(
          conversationId: 'alice_bob',
          message: pending(MessageType.document),
        ),
      ]).single;
      expect(back.message.fileName, 'Contrat été.pdf');
    });

    test('relu, un envoi interrompu s’affiche en échec, prêt à renvoyer', () {
      final back = roundTrip([
        OutboxEntry(
          conversationId: 'alice_bob',
          message: pending(MessageType.voice),
        ),
      ]).single;
      expect(back.message.status, MessageDeliveryStatus.failed);
      expect(back.message.hasServerTimestamp, isFalse);
    });

    test('texte et sticker ne passent pas par la file (Firestore s’en charge)', () {
      expect(OutboxEntry.isMedia(MessageType.text), isFalse);
      expect(OutboxEntry.isMedia(MessageType.sticker), isFalse);
      for (final t in [
        MessageType.image,
        MessageType.video,
        MessageType.voice,
        MessageType.document,
      ]) {
        expect(OutboxEntry.isMedia(t), isTrue, reason: t.name);
      }
    });
  });

  group('sauvegarde abîmée : la discussion s’ouvre quand même', () {
    test('vide ou absente', () {
      expect(OutboxEntry.decodeAll(null), isEmpty);
      expect(OutboxEntry.decodeAll(''), isEmpty);
    });

    test('JSON tronqué (app tuée en pleine écriture)', () {
      expect(OutboxEntry.decodeAll('[{"id":"m1","type":"ima'), isEmpty);
    });

    test('pas une liste', () {
      expect(OutboxEntry.decodeAll('{"id":"m1"}'), isEmpty);
    });

    test('les entrées illisibles sont écartées, les bonnes gardées', () {
      final good = OutboxEntry.encodeAll([
        OutboxEntry(
          conversationId: 'alice_bob',
          message: pending(MessageType.image),
        ),
      ]);
      final mixed =
          '[${good.substring(1, good.length - 1)},'
          '{"id":"x","conversationId":"c","type":"hologramme","path":"/p"},'
          '{"id":"","conversationId":"c","type":"image","path":"/p"},'
          '{"conversationId":"c","type":"image"},'
          '{"id":"t","conversationId":"c","type":"text","path":"/p"},'
          '42]';
      final back = OutboxEntry.decodeAll(mixed);
      expect(back, hasLength(1));
      expect(back.single.message.type, MessageType.image);
    });
  });
}
