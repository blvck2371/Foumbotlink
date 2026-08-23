import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ChatController extends GetxController {
  final messages = <ChatMessage>[].obs;
  final otherProfile = Rxn<UserProfile>();
  final conversation = Rxn<Conversation>();
  final isLoading = true.obs;
  final isSending = false.obs;
  final isRecording = false.obs;
  final recordDuration = 0.obs;
  final ephemeralSeconds = Rxn<int>();
  final showStickers = false.obs;

  late final TextEditingController textController;
  late final ScrollController scrollController;
  late final AudioRecorder _recorder;

  Timer? _recordTimer;
  StreamSubscription? _msgSub;

  String _conversationId = '';
  String _otherUid = '';
  int _lastMessageCount = 0;

  AuthService get _auth => Get.find<AuthService>();
  ChatService get _chat => Get.find<ChatService>();

  String get myUid => _auth.uid;

  @override
  void onInit() {
    super.onInit();
    textController = TextEditingController();
    scrollController = ScrollController();
    _recorder = AudioRecorder();

    final args = Get.arguments as Map<String, dynamic>;
    _conversationId = args['conversationId'] as String;
    _otherUid = args['otherUid'] as String;

    _loadOtherProfile();
    _initConversation();
  }

  @override
  void onClose() {
    textController.dispose();
    scrollController.dispose();
    _msgSub?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.onClose();
  }

  Future<void> _loadOtherProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_otherUid)
          .get();
      if (doc.exists) {
        otherProfile.value = UserProfile.fromMap(doc.id, doc.data()!);
      }
    } on FirebaseException catch (_) {}
  }

  Future<void> _initConversation() async {
    try {
      final conv = await _chat.getOrCreateConversation(myUid, _otherUid);
      conversation.value = conv;
      _conversationId = conv.id;
      ephemeralSeconds.value = conv.ephemeralSeconds;
      _watchMessages();
    } on FirebaseException catch (_) {
      isLoading.value = false;
    }
  }

  void _watchMessages() {
    _msgSub?.cancel();
    _msgSub = _chat.watchMessages(
      conversationId: _conversationId,
      onData: (list) {
        final hasNewMessages = list.length > _lastMessageCount;
        _lastMessageCount = list.length;

        messages.assignAll(list);
        isLoading.value = false;

        if (hasNewMessages) _scrollToBottom();

        _batchMarkAsRead(list);
      },
      onError: (_) {
        isLoading.value = false;
      },
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _batchMarkAsRead(List<ChatMessage> list) {
    final unreadIds = list
        .where((m) => m.senderUid != myUid && !m.isRead)
        .map((m) => m.id)
        .toList();
    if (unreadIds.isEmpty) return;
    _chat.markAsRead(_conversationId, unreadIds);
  }

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty || isSending.value) return;

    textController.clear();
    isSending.value = true;
    try {
      await _chat.sendMessage(
        conversationId: _conversationId,
        senderUid: myUid,
        type: MessageType.text,
        content: text,
        ephemeralSeconds: ephemeralSeconds.value,
      );
    } on Exception catch (_) {
    } finally {
      isSending.value = false;
    }
  }

  Future<void> sendSticker(String emoji) async {
    showStickers.value = false;
    try {
      await _chat.sendMessage(
        conversationId: _conversationId,
        senderUid: myUid,
        type: MessageType.sticker,
        content: emoji,
        ephemeralSeconds: ephemeralSeconds.value,
      );
    } on Exception catch (_) {}
  }

  Future<void> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      isRecording.value = true;
      recordDuration.value = 0;
      _recordTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => recordDuration.value++,
      );
    } on Exception catch (_) {}
  }

  Future<void> stopRecording({bool cancel = false}) async {
    _recordTimer?.cancel();

    String? path;
    try {
      path = await _recorder.stop();
    } on Exception catch (_) {}
    isRecording.value = false;

    if (cancel || path == null || recordDuration.value < 1) {
      _safeDeleteFile(path);
      return;
    }

    final durationMs = recordDuration.value * 1000;
    isSending.value = true;
    try {
      final url = await _chat.uploadVoice(path, _conversationId);
      await _chat.sendMessage(
        conversationId: _conversationId,
        senderUid: myUid,
        type: MessageType.voice,
        content: url,
        durationMs: durationMs,
        ephemeralSeconds: ephemeralSeconds.value,
      );
    } on Exception catch (_) {
    } finally {
      isSending.value = false;
      _safeDeleteFile(path);
    }
  }

  Future<void> pickAndSendImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (xfile == null) return;

    isSending.value = true;
    try {
      final url = await _chat.uploadImage(xfile.path, _conversationId);
      await _chat.sendMessage(
        conversationId: _conversationId,
        senderUid: myUid,
        type: MessageType.image,
        content: url,
        ephemeralSeconds: ephemeralSeconds.value,
      );
    } on Exception catch (_) {
    } finally {
      isSending.value = false;
    }
  }

  Future<void> pickAndSendDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    isSending.value = true;
    try {
      final url = await _chat.uploadDocument(
        file.path!,
        _conversationId,
        file.name,
      );
      await _chat.sendMessage(
        conversationId: _conversationId,
        senderUid: myUid,
        type: MessageType.document,
        content: url,
        fileName: file.name,
        ephemeralSeconds: ephemeralSeconds.value,
      );
    } on Exception catch (_) {
    } finally {
      isSending.value = false;
    }
  }

  void toggleStickers() {
    showStickers.value = !showStickers.value;
  }

  Future<void> setEphemeral(int? seconds) async {
    ephemeralSeconds.value = seconds;
    try {
      await _chat.setEphemeral(_conversationId, seconds);
    } on Exception catch (_) {}
  }

  void _safeDeleteFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException catch (_) {}
  }
}
