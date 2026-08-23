import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class FollowService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _followersRef(String uid) =>
      _db.collection('users').doc(uid).collection('followers');

  CollectionReference<Map<String, dynamic>> _followingRef(String uid) =>
      _db.collection('users').doc(uid).collection('following');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> follow(String myUid, String targetUid) async {
    if (myUid == targetUid) return;

    final alreadyFollowing =
        await _followingRef(myUid).doc(targetUid).get();
    if (alreadyFollowing.exists) return;

    final targetDoc = await _userRef(targetUid).get();
    if (!targetDoc.exists) return;

    final batch = _db.batch();
    batch.set(_followingRef(myUid).doc(targetUid), {
      'followedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_followersRef(targetUid).doc(myUid), {
      'followedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_userRef(myUid), {
      'followingCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
    batch.set(_userRef(targetUid), {
      'followersCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> unfollow(String myUid, String targetUid) async {
    if (myUid == targetUid) return;

    final followDoc = await _followingRef(myUid).doc(targetUid).get();
    if (!followDoc.exists) return;

    final batch = _db.batch();
    batch.delete(_followingRef(myUid).doc(targetUid));
    batch.delete(_followersRef(targetUid).doc(myUid));
    batch.set(_userRef(myUid), {
      'followingCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
    batch.set(_userRef(targetUid), {
      'followersCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<bool> isFollowing(String myUid, String targetUid) async {
    final doc = await _followingRef(myUid).doc(targetUid).get();
    return doc.exists;
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> watchFollowStatus({
    required String myUid,
    required String targetUid,
    required void Function(bool isFollowing) onData,
  }) {
    return _followingRef(myUid).doc(targetUid).snapshots().listen((doc) {
      onData(doc.exists);
    });
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile({
    required String uid,
    required void Function(Map<String, dynamic>? data) onData,
  }) {
    return _userRef(uid).snapshots().listen((doc) {
      onData(doc.exists ? doc.data() : null);
    });
  }

  Future<List<String>> getFollowers(String uid, {int limit = 50}) async {
    final snap = await _followersRef(uid)
        .orderBy('followedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<List<String>> getFollowing(String uid, {int limit = 50}) async {
    final snap = await _followingRef(uid)
        .orderBy('followedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }
}
