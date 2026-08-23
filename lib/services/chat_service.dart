import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';

class ChatService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _convRef =>
      _db.collection('conversations');

  CollectionReference<Map<String, dynamic>> _msgRef(String convId) =>
      _convRef.doc(convId).collection('messages');

  Future<Conversation> getOrCreateConversation(
    String myUid,
    String targetUid,
  ) async {
    final convId = Conversation.buildId(myUid, targetUid);
    final doc = await _convRef.doc(convId).get();

    if (doc.exists) return Conversation.fromDoc(doc);

    final data = {
      'participants': [myUid, targetUid],
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _convRef.doc(convId).set(data);

    return Conversation(
      id: convId,
      participants: [myUid, targetUid],
      createdAt: DateTime.now(),
    );
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderUid,
    required MessageType type,
    required String content,
    String? fileName,
    int? durationMs,
    int? ephemeralSeconds,
  }) async {
    DateTime? expiresAt;
    if (ephemeralSeconds != null && ephemeralSeconds > 0) {
      expiresAt = DateTime.now().add(Duration(seconds: ephemeralSeconds));
    }

    final msg = ChatMessage(
      id: '',
      senderUid: senderUid,
      type: type,
      content: content,
      fileName: fileName,
      durationMs: durationMs,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );

    final lastMsgPreview = switch (type) {
      MessageType.voice => '🎤 Message vocal',
      MessageType.image => '📷 Photo',
      MessageType.document => fileName ?? '📎 Document',
      MessageType.sticker => content,
      MessageType.text => content.length > 80
          ? '${content.substring(0, 80)}…'
          : content,
    };

    final batch = _db.batch();
    batch.set(_msgRef(conversationId).doc(), msg.toMap());
    batch.set(_convRef.doc(conversationId), {
      'lastMessage': lastMsgPreview,
      'lastMessageType': type.name,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderUid': senderUid,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      watchConversations({
    required String myUid,
    required void Function(List<Conversation>) onData,
    void Function(Object error)? onError,
  }) {
    return _convRef
        .where('participants', arrayContains: myUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        onData(snap.docs.map(Conversation.fromDoc).toList());
      },
      onError: onError ?? (_) {},
    );
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMessages({
    required String conversationId,
    required void Function(List<ChatMessage>) onData,
    void Function(Object error)? onError,
    int limit = 50,
  }) {
    return _msgRef(conversationId)
        .orderBy('createdAt', descending: false)
        .limitToLast(limit)
        .snapshots()
        .listen(
      (snap) {
        final messages = snap.docs
            .map(ChatMessage.fromDoc)
            .where((m) => !m.isExpired)
            .toList();
        onData(messages);
      },
      onError: onError ?? (_) {},
    );
  }

  Future<void> markAsRead(
    String conversationId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(_msgRef(conversationId).doc(id), {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> setEphemeral(String conversationId, int? seconds) async {
    await _convRef.doc(conversationId).set({
      'ephemeralSeconds': seconds,
    }, SetOptions(merge: true));
  }

  Future<String> uploadVoice(String filePath, String conversationId) async {
    final fileName = '${_uuid.v4()}.m4a';
    final ref = _storage.ref('chat/$conversationId/voice/$fileName');
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }

  Future<String> uploadImage(String filePath, String conversationId) async {
    final ext = filePath.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    final ref = _storage.ref('chat/$conversationId/images/$fileName');
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }

  Future<String> uploadDocument(
    String filePath,
    String conversationId,
    String originalName,
  ) async {
    final ref =
        _storage.ref('chat/$conversationId/docs/${_uuid.v4()}_$originalName');
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }
}
