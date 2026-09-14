import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';

class CommunityController extends GetxController {
  /// Nombre de profils chargés par page. La liste s'allongeait jusqu'à
  /// 100 puis s'arrêtait sans rien dire : au-delà, les habitants inscrits
  /// n'existaient tout simplement pas pour l'application.
  static const pageSize = 30;

  final members = <UserProfile>[].obs;
  final followingSet = <String>{}.obs;
  final togglingSet = <String>{}.obs;
  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;
  final searchQuery = ''.obs;

  late final ScrollController scrollController;

  /// Dernier profil lu, curseur de la page suivante.
  DocumentSnapshot? _lastDoc;

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
    scrollController = ScrollController()..addListener(_onScroll);
    _loadMembers();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients ||
        isLoadingMore.value ||
        !hasMore.value) {
      return;
    }
    final pos = scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) loadMore();
  }

  Query<Map<String, dynamic>> get _baseQuery =>
      FirebaseFirestore.instance.collection('users').orderBy('displayName');

  Future<void> _loadMembers() async {
    _lastDoc = null;
    hasMore.value = true;
    final query = _baseQuery.limit(pageSize);

    // Cache local d'abord : la liste s'affiche instantanément au retour
    // sur l'écran, puis se recale sur la version serveur. Sans ça, chaque
    // ouverture restait sur son chargeur le temps d'un aller-retour
    // réseau.
    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        _applyMembers(cached);
        isLoading.value = false;
      }
    } on FirebaseException catch (_) {
      // Cache vide : on attend simplement la réponse serveur ci-dessous.
    }

    try {
      _applyMembers(await query.get());
    } on FirebaseException catch (_) {
      // Network or permission error — leave list empty
    } finally {
      isLoading.value = false;
    }

    // Les statuts de suivi arrivent après coup : ils ne décident que de
    // l'état d'un bouton et ne doivent pas retarder l'affichage.
    if (_uid != null) {
      try {
        await _loadFollowingStatus();
      } on FirebaseException catch (_) {
        // Sans réponse, les boutons restent sur « Suivre ».
      }
    }
  }

  void _applyMembers(QuerySnapshot<Map<String, dynamic>> snap) {
    if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
    // Basé sur la page brute : les profils sans nom sont écartés après la
    // requête, et une page raccourcie par ce filtrage ne veut pas dire
    // qu'on a atteint le dernier habitant inscrit.
    hasMore.value = snap.docs.length >= pageSize;
    members.assignAll(_profilesFrom(snap));
  }

  List<UserProfile> _profilesFrom(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((doc) => UserProfile.fromMap(doc.id, doc.data()))
          .where((p) => p.displayName.isNotEmpty)
          .toList();

  /// Page suivante. Comme pour le fil, une page entièrement filtrée
  /// n'allonge pas la liste et n'émettrait donc aucun nouvel événement de
  /// défilement : on enchaîne jusqu'à ramener au moins un profil.
  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      for (var chase = 0; chase < 5; chase++) {
        final cursor = _lastDoc;
        if (cursor == null) {
          hasMore.value = false;
          return;
        }
        final snap =
            await _baseQuery.startAfterDocument(cursor).limit(pageSize).get();
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        hasMore.value = snap.docs.length >= pageSize;

        final known = members.map((e) => e.uid).toSet();
        final additions =
            _profilesFrom(snap).where((p) => !known.contains(p.uid)).toList();
        if (additions.isNotEmpty) {
          members.addAll(additions);
          if (_uid != null) {
            await _loadFollowingStatus();
          }
          return;
        }
        if (!hasMore.value) return;
      }
    } on FirebaseException catch (_) {
      // Réseau ou droits : la liste reste en l'état, le prochain
      // défilement retentera.
    } finally {
      isLoadingMore.value = false;
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
