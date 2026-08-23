import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/conversation.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ConversationsController extends GetxController {
  final conversations = <Conversation>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  AuthService get _auth => Get.find<AuthService>();
  ChatService get _chat => Get.find<ChatService>();

  StreamSubscription? _sub;

  final _profileCache = <String, (String name, bool verified)>{};

  List<Conversation> get filtered {
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isEmpty) return conversations;
    return conversations.where((c) {
      final name = c.otherUserName?.toLowerCase() ?? '';
      return name.contains(q);
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    if (_auth.isSignedIn) _watch();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _watch() {
    _sub = _chat.watchConversations(
      myUid: _auth.uid,
      onData: (list) async {
        final enriched = await _enrichConversations(list);
        conversations.assignAll(enriched);
        isLoading.value = false;
      },
      onError: (_) {
        isLoading.value = false;
      },
    );
  }

  Future<List<Conversation>> _enrichConversations(
    List<Conversation> raw,
  ) async {
    final myUid = _auth.uid;

    final otherUids = raw
        .map((c) => c.otherUid(myUid))
        .where((uid) => uid.isNotEmpty && !_profileCache.containsKey(uid))
        .toSet();

    if (otherUids.isNotEmpty) {
      await Future.wait(otherUids.map((uid) async {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          if (doc.exists) {
            final data = doc.data()!;
            _profileCache[uid] = (
              data['displayName'] as String? ?? 'Utilisateur',
              data['verified'] as bool? ?? false,
            );
          } else {
            _profileCache[uid] = ('Utilisateur', false);
          }
        } on FirebaseException catch (_) {
          _profileCache[uid] = ('Utilisateur', false);
        }
      }));
    }

    return raw.map((conv) {
      final otherUid = conv.otherUid(myUid);
      final cached = _profileCache[otherUid];
      return conv.copyWith(
        otherUserName: cached?.$1 ?? 'Utilisateur',
        otherUserVerified: cached?.$2 ?? false,
      );
    }).toList();
  }

  void openChat(Conversation conv) {
    Get.toNamed(AppRoutes.chat, arguments: {
      'conversationId': conv.id,
      'otherUid': conv.otherUid(_auth.uid),
    });
  }

  Future<void> startNewChat() async {
    Get.toNamed(AppRoutes.community);
  }

  String timeLabel(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} j';
  }
}
