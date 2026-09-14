import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/market_filters.dart';
import '../models/market_item.dart';
import '../models/market_text.dart';
import '../models/report.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/market_favorites_service.dart';
import '../services/market_service.dart';
import '../services/moderation_service.dart';
import '../services/saved_search_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/report_sheet.dart';

/// Ce que la grille montre. Trois listes bien distinctes plutôt qu'un
/// empilement de booléens : la grille publique, ce que j'ai publié, ce
/// que j'ai mis de côté.
enum MarketView { grille, mesAnnonces, favoris }

class MarketController extends GetxController {
  /// Annonces effectivement affichées (tranche visible de [_ordered]).
  final items = <MarketItem>[].obs;

  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  final filters = const MarketFilters().obs;
  final view = MarketView.grille.obs;

  /// Numéros déjà révélés dans cette session, par id d'annonce — pour ne
  /// pas relire le document à chaque appui sur « Appeler ».
  final revealedPhones = <String, String>{}.obs;

  late final ScrollController scrollController;
  final searchCtrl = TextEditingController();

  /// Fenêtre brute renvoyée par le serveur, avant filtres locaux et tri.
  final _window = <MarketItem>[];

  /// Fenêtre filtrée et triée — la liste de référence dont [items] est le
  /// début.
  final _ordered = <MarketItem>[];

  static const _pageSize = 20;
  int _visibleCount = _pageSize;

  /// Graine du mélange aléatoire. Stable pendant toute la navigation :
  /// c'est ce qui empêche une annonce de sauter d'une place à l'autre
  /// pendant qu'on fait défiler. Elle n'est retirée qu'à un
  /// rafraîchissement explicite — l'ordre change alors, et c'est
  /// justement l'intérêt : chaque visite met d'autres vendeurs devant.
  int _seed = DateTime.now().millisecondsSinceEpoch;

  MarketService get _market => Get.find<MarketService>();
  AuthService get _auth => Get.find<AuthService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  MarketFavoritesService get _favorites => Get.find<MarketFavoritesService>();
  SavedSearchService get _savedSearches => Get.find<SavedSearchService>();

  bool get isAuthenticated => _auth.isSignedIn && _profiles.hasProfile;
  String get _uid => _auth.isSignedIn ? _auth.uid : '';

  /// L'annonce appartient à l'utilisateur courant (masque les actions
  /// d'achat, affiche les actions de gestion).
  bool isMine(MarketItem item) =>
      _auth.isSignedIn && item.sellerUid == _auth.uid;

  bool isFavorite(String itemId) => _favorites.isFavorite(itemId);

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
    _watchFavorites();
    // Le marché s'ouvre le plus souvent sans être connecté : on se
    // connecte en cours de route, au premier favori ou au premier
    // contact. Sans cette écoute, les cœurs resteraient vides jusqu'au
    // prochain lancement de l'app.
    ever(_auth.firebaseUser, (_) {
      _watchFavorites();
      items.refresh();
    });
    // Cache local d'abord au premier affichage : la grille apparaît tout
    // de suite plutôt qu'après un aller-retour réseau.
    refreshListings(preferCache: true);
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
    if (!scrollController.hasClients || !hasMore.value) return;
    final pos = scrollController.position;
    // Marge large : on découvre la tranche suivante ~2 rangées avant
    // d'atteindre le bas, pour que le défilement reste continu.
    if (pos.pixels >= pos.maxScrollExtent - 600) loadMore();
  }

  // ---------------------------------------------------------------------
  // Chargement
  // ---------------------------------------------------------------------

  /// Recharge la fenêtre depuis le serveur.
  ///
  /// [preferCache] n'est vrai qu'au tout premier chargement — un
  /// rafraîchissement explicite doit toujours interroger le serveur, et
  /// retire aussi la graine du mélange pour rebattre les cartes.
  Future<void> refreshListings({bool preferCache = false}) async {
    if (isLoading.value) return;
    isLoading.value = true;
    if (!preferCache) _seed = DateTime.now().millisecondsSinceEpoch;
    try {
      final window = switch (view.value) {
        MarketView.favoris => await _loadFavorites(),
        MarketView.mesAnnonces => await _market.fetchWindow(
          filters: filters.value,
          sellerUid: _uid,
          preferCache: preferCache,
        ),
        MarketView.grille => await _market.fetchWindow(
          filters: filters.value,
          preferCache: preferCache,
        ),
      };
      _window
        ..clear()
        ..addAll(window.where((e) => !_moderation.isBlocked(e.sellerUid)));
      _visibleCount = _pageSize;
      _applyLocal();
    } finally {
      isLoading.value = false;
    }
  }

  void _watchFavorites() {
    if (_auth.isSignedIn) {
      _favorites.watch(uid: _uid, onChanged: () => items.refresh());
    } else {
      _favorites.stop();
    }
  }

  Future<List<MarketItem>> _loadFavorites() async {
    if (!_auth.isSignedIn) return const [];
    return _favorites.fetchFavorites(uid: _uid, parse: _market.parseDoc);
  }

  /// Applique les filtres locaux (prix, état, lieu, et catégorie/type
  /// dans les vues qui ne les passent pas au serveur) puis le tri, et
  /// recalcule la tranche visible.
  ///
  /// Tout se fait en mémoire sur la fenêtre déjà chargée : changer de tri
  /// ou de fourchette de prix est instantané et ne coûte aucune lecture.
  void _applyLocal() {
    final f = filters.value;
    final localCategoryFilter = view.value != MarketView.grille;

    var list = _window.where((item) {
      if (!f.matches(item)) return false;
      if (localCategoryFilter) {
        if (f.category != null && item.category != f.category) return false;
        if (f.listingType != null && item.listingType != f.listingType) {
          return false;
        }
        final tokens = searchTokens(f.query);
        if (tokens.isNotEmpty &&
            !tokens.every((t) => item.keywords.contains(t))) {
          return false;
        }
      }
      return true;
    }).toList();

    switch (f.sort) {
      case MarketSort.aleatoire:
        list.shuffle(Random(_seed));
      case MarketSort.recent:
        list.sort((a, b) => b.bumpedAt.compareTo(a.bumpedAt));
      case MarketSort.prixCroissant:
        list = _byPrice(list, ascending: true);
      case MarketSort.prixDecroissant:
        list = _byPrice(list, ascending: false);
    }

    _ordered
      ..clear()
      ..addAll(list);
    _publishVisible();
  }

  /// Tri par prix, les annonces sans montant comparable (« prix à
  /// discuter ») rejetées en fin de liste plutôt que traitées comme
  /// gratuites — sinon elles trusteraient la tête du tri croissant.
  List<MarketItem> _byPrice(List<MarketItem> list, {required bool ascending}) {
    final withPrice = list.where((e) => !e.priceOnRequest).toList()
      ..sort(
        (a, b) =>
            ascending ? a.price.compareTo(b.price) : b.price.compareTo(a.price),
      );
    final without = list.where((e) => e.priceOnRequest).toList();
    return [...withPrice, ...without];
  }

  void _publishVisible() {
    final end = _visibleCount.clamp(0, _ordered.length);
    items.assignAll(_ordered.take(end));
    hasMore.value = end < _ordered.length;
  }

  /// Découvre la tranche suivante. Aucune requête : la fenêtre est déjà
  /// en mémoire, la pagination est purement locale.
  void loadMore() {
    if (!hasMore.value || isLoadingMore.value) return;
    isLoadingMore.value = true;
    _visibleCount += _pageSize;
    _publishVisible();
    isLoadingMore.value = false;
  }

  // ---------------------------------------------------------------------
  // Filtres et tri
  // ---------------------------------------------------------------------

  /// Applique un nouveau jeu de filtres. On ne repart au serveur que si
  /// la requête elle-même change (catégorie, type, recherche) ; un
  /// changement de tri ou de fourchette de prix se règle en mémoire.
  Future<void> applyFilters(MarketFilters next) async {
    final previous = filters.value;
    if (next == previous) return;
    filters.value = next;

    // « Mes annonces » et « Mes favoris » sont chargés en entier : leur
    // requête serveur ne dépend d'aucun filtre, tout s'y applique en
    // mémoire. Seule la grille publique passe catégorie, type et
    // recherche au serveur, et doit donc recharger quand ils changent.
    final needsRefetch =
        view.value == MarketView.grille && !next.sameQueryAs(previous);
    if (!needsRefetch) {
      _visibleCount = _pageSize;
      _applyLocal();
      return;
    }
    await refreshListings();
  }

  Future<void> setCategory(MarketCategory? category) => applyFilters(
    filters.value.category == category
        ? filters.value.copyWith(clearCategory: true)
        : filters.value.copyWith(
            category: category,
            clearCategory: category == null,
          ),
  );

  Future<void> setType(MarketListingType? type) => applyFilters(
    filters.value.listingType == type
        ? filters.value.copyWith(clearListingType: true)
        : filters.value.copyWith(
            listingType: type,
            clearListingType: type == null,
          ),
  );

  Future<void> setSort(MarketSort sort) =>
      applyFilters(filters.value.copyWith(sort: sort));

  Future<void> search(String query) =>
      applyFilters(filters.value.copyWith(query: query));

  void clearSearch() {
    searchCtrl.clear();
    search('');
  }

  Future<void> clearFilters() async {
    searchCtrl.clear();
    await applyFilters(filters.value.cleared().copyWith(query: ''));
  }

  /// Rebat les cartes sans recharger : nouvelle graine, nouvel ordre.
  void reshuffle() {
    _seed = DateTime.now().millisecondsSinceEpoch;
    if (filters.value.sort != MarketSort.aleatoire) {
      filters.value = filters.value.copyWith(sort: MarketSort.aleatoire);
    }
    _visibleCount = _pageSize;
    _applyLocal();
  }

  // ---------------------------------------------------------------------
  // Vues
  // ---------------------------------------------------------------------

  Future<void> setView(MarketView next) async {
    if (view.value == next) return;
    if (next != MarketView.grille && !await _ensureAuthenticated()) return;
    view.value = next;
    await refreshListings();
  }

  Future<void> toggleOnlyMine() => setView(
    view.value == MarketView.mesAnnonces
        ? MarketView.grille
        : MarketView.mesAnnonces,
  );

  Future<void> toggleFavoritesView() => setView(
    view.value == MarketView.favoris ? MarketView.grille : MarketView.favoris,
  );

  // ---------------------------------------------------------------------
  // Favoris
  // ---------------------------------------------------------------------

  Future<void> toggleFavorite(MarketItem item) async {
    if (!await _ensureAuthenticated()) return;
    try {
      final added = await _favorites.toggle(uid: _uid, item: item);
      items.refresh();
      if (view.value == MarketView.favoris && !added) {
        _window.removeWhere((e) => e.id == item.id);
        _applyLocal();
      }
    } on Object catch (e) {
      _toast('Action impossible : $e');
    }
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  void openListing(MarketItem item) {
    Get.toNamed(AppRoutes.marketDetail, arguments: item.id);
  }

  Future<void> openCreateListing() async {
    if (!await _ensureAuthenticated()) return;

    // Garde-fou anti-inondation, vérifié avant d'ouvrir le formulaire —
    // le refus qui fait foi est côté serveur, mais autant ne pas laisser
    // quelqu'un saisir une annonce qui sera supprimée à l'arrivée.
    final today = await _market.countTodayListings(_uid);
    if (today >= kDailyListingLimit) {
      _toast(
        'Vous avez publié $kDailyListingLimit annonces aujourd’hui. '
        'Revenez demain.',
      );
      return;
    }

    final result = await Get.toNamed(AppRoutes.marketCompose);
    if (result is MarketItem) {
      _window.insert(0, result);
      _applyLocal();
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  /// Ouvre le formulaire en modification. Renvoie l'annonce à jour, que
  /// l'écran de détail utilise pour se rafraîchir.
  Future<MarketItem?> openEditListing(MarketItem item) async {
    if (!isMine(item)) return null;
    final result = await Get.toNamed(AppRoutes.marketCompose, arguments: item);
    if (result is MarketItem) {
      _replaceInList(result);
      return result;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Contacter le vendeur
  // ---------------------------------------------------------------------

  /// Révèle le numéro du vendeur — nécessite un compte, et laisse une
  /// trace de contact (qui ouvre le droit de laisser un avis, et alimente
  /// le compteur affiché au vendeur).
  ///
  /// Le numéro n'est pas dans le document public de l'annonce : il est lu
  /// ici, à la demande. C'est ce qui empêche d'aspirer en une requête les
  /// numéros de toute la commune.
  Future<String?> revealPhone(MarketItem item) async {
    final cached = revealedPhones[item.id];
    if (cached != null) return cached;
    if (!await _ensureAuthenticated()) return null;

    final phone = await _market.fetchPhone(item);
    if (phone == null || phone.isEmpty) {
      _toast('Ce vendeur n’a pas laissé de numéro. Écrivez-lui un message.');
      return null;
    }
    revealedPhones[item.id] = phone;
    await _market.recordContact(item: item, buyerUid: _uid);
    return phone;
  }

  /// Normalise un numéro pour un lien `tel:` : garde le `+` de tête, retire
  /// tout le reste (espaces, tirets, points).
  String _dialable(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    return s;
  }

  /// Numéro international sans `+` ni `0`, pour `wa.me`. Un numéro
  /// camerounais local à 9 chiffres (6XXXXXXXX) est préfixé 237.
  String _whatsappNumber(String raw) {
    var s = _dialable(raw);
    if (s.startsWith('+')) return s.substring(1);
    if (s.length == 9 && s.startsWith('6')) return '237$s';
    return s;
  }

  Future<void> _launch(Uri uri, {LaunchMode? mode}) async {
    try {
      final ok = await launchUrl(uri, mode: mode ?? LaunchMode.platformDefault);
      if (!ok) _toast('Aucune application pour ouvrir « ${uri.scheme} »');
    } on Object catch (e) {
      _toast('Action impossible : $e');
    }
  }

  Future<void> callSeller(MarketItem item) async {
    final phone = _dialable(await revealPhone(item) ?? '');
    if (phone.isEmpty) return;
    await _launch(Uri(scheme: 'tel', path: phone));
  }

  Future<void> smsSeller(MarketItem item) async {
    final phone = _dialable(await revealPhone(item) ?? '');
    if (phone.isEmpty) return;
    await _launch(
      Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': _availabilityText(item)},
      ),
    );
  }

  Future<void> whatsappSeller(MarketItem item) async {
    final number = _whatsappNumber(await revealPhone(item) ?? '');
    if (number.isEmpty) return;
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(_availabilityText(item))}',
    );
    await _launch(uri, mode: LaunchMode.externalApplication);
  }

  String _availabilityText(MarketItem item) =>
      'Bonjour, votre annonce « ${item.title} » (${item.priceLabel}) '
      'est-elle toujours disponible ?';

  // ---------------------------------------------------------------------
  // Discuter dans l'app / proposer un prix
  // ---------------------------------------------------------------------

  Future<void> chatWithSeller(MarketItem item, {String? prefill}) async {
    if (!await _ensureAuthenticated()) return;
    if (item.sellerUid == _auth.uid) return;
    await _market.recordContact(item: item, buyerUid: _uid);
    Get.toNamed(
      AppRoutes.chat,
      arguments: {
        'otherUid': item.sellerUid,
        'prefill': prefill ?? _availabilityText(item),
      },
    );
  }

  /// Ouvre la discussion avec un message de proposition pré-rempli — le
  /// vendeur répond dans le fil pour accepter / négocier.
  Future<void> offerSeller(MarketItem item, int amount) async {
    if (amount <= 0) return;
    await chatWithSeller(
      item,
      prefill:
          '💰 Proposition : ${formatAmount(amount)} FCFA\n'
          'pour « ${item.title} » (affiché à ${item.priceLabel}).',
    );
  }

  // ---------------------------------------------------------------------
  // Alertes (recherches enregistrées)
  // ---------------------------------------------------------------------

  /// Enregistre les critères courants comme alerte : à chaque nouvelle
  /// annonce correspondante, une notification part.
  Future<void> saveCurrentSearch() async {
    if (!await _ensureAuthenticated()) return;
    try {
      final saved = await _savedSearches.create(
        uid: _uid,
        filters: filters.value,
      );
      _toast('Alerte créée : ${saved.label}');
    } on Object catch (e) {
      _toast('Alerte impossible : $e');
    }
  }

  void openSavedSearches() => Get.toNamed(AppRoutes.marketAlerts);

  // ---------------------------------------------------------------------
  // Partager / signaler
  // ---------------------------------------------------------------------

  Future<void> shareListing(MarketItem item) async {
    await SharePlus.instance.share(
      ShareParams(text: item.shareText, subject: item.title),
    );
  }

  Future<void> reportListing(MarketItem item) async {
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return;
    }
    final choice = await showReportSheet(targetLabel: 'cette annonce');
    if (choice == null) return;
    try {
      await _moderation.report(
        ContentReport(
          targetType: ReportTargetType.marketItem,
          targetId: item.id,
          targetPath: 'market/${item.id}',
          targetOwnerUid: item.sellerUid,
          reporterUid: _auth.uid,
          reason: choice.reason,
          details: choice.details,
          excerpt: item.title,
        ),
      );
      _toast('Signalement envoyé. Merci.');
    } on Object catch (e) {
      _toast('Signalement impossible : $e');
    }
  }

  // ---------------------------------------------------------------------
  // Gérer son annonce
  // ---------------------------------------------------------------------

  /// Marque vendu / remet en vente. Optimiste, avec retour arrière si
  /// Firestore refuse. Renvoie l'annonce à jour (ou l'originale en cas
  /// d'échec) pour que l'écran de détail se rafraîchisse.
  ///
  /// Une annonce vendue quitte la grille publique — elle ne reste
  /// visible que pour son auteur, dans « Mes annonces ».
  Future<MarketItem> toggleSold(MarketItem item) async {
    final nowSold = !item.sold;
    var updated = item.copyWith(
      sold: nowSold,
      soldAt: nowSold ? DateTime.now() : null,
    );
    _replaceInList(updated);
    try {
      final expiresAt = await _market.setSold(id: item.id, sold: nowSold);
      if (!nowSold && expiresAt != null) {
        updated = updated.copyWith(
          bumpedAt: DateTime.now(),
          expiresAt: expiresAt,
        );
        _replaceInList(updated);
      }
      if (nowSold && view.value == MarketView.grille) {
        _window.removeWhere((e) => e.id == item.id);
        _applyLocal();
      }
      _toast(
        nowSold
            ? 'Annonce marquée vendue — elle n’apparaît plus dans le marché'
            : 'Annonce remise en vente pour ${kListingLifetime.inDays} jours',
      );
      return updated;
    } on Object catch (e) {
      _replaceInList(item);
      _toast('Action impossible : $e');
      return item;
    }
  }

  /// Relance une annonce expirée ou sur le point de l'être : elle repart
  /// pour 60 jours et remonte dans la grille. Gratuit, autant de fois
  /// qu'on veut — c'est la seule « remontée » possible ici, et elle ne se
  /// paie pas.
  Future<MarketItem> renewListing(MarketItem item) async {
    try {
      final (bumpedAt, expiresAt) = await _market.renewListing(item.id);
      final updated = item.copyWith(bumpedAt: bumpedAt, expiresAt: expiresAt);
      _replaceInList(updated);
      _toast('Annonce relancée pour ${kListingLifetime.inDays} jours');
      return updated;
    } on Object catch (e) {
      _toast('Relance impossible : $e');
      return item;
    }
  }

  /// Demande confirmation puis supprime. Renvoie `true` si l'annonce a bien
  /// été supprimée (l'écran de détail doit alors se fermer).
  Future<bool> confirmDelete(MarketItem item) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Supprimer l’annonce ?'),
        content: const Text(
          'Cette action est définitive. L’annonce et ses photos seront '
          'retirées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _market.deleteListing(item);
      _window.removeWhere((e) => e.id == item.id);
      _applyLocal();
      _toast('Annonce supprimée');
      return true;
    } on Object catch (e) {
      _toast('Suppression impossible : $e');
      return false;
    }
  }

  void _replaceInList(MarketItem item) {
    final i = _window.indexWhere((e) => e.id == item.id);
    if (i >= 0) _window[i] = item;
    final j = _ordered.indexWhere((e) => e.id == item.id);
    if (j >= 0) _ordered[j] = item;
    final k = items.indexWhere((e) => e.id == item.id);
    if (k >= 0) items[k] = item;
  }

  void _toast(String message) {
    Get.closeAllSnackbars();
    Get.snackbar(
      'Marché',
      message,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
      snackPosition: SnackPosition.BOTTOM,
    );
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
