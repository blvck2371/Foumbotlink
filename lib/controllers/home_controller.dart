import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../models/app_feature.dart';
import '../models/feed_item.dart';
import '../routes/app_routes.dart';
import '../services/feed_service.dart';
import '../theme/theme_controller.dart';

class HomeController extends GetxController {
  HomeController({FeedService? feedService})
      : _feed = feedService ?? FeedService();

  final FeedService _feed;
  final unreadNotifications = 3.obs;

  final items = <FeedItem>[].obs;
  final filter = FeedFilter.all.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;
  final feedTick = 0.obs;

  late final ScrollController scrollController;

  int _page = 0;

  FeedService get feedService => _feed;

  ThemeController get _theme => Get.find<ThemeController>();
  bool get isDarkMode => _theme.isDarkMode;
  List<AppFeature> get features => AppFeature.all;

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController()..addListener(_onScroll);
    refreshFeed();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.onClose();
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

  Future<void> refreshFeed() async {
    if (isLoading.value) return;
    isLoading.value = true;
    _page = 0;
    hasMore.value = true;
    try {
      final page = await _feed.fetchPage(page: 0, filter: filter.value);
      items.assignAll(page);
      _page = 1;
      hasMore.value = page.length >= FeedService.pageSize;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final page =
          await _feed.fetchPage(page: _page, filter: filter.value);
      if (page.isEmpty) {
        hasMore.value = false;
      } else {
        items.addAll(page);
        _page++;
        hasMore.value = page.length >= FeedService.pageSize;
      }
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> setFilter(FeedFilter value) async {
    if (filter.value == value) return;
    filter.value = value;
    await refreshFeed();
  }

  void toggleLike(String id) {
    final updated = _feed.toggleLike(id);
    if (updated == null) return;
    _replaceItem(updated);
  }

  void addComment(String id, String text, {String? parentCommentId}) {
    final updated = _feed.addComment(id, text, parentCommentId: parentCommentId);
    if (updated == null) return;
    _replaceItem(updated);
  }

  void toggleCommentLike(String postId, String commentId) {
    final updated = _feed.toggleCommentLike(postId, commentId);
    if (updated == null) return;
    _replaceItem(updated);
  }

  void _replaceItem(FeedItem updated) {
    final index = items.indexWhere((e) => e.id == updated.id);
    if (index >= 0) {
      items[index] = updated;
      items.refresh();
    }
    feedTick.value++;
  }

  void openPost(FeedItem item) {
    Get.toNamed(AppRoutes.feedPost, arguments: item.id);
  }

  void toggleTheme() => _theme.toggleTheme();

  void openFeature(AppFeature feature) {
    if (feature.id == AppFeatureId.notifications) {
      unreadNotifications.value = 0;
    }
    Get.toNamed(AppRoutes.feature, arguments: feature);
  }

  void openNotifications() {
    openFeature(AppFeature.byId(AppFeatureId.notifications));
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
