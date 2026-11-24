import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_message.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageAt,
    this.lastMessageSenderUid,
    this.ephemeralSeconds,
    required this.createdAt,
    this.otherUserName,
    this.otherUserPhotoUrl,
    this.otherUserVerified = false,
    this.unreadCount = 0,
    this.lastCallLabel,
  });

  /// Aperçu d'une trace d'appel en dernier message (« 📞 Appel vocal
  /// manqué »), calculé à la lecture : il dépend de qui regarde.
  final String? lastCallLabel;

  final String id;
  final List<String> participants;
  final String? lastMessage;
  final MessageType? lastMessageType;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderUid;
  final int? ephemeralSeconds;
  final DateTime createdAt;
  final String? otherUserName;

  /// Photo de profil de l'interlocuteur — absente du document
  /// `conversations`, hydratée par `ConversationsController._enrich` depuis
  /// le profil. `null` = pas de photo, l'UI retombe sur les initiales.
  final String? otherUserPhotoUrl;

  final bool otherUserVerified;
  final int unreadCount;

  String otherUid(String myUid) =>
      participants.firstWhere((uid) => uid != myUid, orElse: () => '');

  String get lastMessagePreview {
    if (lastMessage == null) return '';
    if (lastMessageType == MessageType.call && lastCallLabel != null) {
      return lastCallLabel!;
    }
    return switch (lastMessageType) {
      MessageType.voice => '🎤 Message vocal',
      MessageType.image => '📷 Photo',
      MessageType.video => '🎥 Vidéo',
      MessageType.document => '📎 ${lastMessage!}',
      MessageType.sticker => lastMessage!,
      _ => lastMessage!,
    };
  }

  static String buildId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Conversation copyWith({
    String? otherUserName,
    String? otherUserPhotoUrl,
    bool? otherUserVerified,
    int? unreadCount,
  }) => Conversation(
    id: id,
    participants: participants,
    lastMessage: lastMessage,
    lastMessageType: lastMessageType,
    lastMessageAt: lastMessageAt,
    lastMessageSenderUid: lastMessageSenderUid,
    ephemeralSeconds: ephemeralSeconds,
    createdAt: createdAt,
    otherUserName: otherUserName ?? this.otherUserName,
    otherUserPhotoUrl: otherUserPhotoUrl ?? this.otherUserPhotoUrl,
    otherUserVerified: otherUserVerified ?? this.otherUserVerified,
    unreadCount: unreadCount ?? this.unreadCount,
    lastCallLabel: lastCallLabel,
  );

  factory Conversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String myUid,
  }) {
    final d = doc.data()!;
    final unreadMap = d['unreadCounts'] as Map<String, dynamic>?;
    final unread = unreadMap?[myUid];
    return Conversation(
      id: doc.id,
      participants: List<String>.from(d['participants'] ?? []),
      lastMessage: d['lastMessage'] as String?,
      lastMessageType: d['lastMessageType'] == null
          ? null
          : MessageType.values.firstWhere(
              (t) => t.name == d['lastMessageType'],
              orElse: () => MessageType.text,
            ),
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderUid: d['lastMessageSenderUid'] as String?,
      ephemeralSeconds: d['ephemeralSeconds'] as int?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadCount: unread is int ? unread : (unread as num?)?.toInt() ?? 0,
      lastCallLabel: _callLabel(
        d['lastCall'],
        d['lastMessageSenderUid'],
        myUid,
      ),
    );
  }

  static String? _callLabel(Object? raw, Object? senderUid, String myUid) {
    if (raw is! Map) return null;
    final outcome = CallOutcome.values
        .where((o) => o.name == raw['outcome'])
        .firstOrNull;
    if (outcome == null) return null;
    final video = raw['type'] == 'video';
    final l = callLogLabel(
      video: video,
      outcome: outcome,
      mine: senderUid == myUid,
      durationMs: (raw['durationMs'] as num?)?.toInt(),
    );
    return '${video ? '📹' : '📞'} ${l.label}';
  }
}
