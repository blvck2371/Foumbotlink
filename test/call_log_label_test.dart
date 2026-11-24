import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/chat_message.dart';

void main() {
  String label(
    CallOutcome o, {
    bool mine = false,
    bool video = false,
    int? ms,
  }) =>
      callLogLabel(video: video, outcome: o, mine: mine, durationMs: ms).label;

  test('appel répondu : durée, des deux côtés', () {
    expect(label(CallOutcome.ended, ms: 192000), 'Appel vocal · 3:12');
    expect(
      label(CallOutcome.ended, mine: true, video: true, ms: 3723000),
      'Appel vidéo · 1:02:03',
    );
  });

  test('appelé : manqué, en rouge, même quand l\'appelant a raccroché', () {
    for (final o in [
      CallOutcome.missed,
      CallOutcome.cancelled,
      CallOutcome.busy,
    ]) {
      final l = callLogLabel(video: false, outcome: o, mine: false);
      expect(l.label, 'Appel vocal manqué');
      expect(l.missed, isTrue);
    }
    expect(label(CallOutcome.declined), 'Appel vocal refusé');
  });

  test('appelant : jamais « manqué », et le refus n\'est pas révélé', () {
    expect(label(CallOutcome.missed, mine: true), 'Appel vocal · Sans réponse');
    expect(
      label(CallOutcome.declined, mine: true),
      'Appel vocal · Sans réponse',
    );
    expect(label(CallOutcome.cancelled, mine: true), 'Appel vocal · Annulé');
    expect(label(CallOutcome.busy, mine: true), 'Appel vocal · Occupé');
  });

  test('message de trace d\'appel lu depuis Firestore', () {
    final m = ChatMessage.fromMap('calls_x', {
      'senderUid': 'ana',
      'type': 'call',
      'content': '',
      'callType': 'video',
      'callOutcome': 'missed',
      'durationMs': 0,
    });
    expect(m.isCallLog, isTrue);
    expect(m.callLabel('ben').label, 'Appel vidéo manqué');
    expect(m.callLabel('ana').label, 'Appel vidéo · Sans réponse');
    expect(m.listPreview, '📹 Appel vidéo');
  });
}
