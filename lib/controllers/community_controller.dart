import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';

class CommunityController extends GetxController {
  final members = <UserProfile>[].obs;
  final followingSet = <String>{}.obs;
  final togglingSet = <String>{}.obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  AuthService get _auth => Get.find<AuthService>();
  FollowService get _follow => Get.find<FollowService>();

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  List<UserProfile> get filteredMembers {
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isEmpty) return members;
    return members.where((m) {
      return m.displayName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('displayName')
          .limit(100)
          .get();

      final list = snap.docs
          .map((doc) => UserProfile.fromMap(doc.id, doc.data()))
          .where((p) => p.displayName.isNotEmpty)
          .toList();

      members.assignAll(list);

      if (_uid != null) {
        await _loadFollowingStatus();
      }
    } on FirebaseException catch (_) {
      // Network or permission error — leave list empty
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadFollowingStatus() async {
    final uid = _uid;
    if (uid == null) return;

    final followingList = await _follow.getFollowing(uid, limit: 200);
    followingSet.assignAll(followingList.toSet());
  }

  bool isFollowing(String targetUid) => followingSet.contains(targetUid);

  bool isOwnProfile(String targetUid) => _uid == targetUid;

  Future<void> toggleFollow(String targetUid) async {
    if (togglingSet.contains(targetUid)) return;

    if (!_auth.isSignedIn) return;

    final uid = _uid!;
    togglingSet.add(targetUid);

    try {
      if (isFollowing(targetUid)) {
        await _follow.unfollow(uid, targetUid);
        followingSet.remove(targetUid);
      } else {
        await _follow.follow(uid, targetUid);
        followingSet.add(targetUid);
      }
      followingSet.refresh();
    } on FirebaseException catch (_) {
      // Revert silently on error
    } finally {
      togglingSet.remove(targetUid);
      togglingSet.refresh();
    }
  }

  @override
  Future<void> refresh() async {
    isLoading.value = true;
    await _loadMembers();
  }
}
