import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../models/demarche.dart';
import '../models/feed_item.dart';
import '../models/live_session.dart';
import '../models/market_item.dart';
import '../models/search_text.dart';
import '../models/user_profile.dart';
import '../routes/app_routes.dart';
import '../services/feed_memory.dart';
import '../services/search_service.dart';
import '../widgets/live_ring.dart';
import 'home_controller.dart';

/// Onglets des résultats, dans l'ordre affiché.
enum SearchTab { top, accounts, posts, listings, demarches, lives }

/// Recherche globale façon TikTok : suggestions dès les premières
/// lettres, résultats par familles, historique, comptes populaires et
/// lives en cours quand la saisie est vide.
class AppSearchController extends GetxController {
  /// Attente après la dernière frappe avant d'interroger le serveur :
  /// assez courte pour paraître instantanée, assez longue pour ne pas
  /// lancer une requête par lettre.
  static const _debounce = Duration(milliseconds: 250);

  final textController = TextEditingController();
  final focusNode = FocusNode();

  final query = ''.obs;
  final results = SearchResults.empty.obs;
  final isSearching = false.obs;
  final tab = SearchTab.top.obs;
  final recent = <String>[].obs;
  final popular = <UserProfile>[].obs;

  Timer? _timer;

  /// Numéro de la requête en cours : une réponse plus lente qu'une
  /// suivante ne doit jamais écraser des résultats plus récents.
  int _request = 0;

  SearchService get _search => Get.find<SearchService>();

  bool get hasQuery => searchQueryTokens(query.value).isNotEmpty;

  /// Lives en cours (suggestions sans saisie). Lu dans un `Obx` : suit le
  /// temps réel.
  List<LiveSession> get currentLives => _search.currentLives;

  Set<String> get _following => Get.isRegistered<HomeController>()
      ? Get.find<HomeController>().followingUids
      : const {};

  @override
  void onInit() {
    super.onInit();
    textController.addListener(_onText);
    unawaited(_loadSuggestions());
  }

  Future<void> _loadSuggestions() async {
    recent.assignAll(await _search.recentSearches());
    popular.assignAll(await _search.popularAccounts());
  }

  void _onText() {
    final text = textController.text;
    if (text == query.value) return;
    query.value = text;
    _timer?.cancel();
    if (!hasQuery) {
      _request++;
      isSearching.value = false;
      results.value = SearchResults.empty;
      return;
    }
    isSearching.value = true;
    _timer = Timer(_debounce, () => _run(text));
  }

  Future<void> _run(String text) async {
    final id = ++_request;
    isSearching.value = true;
    try {
      final r = await _search.search(text, following: _following);
      if (id != _request) return;
      results.value = r;
    } finally {
      if (id == _request) isSearching.value = false;
    }
  }

  /// Validation au clavier : on garde la recherche dans l'historique.
  void submit([String? value]) {
    final text = (value ?? textController.text).trim();
    if (text.isEmpty) return;
    unawaited(_remember(text));
    focusNode.unfocus();
  }

  /// Relance une recherche de l'historique.
  void useRecent(String text) {
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    submit(text);
  }

  void clear() {
    textController.clear();
    tab.value = SearchTab.top;
    focusNode.requestFocus();
  }

  Future<void> _remember(String text) async =>
      recent.assignAll(await _search.remember(text));

  Future<void> forget(String text) async =>
      recent.assignAll(await _search.forget(text));

  Future<void> clearRecent() async {
    await _search.clearRecent();
    recent.clear();
  }

  /// Ouvrir un résultat enregistre la recherche, comme sur TikTok.
  void _rememberCurrent() {
    if (hasQuery) unawaited(_remember(query.value.trim()));
  }

  void openUser(UserProfile user) {
    _rememberCurrent();
    FeedMemory.instance.bump(user.uid, FeedMemory.profileVisit);
    Get.toNamed(
      AppRoutes.userProfile,
      arguments: user.uid,
      preventDuplicates: false,
    );
  }

  void openPost(FeedItem post) {
    _rememberCurrent();
    FeedMemory.instance.bump(post.authorUid, FeedMemory.open);
    Get.toNamed(AppRoutes.feedPost, arguments: post.id);
  }

  void openListing(MarketItem item) {
    _rememberCurrent();
    Get.toNamed(AppRoutes.marketDetail, arguments: item.id);
  }

  void openDemarche(Demarche d) {
    _rememberCurrent();
    Get.toNamed(AppRoutes.demarcheDetail, arguments: d);
  }

  void openLive(LiveSession live) {
    _rememberCurrent();
    unawaited(watchLive(live.id));
  }

  @override
  void onClose() {
    _timer?.cancel();
    textController.dispose();
    focusNode.dispose();
    super.onClose();
  }
}
