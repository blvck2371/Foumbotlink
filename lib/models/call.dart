import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }

enum CallStatus { ringing, accepted, declined, ended, missed, busy }

/// Où en est un membre d'un appel de groupe.
enum CallMemberState { ringing, joined, left, declined, missed, busy }

/// Une ligne de `members` dans un appel de groupe (voir functions/calls.js).
class CallMember {
  const CallMember({
    required this.uid,
    required this.state,
    required this.name,
    this.invitedBy,
  });

  final String uid;
  final CallMemberState state;
  final String name;
  final String? invitedBy;

  /// Occupe une place dans l'appel : en communication, ou son téléphone
  /// sonne.
  bool get isActive =>
      state == CallMemberState.ringing || state == CallMemberState.joined;

  factory CallMember.fromMap(String uid, Map<String, dynamic> d) => CallMember(
    uid: uid,
    state: CallMemberState.values.firstWhere(
      (s) => s.name == d['state'],
      orElse: () => CallMemberState.left,
    ),
    name: (d['name'] as String?)?.trim().isNotEmpty == true
        ? (d['name'] as String).trim()
        : 'Habitant',
    invitedBy: d['invitedBy'] as String?,
  );
}

/// Document d'appel (`calls/{callId}`) : qui appelle qui, et où en est la
/// sonnerie. La voix et l'image, elles, passent par la salle LiveKit
/// `call_{callId}` (voir CallService.joinRoom).
class Call {
  const Call({
    required this.id,
    required this.conversationId,
    required this.callerUid,
    required this.calleeUid,
    required this.type,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.isGroup = false,
    this.members = const {},
  });

  /// Plafond de participants simultanés (aligné sur MAX_CALL_MEMBERS de
  /// functions/calls.js).
  static const maxMembers = 8;

  final String id;
  final String conversationId;
  final String callerUid;
  final String calleeUid;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;

  /// Instant (horloge serveur) où l'appelé a décroché. Sert de référence
  /// **commune aux deux appareils** pour la durée affichée : chacun comptant
  /// de son côté, les deux chronos divergeaient de plusieurs secondes.
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// L'appel est passé en groupe : quelqu'un a été ajouté. Chacun quitte
  /// alors l'appel sans le couper pour les autres.
  final bool isGroup;

  /// Membres d'un appel de groupe, par uid. Vide pour un appel à deux.
  final Map<String, CallMember> members;

  /// Membres qui occupent une place (en communication ou qui sonnent).
  Iterable<CallMember> get activeMembers =>
      members.values.where((m) => m.isActive);

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
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answeredAt: (d['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (d['endedAt'] as Timestamp?)?.toDate(),
      isGroup: d['group'] == true,
      members: {
        for (final e in ((d['members'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is Map)
            e.key as String: CallMember.fromMap(
              e.key as String,
              Map<String, dynamic>.from(e.value as Map),
            ),
      },
    );
  }
}
