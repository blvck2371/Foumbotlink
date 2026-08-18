import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/app_feature.dart';
import '../models/feed_item.dart';
import '../models/market_item.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/market_service.dart';
import '../services/user_profile_service.dart';
import '../theme/theme_controller.dart';

class HomeController extends GetxController {
  final unreadNotifications = 0.obs;

  final items = <FeedItem>[].obs;
  final marketItems = <MarketItem>[].obs;
  final filter = FeedFilter.all.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  late final ScrollController scrollController;
  StreamSubscription? _watchSub;
  StreamSubscription? _marketWatchSub;

  FeedService get _feed => Get.find<FeedService>();
  MarketService get _market => Get.find<MarketService>();
  ThemeController get _theme => Get.find<ThemeController>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  bool get isDarkMode => _theme.isDarkMode;
  List<AppFeature> get features => AppFeature.all;

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  bool get isAuthenticated => _auth.isSignedIn && _profiles.hasProfile;

  Future<bool> _ensureAuthenticated() async {
    if (_auth.isSignedIn) await _profiles.waitUntilLoaded();
    if (isAuthenticated) return true;
    await Get.toNamed(AppRoutes.auth);
    return isAuthenticated;
  }

  Future<void> signOut() => _auth.signOut();

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController()..addListener(_onScroll);
    _initialLoad();
  }

  @override
  void onClose() {
    _watchSub?.cancel();
    _marketWatchSub?.cancel();
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.onClose();
  }

  Future<void> _initialLoad() async {
    await refreshFeed();
    _startWatching();
  }

  void _startWatching() {
    _watchSub?.cancel();
    _marketWatchSub?.cancel();

    _watchSub = _feed.watchPosts(
      currentUid: _uid,
      onAdded: (item) {
        if (items.every((e) => e.id != item.id) && _matchesFilter(item)) {
          items.insert(0, item);
          items.refresh();
        }
      },
      onModified: (updated) {
        final i = items.indexWhere((e) => e.id == updated.id);
        if (i >= 0) {
          items[i] = updated;
          items.refresh();
        }
      },
      onRemoved: (id) {
        items.removeWhere((e) => e.id == id);
        items.refresh();
      },
    );

    _marketWatchSub = _market.watchMarket(
      onAdded: (item) {
        if (marketItems.every((e) => e.id != item.id) && isMarketMode) {
          marketItems.insert(0, item);
          marketItems.refresh();
        }
      },
      onModified: (updated) {
        final i = marketItems.indexWhere((e) => e.id == updated.id);
        if (i >= 0) {
          marketItems[i] = updated;
          marketItems.refresh();
        }
      },
      onRemoved: (id) {
        marketItems.removeWhere((e) => e.id == id);
        marketItems.refresh();
      },
    );
  }

  bool _matchesFilter(FeedItem item) {
    return switch (filter.value) {
      FeedFilter.all => true,
      FeedFilter.infos => item.type == FeedType.info,
      FeedFilter.annonces => item.type == FeedType.annonce,
      FeedFilter.population => item.type == FeedType.post,
      FeedFilter.venteAchat => false,
    };
  }

  void _onScroll() {
    if (!scrollController.hasClients || isLoadingMore.value || !hasMore.value) {
      return;
    }
    final pos = scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      loadMore();
    }
  }

  bool get isMarketMode => filter.value == FeedFilter.venteAchat;

  Future<void> refreshFeed() async {
    if (isLoading.value) return;
    isLoading.value = true;
    hasMore.value = true;
    try {
      if (isMarketMode) {
        final page = await _market.fetchPage(page: 0, reset: true);
        marketItems.assignAll(page);
        hasMore.value = page.length >= MarketService.pageSize;
      } else {
        final page = await _feed.fetchPage(
          filter: filter.value,
          reset: true,
          currentUid: _uid,
        );
        items.assignAll(page);
        hasMore.value = page.length >= FeedService.pageSize;
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      if (isMarketMode) {
        final page = await _market.fetchPage(
          page: (marketItems.length / MarketService.pageSize).ceil(),
        );
        if (page.isEmpty) {
          hasMore.value = false;
        } else {
          marketItems.addAll(page);
          hasMore.value = page.length >= MarketService.pageSize;
        }
      } else {
        final page = await _feed.fetchPage(
          filter: filter.value,
          currentUid: _uid,
        );
        if (page.isEmpty) {
          hasMore.value = false;
        } else {
          items.addAll(page);
          hasMore.value = page.length >= FeedService.pageSize;
        }
      }
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> setFilter(FeedFilter value) async {
    if (filter.value == value) return;
    filter.value = value;
    await refreshFeed();
    _startWatching();
  }

  Future<void> toggleLike(String postId) async {
    if (!await _ensureAuthenticated()) return;
    final uid = _auth.uid;
    final index = items.indexWhere((e) => e.id == postId);
    if (index < 0) return;
    final original = items[index];
    final liked = !original.likedByMe;
    items[index] = original.copyWith(
      likedByMe: liked,
      likesCount: (original.likesCount + (liked ? 1 : -1)).clamp(0, 999999),
    );
    items.refresh();
    try {
      await _feed.setLike(postId, uid, liked);
    } catch (_) {
      final revertIndex = items.indexWhere((e) => e.id == postId);
      if (revertIndex >= 0) {
        items[revertIndex] = original;
        items.refresh();
      }
    }
  }

  Future<void> addComment(
    String postId,
    String text, {
    String? parentCommentId,
    String? replyToName,
  }) async {
    if (!await _ensureAuthenticated()) return;
    final profile = _profiles.profile.value!;
    await _feed.addComment(
      postId: postId,
      authorUid: _auth.uid,
      authorName: profile.displayName,
      text: text,
      parentCommentId: parentCommentId,
      replyToName: replyToName,
    );
    final index = items.indexWhere((e) => e.id == postId);
    if (index >= 0) {
      final item = items[index];
      items[index] = item.copyWith(commentsCount: item.commentsCount + 1);
      items.refresh();
    }
  }

  Future<void> toggleCommentLike(
    String postId,
    String commentId,
    bool currentlyLiked,
  ) async {
    if (!await _ensureAuthenticated()) return;
    final liked = !currentlyLiked;
    await _feed.setCommentLike(postId, commentId, _auth.uid, liked);
  }

  void openPost(FeedItem item) {
    Get.toNamed(AppRoutes.feedPost, arguments: item.id);
  }

  void openMarketItem(MarketItem item) {
    Get.toNamed(AppRoutes.marketDetail, arguments: item.id);
  }

  Future<void> openCompose() async {
    if (!await _ensureAuthenticated()) return;

    final profile = _profiles.profile.value;
    if (profile != null && !profile.canPublish) {
      Get.defaultDialog(
        title: 'Compte en attente de validation',
        middleText: 'Les comptes structure doivent être validés par '
            'l’équipe de Foumbot Link avant de pouvoir publier des '
            'informations ou des annonces officielles. Vous serez '
            'prévenu·e dès que ce sera fait.',
        textConfirm: 'Compris',
        onConfirm: Get.back,
      );
      return;
    }

    final result = await Get.toNamed(AppRoutes.compose);
    if (result is FeedItem) {
      publishPost(result);
    }
  }

  void publishPost(FeedItem item) {
    items.insert(0, item);
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void toggleTheme() => _theme.toggleTheme();

  void openFeature(AppFeature feature) {
    if (feature.id == AppFeatureId.venteAchat) {
      Get.toNamed(AppRoutes.market);
      return;
    }
    Get.toNamed(AppRoutes.feature, arguments: feature);
  }

  void openNotifications() {
    unreadNotifications.value = 0;
    Get.toNamed(AppRoutes.feature, arguments: const AppFeature(
      id: AppFeatureId.notifications,
      title: 'Notifications',
      subtitle: 'Alertes et messages reçus',
      icon: Icons.notifications_outlined,
    ));
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
