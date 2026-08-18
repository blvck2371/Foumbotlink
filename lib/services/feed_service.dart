import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/feed_item.dart';

class FeedService {
  static const pageSize = 8;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _postsRef =>
      _db.collection('posts');

  DocumentSnapshot? _lastDoc;

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  Future<List<FeedItem>> fetchPage({
    FeedFilter filter = FeedFilter.all,
    bool reset = false,
    String? currentUid,
  }) async {
    if (reset) _lastDoc = null;

    Query<Map<String, dynamic>> query =
        _postsRef.orderBy('publishedAt', descending: true);

    if (filter != FeedFilter.all && filter != FeedFilter.venteAchat) {
      final typeName = switch (filter) {
        FeedFilter.infos => 'info',
        FeedFilter.annonces => 'annonce',
        FeedFilter.population => 'post',
        _ => '',
      };
      query = query.where('type', isEqualTo: typeName);
    }

    if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);
    final snapshot = await query.limit(pageSize).get();
    if (snapshot.docs.isNotEmpty) _lastDoc = snapshot.docs.last;

    return snapshot.docs
        .map((doc) => _itemFromDoc(doc, currentUid))
        .toList();
  }

  Future<FeedItem?> getById(String id, {String? currentUid}) async {
    final doc = await _postsRef.doc(id).get();
    if (!doc.exists) return null;
    return _itemFromDoc(doc, currentUid);
  }

  FeedItem _itemFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String? currentUid,
  ) {
    final d = doc.data()!;
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
      publishedAt:
          (d['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
      likesCount: d['likesCount'] as int? ?? 0,
      likedByMe: currentUid != null && likedBy.contains(currentUid),
      commentsCount: d['commentsCount'] as int? ?? 0,
    );
  }

  // -----------------------------------------------------------------------
  // Créer un post (avec upload d'images vers Storage)
  // -----------------------------------------------------------------------

  Future<FeedItem> createPost({
    required FeedType type,
    required String title,
    required String body,
    required String authorUid,
    required String authorName,
    required String authorSubtitle,
    List<String> localImagePaths = const [],
  }) async {
    final docRef = _postsRef.doc();

    final imageUrls = await _uploadImages(
      localImagePaths,
      'posts/${docRef.id}',
    );

    final now = DateTime.now();
    await docRef.set({
      'type': type.name,
      'title': title.trim(),
      'body': body.trim(),
      'authorUid': authorUid,
      'authorName': authorName,
      'authorSubtitle': authorSubtitle,
      'publishedAt': Timestamp.fromDate(now),
      'imageUrls': imageUrls,
      'likesCount': 0,
      'likedBy': <String>[],
      'commentsCount': 0,
    });

    return FeedItem(
      id: docRef.id,
      type: type,
      title: title.trim(),
      body: body.trim(),
      authorUid: authorUid,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      publishedAt: now,
      imageUrls: imageUrls,
    );
  }

  // -----------------------------------------------------------------------
  // Likes
  // -----------------------------------------------------------------------

  Future<void> setLike(String postId, String uid, bool liked) async {
    final ref = _postsRef.doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final likedBy = List<String>.from(snap.data()?['likedBy'] ?? []);
      final alreadyLiked = likedBy.contains(uid);
      if (liked && alreadyLiked) return;
      if (!liked && !alreadyLiked) return;
      if (liked) {
        likedBy.add(uid);
      } else {
        likedBy.remove(uid);
      }
      tx.update(ref, {
        'likedBy': likedBy,
        'likesCount': likedBy.length,
      });
    });
  }

  // -----------------------------------------------------------------------
  // Commentaires
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) =>
      _postsRef.doc(postId).collection('comments');

  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorName,
    required String text,
    String? parentCommentId,
    String? replyToName,
  }) async {
    await _commentsRef(postId).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'text': text.trim(),
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'parentCommentId': parentCommentId,
      'replyToName': replyToName,
      'likesCount': 0,
      'likedBy': <String>[],
    });
    await _postsRef.doc(postId).update({
      'commentsCount': FieldValue.increment(1),
    });
  }

  Future<List<FeedComment>> fetchComments(
    String postId, {
    String? currentUid,
  }) async {
    final snapshot =
        await _commentsRef(postId).orderBy('createdAt').get();

    final flat = snapshot.docs.map((doc) {
      final d = doc.data();
      final likedBy = List<String>.from(d['likedBy'] ?? []);
      return (
        comment: FeedComment(
          id: doc.id,
          authorUid: d['authorUid'] as String? ?? '',
          authorName: d['authorName'] as String? ?? '',
          text: d['text'] as String? ?? '',
          createdAt:
              (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          parentCommentId: d['parentCommentId'] as String?,
          replyToName: d['replyToName'] as String?,
          likesCount: d['likesCount'] as int? ?? 0,
          likedByMe: currentUid != null && likedBy.contains(currentUid),
        ),
        parentId: d['parentCommentId'] as String?,
      );
    }).toList();

    return _buildTree(flat);
  }

  List<FeedComment> _buildTree(
    List<({FeedComment comment, String? parentId})> flat,
  ) {
    final childrenOf = <String?, List<FeedComment>>{};
    for (final entry in flat) {
      childrenOf.putIfAbsent(entry.parentId, () => []).add(entry.comment);
    }

    FeedComment attach(FeedComment c) {
      final children = childrenOf[c.id];
      if (children == null || children.isEmpty) return c;
      return c.copyWith(replies: children.map(attach).toList());
    }

    return (childrenOf[null] ?? []).map(attach).toList();
  }

  Future<void> setCommentLike(
    String postId,
    String commentId,
    String uid,
    bool liked,
  ) async {
    final ref = _commentsRef(postId).doc(commentId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final likedBy = List<String>.from(snap.data()?['likedBy'] ?? []);
      final alreadyLiked = likedBy.contains(uid);
      if (liked && alreadyLiked) return;
      if (!liked && !alreadyLiked) return;
      if (liked) {
        likedBy.add(uid);
      } else {
        likedBy.remove(uid);
      }
      tx.update(ref, {
        'likedBy': likedBy,
        'likesCount': likedBy.length,
      });
    });
  }

  // -----------------------------------------------------------------------
  // Temps réel
  // -----------------------------------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchPosts({
    String? currentUid,
    required void Function(FeedItem item) onAdded,
    required void Function(FeedItem item) onModified,
    required void Function(String id) onRemoved,
  }) {
    return _postsRef
        .orderBy('publishedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
            onAdded(_itemFromDoc(change.doc, currentUid));
          case DocumentChangeType.modified:
            onModified(_itemFromDoc(change.doc, currentUid));
          case DocumentChangeType.removed:
            onRemoved(change.doc.id);
        }
      }
    });
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchComments(
    String postId, {
    String? currentUid,
    required void Function(List<FeedComment> comments) onData,
  }) {
    return _commentsRef(postId)
        .orderBy('createdAt')
        .snapshots()
        .listen((snapshot) {
      final flat = snapshot.docs.map((doc) {
        final d = doc.data();
        final likedBy = List<String>.from(d['likedBy'] ?? []);
        return (
          comment: FeedComment(
            id: doc.id,
            authorUid: d['authorUid'] as String? ?? '',
            authorName: d['authorName'] as String? ?? '',
            text: d['text'] as String? ?? '',
            createdAt:
                (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            parentCommentId: d['parentCommentId'] as String?,
            replyToName: d['replyToName'] as String?,
            likesCount: d['likesCount'] as int? ?? 0,
            likedByMe: currentUid != null && likedBy.contains(currentUid),
          ),
          parentId: d['parentCommentId'] as String?,
        );
      }).toList();
      onData(_buildTree(flat));
    });
  }

  // -----------------------------------------------------------------------
  // Upload d'images
  // -----------------------------------------------------------------------

  Future<List<String>> _uploadImages(
    List<String> localPaths,
    String storagePath,
  ) async {
    final urls = <String>[];
    for (var i = 0; i < localPaths.length; i++) {
      final file = File(localPaths[i]);
      final ref = _storage.ref('$storagePath/$i.jpg');
      await ref.putFile(file);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}
