import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../models/market_item.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/market_service.dart';
import '../services/user_profile_service.dart';

class MarketController extends GetxController {
  final items = <MarketItem>[].obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  final selectedCategory = Rxn<MarketCategory>();
  final selectedType = Rxn<MarketListingType>();
  final searchQuery = ''.obs;

  late final ScrollController scrollController;
  final searchCtrl = TextEditingController();

  int _page = 0;

  MarketService get _market => Get.find<MarketService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  bool get isAuthenticated => _auth.isSignedIn && _profiles.hasProfile;

  Future<bool> _ensureAuthenticated() async {
    if (_auth.isSignedIn) await _profiles.waitUntilLoaded();
    if (isAuthenticated) return true;
    await Get.toNamed(AppRoutes.auth);
    return isAuthenticated;
  }

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController()..addListener(_onScroll);
    refreshListings();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    searchCtrl.dispose();
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

  Future<void> refreshListings() async {
    if (isLoading.value) return;
    isLoading.value = true;
    _page = 0;
    hasMore.value = true;
    try {
      final page = await _market.fetchPage(
        page: 0,
        category: selectedCategory.value,
        listingType: selectedType.value,
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
        reset: true,
      );
      items.assignAll(page);
      _page = 1;
      hasMore.value = page.length >= MarketService.pageSize;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final page = await _market.fetchPage(
        page: _page,
        category: selectedCategory.value,
        listingType: selectedType.value,
        query: searchQuery.value.isEmpty ? null : searchQuery.value,
      );
      if (page.isEmpty) {
        hasMore.value = false;
      } else {
        items.addAll(page);
        _page++;
        hasMore.value = page.length >= MarketService.pageSize;
      }
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> setCategory(MarketCategory? category) async {
    if (selectedCategory.value == category) {
      selectedCategory.value = null;
    } else {
      selectedCategory.value = category;
    }
    await refreshListings();
  }

  Future<void> setType(MarketListingType? type) async {
    if (selectedType.value == type) {
      selectedType.value = null;
    } else {
      selectedType.value = type;
    }
    await refreshListings();
  }

  Future<void> search(String query) async {
    searchQuery.value = query;
    await refreshListings();
  }

  void clearSearch() {
    searchCtrl.clear();
    search('');
  }

  void openListing(MarketItem item) {
    Get.toNamed(AppRoutes.marketDetail, arguments: item.id);
  }

  Future<void> openCreateListing() async {
    if (!await _ensureAuthenticated()) return;
    final result = await Get.toNamed(AppRoutes.marketCompose);
    if (result is MarketItem) {
      items.insert(0, result);
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
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
