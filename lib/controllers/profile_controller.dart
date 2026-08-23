import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/feed_item.dart';
import '../models/user_profile.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';

class ProfileController extends GetxController {
  final targetUid = ''.obs;
  final profile = Rxn<UserProfile>();
  final posts = <FeedItem>[].obs;
  final isFollowing = false.obs;
  final isLoadingProfile = true.obs;
  final isLoadingPosts = true.obs;
  final isToggling = false.obs;

  AuthService get _auth => Get.find<AuthService>();
  FollowService get _follow => Get.find<FollowService>();

  StreamSubscription? _profileSub;
  StreamSubscription? _followSub;

  bool get isOwnProfile =>
      _auth.isSignedIn && _auth.uid == targetUid.value;

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  @override
  void onInit() {
    super.onInit();
    final uid = Get.arguments as String;
    targetUid.value = uid;
    _watchProfile(uid);
    _loadPosts(uid);
    if (_auth.isSignedIn && !isOwnProfile) {
      _watchFollowStatus(uid);
    }
  }

  @override
  void onClose() {
    _profileSub?.cancel();
    _followSub?.cancel();
    super.onClose();
  }

  void _watchProfile(String uid) {
    _profileSub = _follow.watchUserProfile(
      uid: uid,
      onData: (data) {
        if (data != null) {
          profile.value = UserProfile.fromMap(uid, data);
        } else {
          profile.value = null;
        }
        isLoadingProfile.value = false;
      },
    );
  }

  void _watchFollowStatus(String uid) {
    _followSub?.cancel();
    _followSub = _follow.watchFollowStatus(
      myUid: _auth.uid,
      targetUid: uid,
      onData: (following) {
        isFollowing.value = following;
      },
    );
  }

  Future<void> _loadPosts(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where('authorUid', isEqualTo: uid)
          .orderBy('publishedAt', descending: true)
          .limit(20)
          .get();
      posts.assignAll(snap.docs.map((doc) {
        final d = doc.data();
        final likedBy = List<String>.from(d['likedBy'] ?? []);
        return FeedItem(
          id: doc.id,
          type: FeedType.values.firstWhere(
            (t) => t.name == d['type'],
            orElse: () => FeedType.post,
          ),
          title: d['title'] as String? ?? '',
          body: d['body'] as String? ?? '',
          authorUid: d['authorUid'] as String? ?? '',
          authorName: d['authorName'] as String? ?? '',
          authorSubtitle: d['authorSubtitle'] as String? ?? '',
          authorVerified: d['authorVerified'] as bool? ?? false,
          publishedAt:
              (d['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          imageUrls: List<String>.from(d['imageUrls'] ?? []),
          likesCount: d['likesCount'] as int? ?? 0,
          likedByMe: _uid != null && likedBy.contains(_uid),
          commentsCount: d['commentsCount'] as int? ?? 0,
        );
      }));
    } on FirebaseException catch (_) {
      // Index pas encore prêt ou erreur réseau — on laisse la liste vide
    } finally {
      isLoadingPosts.value = false;
    }
  }

  Future<void> toggleFollow() async {
    if (isOwnProfile || isToggling.value) return;
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return;
      _watchFollowStatus(targetUid.value);
    }
    isToggling.value = true;
    try {
      if (isFollowing.value) {
        await _follow.unfollow(_auth.uid, targetUid.value);
      } else {
        await _follow.follow(_auth.uid, targetUid.value);
      }
    } on FirebaseException catch (_) {
      // Erreur réseau ou permissions — le bouton revient à son état
    } finally {
      isToggling.value = false;
    }
  }

  String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      return 'Il y a $m min';
    }
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} j';
  }
}
