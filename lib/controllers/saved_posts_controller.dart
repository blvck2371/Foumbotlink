import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../models/feed_item.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/moderation_service.dart';
import 'home_controller.dart';

/// Écran « Enregistrés ». Volontairement sans écoute temps réel : la liste
/// se consulte, elle ne se regarde pas vivre. Un `get()` à l'ouverture et
/// un tirer-pour-rafraîchir suffisent, là où un `snapshots()` par post
/// coûterait une écoute permanente pour rien.
class SavedPostsController extends GetxController {
  final items = <FeedItem>[].obs;
  final isLoading = true.obs;

  AuthService get _auth => Get.find<AuthService>();
  FeedService get _feed => Get.find<FeedService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  HomeController get _home => Get.find<HomeController>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    if (!_auth.isSignedIn) {
      items.clear();
      isLoading.value = false;
      return;
    }
    try {
      final saved = await _feed.fetchSavedPosts(_auth.uid);
      items.assignAll([
        for (final post in saved)
          // Un auteur bloqué après coup ne doit pas réapparaître ici sous
          // prétexte que sa publication avait été mise de côté avant.
          if (!_moderation.isBlocked(post.authorUid))
            // `likedByMe` ne se lit pas dans le document du post : c'est
            // HomeController qui fait autorité, ici comme dans le fil.
            post.copyWith(likedByMe: _home.isLikedByMe(post.id)),
      ]);
    } catch (e) {
      developer.log(
        'Chargement des enregistrements',
        name: 'SavedPostsController',
        error: e,
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Retire le signet **et** la carte : sur cet écran, le retrait est le
  /// geste attendu, garder la ligne affichée serait déroutant.
  Future<void> unsave(FeedItem post) async {
    await _home.toggleSave(post);
    if (!_home.isSavedByMe(post.id)) {
      items.removeWhere((p) => p.id == post.id);
    }
  }

  void open(FeedItem post) => _home.openPost(post);

  String timeAgo(DateTime date) => _home.timeAgo(date);
}
