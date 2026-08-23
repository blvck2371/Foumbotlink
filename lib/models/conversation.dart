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
    this.otherUserVerified = false,
    this.unreadCount = 0,
  });

  final String id;
  final List<String> participants;
  final String? lastMessage;
  final MessageType? lastMessageType;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderUid;
  final int? ephemeralSeconds;
  final DateTime createdAt;
  final String? otherUserName;
  final bool otherUserVerified;
  final int unreadCount;

  String otherUid(String myUid) =>
      participants.firstWhere((uid) => uid != myUid, orElse: () => '');

  String get lastMessagePreview {
    if (lastMessage == null) return '';
    return switch (lastMessageType) {
      MessageType.voice => '🎤 Message vocal',
      MessageType.image => '📷 Photo',
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
    bool? otherUserVerified,
    int? unreadCount,
  }) =>
      Conversation(
        id: id,
        participants: participants,
        lastMessage: lastMessage,
        lastMessageType: lastMessageType,
        lastMessageAt: lastMessageAt,
        lastMessageSenderUid: lastMessageSenderUid,
        ephemeralSeconds: ephemeralSeconds,
        createdAt: createdAt,
        otherUserName: otherUserName ?? this.otherUserName,
        otherUserVerified: otherUserVerified ?? this.otherUserVerified,
        unreadCount: unreadCount ?? this.unreadCount,
      );

  factory Conversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
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
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
