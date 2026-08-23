import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, voice, image, document, sticker }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.type,
    required this.content,
    this.fileName,
    this.durationMs,
    required this.createdAt,
    this.readAt,
    this.expiresAt,
  });

  final String id;
  final String senderUid;
  final MessageType type;
  final String content;
  final String? fileName;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isRead => readAt != null;

  String get voiceDurationLabel {
    if (durationMs == null) return '0:00';
    final secs = (durationMs! / 1000).round();
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
        'senderUid': senderUid,
        'type': type.name,
        'content': content,
        if (fileName != null) 'fileName': fileName,
        if (durationMs != null) 'durationMs': durationMs,
        'createdAt': FieldValue.serverTimestamp(),
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      };

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChatMessage(
      id: doc.id,
      senderUid: d['senderUid'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => MessageType.text,
      ),
      content: d['content'] as String? ?? '',
      fileName: d['fileName'] as String?,
      durationMs: d['durationMs'] as int?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (d['readAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
    );
  }
}
