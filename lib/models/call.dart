import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }

enum CallStatus { ringing, accepted, declined, ended, missed, busy }

/// Document de signalisation WebRTC (`calls/{callId}`). Ne transporte que
/// les métadonnées et les SDP offer/answer — les candidats ICE vivent
/// dans les sous-collections `callerCandidates` / `calleeCandidates` pour
/// pouvoir être ajoutés au fil de l'eau sans réécrire tout le document.
class Call {
  const Call({
    required this.id,
    required this.conversationId,
    required this.callerUid,
    required this.calleeUid,
    required this.type,
    required this.status,
    this.offer,
    this.answer,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  final String id;
  final String conversationId;
  final String callerUid;
  final String calleeUid;
  final CallType type;
  final CallStatus status;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime createdAt;

  /// Instant (horloge serveur) où l'appelé a décroché — écrit en même temps
  /// que l'`answer`. Sert de référence **commune aux deux appareils** pour la
  /// durée affichée : chacun comptant de son côté, les deux chronos
  /// divergeaient de plusieurs secondes.
  final DateTime? answeredAt;
  final DateTime? endedAt;

  Map<String, dynamic> toMap() => {
    'conversationId': conversationId,
    'callerUid': callerUid,
    'calleeUid': calleeUid,
    'type': type.name,
    'status': status.name,
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory Call.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Call(
      id: doc.id,
      conversationId: d['conversationId'] as String? ?? '',
      callerUid: d['callerUid'] as String? ?? '',
      calleeUid: d['calleeUid'] as String? ?? '',
      type: CallType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => CallType.audio,
      ),
      status: CallStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => CallStatus.ended,
      ),
      offer: (d['offer'] as Map<String, dynamic>?),
      answer: (d['answer'] as Map<String, dynamic>?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answeredAt: (d['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (d['endedAt'] as Timestamp?)?.toDate(),
    );
  }
}
