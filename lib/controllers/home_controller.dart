import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_feature.dart';
import '../models/feed_item.dart';
import '../models/market_item.dart';
import '../models/report.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/feed_memory.dart';
import '../services/feed_ranker.dart';
import '../services/feed_service.dart';
import '../services/follow_service.dart';
import '../services/live_service.dart';
import '../services/market_service.dart';
import '../services/moderation_service.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/user_profile_service.dart';
import '../theme/theme_controller.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/report_sheet.dart';
import '../services/profile_gate.dart';

class HomeController extends GetxController {
  final unreadNotifications = 0.obs;

  final items = <FeedItem>[].obs;
  final marketItems = <MarketItem>[].obs;
  final filter = FeedFilter.all.obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasMore = true.obs;

  /// Graine de la rotation du fil, retirée à chaque rafraîchissement.
  ///
  /// Le fil était strictement chronologique : sans nouvelle publication,
  /// il présentait exactement la même chose, dans le même ordre, à chaque
  /// ouverture. Cette graine fait tourner les publications qui ne sont
  /// plus fraîches. Elle reste stable pendant toute la consultation, pour
  /// que l'ordre ne bouge pas sous les doigts en cours de défilement.
  int _feedSeed = DateTime.now().millisecondsSinceEpoch;

  /// Rang de la page en cours — combiné à [_feedSeed] pour que chaque
  /// page ait son propre tirage, sans jamais rejouer celui d'une page
  /// déjà affichée.
  int _pageIndex = 0;

  /// Nombre de pages consécutives que `loadMore` accepte de traverser
  /// quand elles n'apportent rien de visible. Sans cette relance, une page
  /// entièrement absorbée par le filtrage ou le dédoublonnage arrêtait le
  /// défilement infini pour de bon.
  static const _maxEmptyPageChases = 5;

  late final ScrollController scrollController;
  Future<void>? _firstLoad;
  Worker? _authWorker;

  /// uid avec lequel le fil courant a été chargé et est écouté.
  String? _boundUid;

  /// Un « j'aime » en vol par post, et l'état visé si l'utilisateur
  /// continue d'appuyer pendant l'écriture.
  final _likeInFlight = <String>{};
  final _desiredLike = <String, bool>{};

  /// Les posts aimés par la session. Depuis que les likes vivent dans
  /// `posts/{id}/likes/{uid}`, le document du post ne dit plus si *moi* je
  /// l'ai aimé : cet ensemble, chargé une fois depuis le miroir personnel,
  /// répond pour tout le fil sans une lecture par post.
  final _myLikes = <String>{};

  /// Les posts mis de côté par la session — observable, à la différence de
  /// [_myLikes] : `likedByMe` voyage dans le [FeedItem] et se répercute via
  /// `items.refresh()`, alors que l'état « enregistré » ne vit que dans cet
  /// ensemble et doit donc pouvoir déclencher un rebuild par lui-même (le
  /// signet de chaque carte l'écoute dans son propre `Obx`).
  final savedPostIds = <String>{}.obs;

  /// Les comptes suivis par la session, rechargés à chaque rafraîchissement
  /// du fil : leurs publications du jour ouvrent la liste (voir
  /// [FeedService.fetchFollowingHighlights]).
  final _followingUids = <String>{};

  /// Toutes les publications candidates chargées pour cette visite —
  /// affichées ou en attente. Le classement ([FeedRanker]) puise ici.
  final _pool = <String, FeedItem>{};

  /// Publications classées, pas encore affichées : le défilement infini
  /// les sert par lots de [_batch]. Quand il en reste peu, une page de plus
  /// est chargée et reclassée avec elles.
  var _queue = <FeedItem>[];

  /// Taille d'un lot servi au défilement.
  static const _batch = 10;

  /// Candidates demandées au premier chargement, puis à chaque page : le
  /// classement a besoin de matière pour choisir, pas seulement des 8
  /// dernières publications.
  static const _firstPoolSize = 60;
  static const _nextPoolSize = 30;

  /// Reste-t-il des pages côté serveur ?
  bool _morePages = true;

  /// Début de la visite : une publication plus récente est une vraie
  /// nouveauté, annoncée par la pastille « Nouvelles publications ».
  DateTime _visitStart = DateTime.now();

  /// Nouvelles publications arrivées pendant la lecture. Facebook ne les
  /// glisse pas sous le doigt : une pastille propose de les afficher.
  final pendingNew = <FeedItem>[].obs;

  /// Publications plus anciennes arrivées après coup (fil servi par le
  /// cache, puis le serveur complète) : regroupées et classées ensemble.
  final _lateArrivals = <FeedItem>[];
  Timer? _lateTimer;

  /// Publications sur lesquelles on s'est attardé pendant cette visite.
  final _dwelled = <String>{};

  FeedMemory get _memory => FeedMemory.instance;

  /// Comptes suivis par la session — la recherche les fait remonter.
  Set<String> get followingUids => Set.unmodifiable(_followingUids);
  StreamSubscription? _watchSub;
  StreamSubscription? _marketWatchSub;
  StreamSubscription? _notificationsSub;
  Workers? _blockedSub;

  FeedService get _feed => Get.find<FeedService>();
  MarketService get _market => Get.find<MarketService>();
  ThemeController get _theme => Get.find<ThemeController>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  FollowService get _follow => Get.find<FollowService>();
  NotificationService get _notifs => Get.find<NotificationService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  bool get isDarkMode => _theme.isDarkMode;
  List<AppFeature> get features => AppFeature.all;

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  bool get isAuthenticated => _auth.isSignedIn && _profiles.hasProfile;

  Future<bool> _ensureAuthenticated() async {
    if (_auth.isSignedIn) await _profiles.waitUntilLoaded();
    if (isAuthenticated) return true;
    // Connexion si besoin, puis profil si le compte n'en a pas encore.
    await ProfileGate.ensure(reason: 'Pour participer');
    // `onInit` ne branche notifications et liste de blocage que si la
    // session existait déjà au lancement : après une connexion depuis le
    // fil, il faut les brancher ici, sans quoi un blocage resterait sans
    // effet jusqu'au prochain démarrage.
    if (isAuthenticated && _blockedSub == null) {
      _watchNotifications();
      _watchBlocked();
    }
    return isAuthenticated;
  }

  Future<void> signOut() async {
    // Le ménage de fin de session est du « meilleur effort », et surtout
    // il ne doit jamais retenir la déconnexion elle-même : ce sont des
    // écritures Firestore, or une écriture Firestore ne rend la main
    // qu'une fois acquittée par le serveur — hors ligne ou sur un réseau
    // qui traîne, elle n'aboutit tout simplement jamais. Attendues en
    // série comme avant, elles laissaient `_auth.signOut()` hors
    // d'atteinte : le bouton « Se déconnecter » paraissait mort.
    await _endSessionCleanup();
    await _auth.signOut();
    // Le tiroir est déjà refermé quand on arrive ici : sans un mot, la
    // déconnexion ne se voit nulle part depuis le fil (public, donc
    // inchangé), et on la croit ratée.
    Get.snackbar(
      'Déconnecté',
      'Vous consultez maintenant Foumbot Link sans compte.',
      duration: const Duration(seconds: 3),
    );
  }

  /// Politique de confidentialité, publiée sur Firebase Hosting (dossier
  /// `public/`). Le même lien figure sur la fiche Play Store.
  static final privacyPolicyUrl = Uri.parse(
    'https://foumbotlink.web.app/confidentialite',
  );

  Future<void> openPrivacyPolicy() async {
    final ok = await launchUrl(
      privacyPolicyUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      Get.snackbar('Lien indisponible', privacyPolicyUrl.toString());
    }
  }

  /// Suppression définitive du compte — exigence du Play Store.
  ///
  /// Tout le travail se fait côté serveur (`deleteAccount`, Admin SDK) :
  /// le client n'a pas le droit d'effacer ce qu'il a publié chez les
  /// autres (commentaires, liens d'abonnement), et une suppression
  /// interrompue doit pouvoir être reprise.
  final isDeletingAccount = false.obs;

  Future<void> deleteAccount() async {
    if (isDeletingAccount.value) return;
    final confirmed = await confirmAction(
      title: 'Supprimer votre compte ?',
      message:
          'Votre profil, vos publications, commentaires, statuts, '
          'annonces et abonnements seront effacés définitivement. Les '
          'messages déjà envoyés restent chez leurs destinataires, et les '
          'dossiers déposés auprès d’une structure restent dans ses '
          'registres.\n\nCette action est irréversible.',
      confirmLabel: 'Supprimer définitivement',
    );
    if (!confirmed) return;

    isDeletingAccount.value = true;
    try {
      await _endSessionCleanup();
      await FirebaseFunctions.instance
          .httpsCallable(
            'deleteAccount',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call<Map<String, dynamic>>();
      await _auth.signOut();
      Get.snackbar(
        'Compte supprimé',
        'Vos données ont été effacées. Merci d’avoir utilisé Foumbot Link.',
        duration: const Duration(seconds: 4),
      );
    } on Object catch (e) {
      developer.log('deleteAccount', name: 'HomeController', error: e);
      Get.snackbar(
        'Suppression interrompue',
        'Vérifiez votre connexion et réessayez : la suppression reprendra '
            'là où elle s’est arrêtée.',
        duration: const Duration(seconds: 5),
      );
    } finally {
      isDeletingAccount.value = false;
    }
  }

  /// Présence et token FCM retirés avant que l'uid disparaisse, sous
  /// délai maximal.
  ///
  /// Si le délai expire, on part quand même : un token FCM qui survit à la
  /// déconnexion est bien moins grave qu'une session dont on ne peut plus
  /// sortir — et `deleteToken()` l'invalide de toute façon côté appareil.
  Future<void> _endSessionCleanup() async {
    try {
      await Future.wait([
        Get.find<PresenceService>().goOffline(),
        Get.find<PushService>().unregisterToken(),
      ]).timeout(const Duration(seconds: 3));
    } on Object catch (e) {
      developer.log('signOut cleanup', name: 'HomeController', error: e);
    }
  }

  @override
  void onInit() {
    super.onInit();
    scrollController = ScrollController()..addListener(_onScroll);
    _firstLoad = _initialLoad();
    // `authStateChanges()` est asynchrone : au démarrage à froid, le fil est
    // chargé et écouté avant que l'uid de la session restaurée soit connu.
    // Sans ce recalage, tous les posts restent marqués « pas encore aimés »
    // alors que le serveur sait le contraire.
    _authWorker = ever<Object?>(_auth.firebaseUser, (_) => _onAuthChanged());
    if (_auth.isSignedIn) {
      _watchNotifications();
      _watchBlocked();
      _notifs.checkAppUpdate(_auth.uid);
    }
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    _watchSub?.cancel();
    _marketWatchSub?.cancel();
    _notificationsSub?.cancel();
    _blockedSub?.dispose();
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.onClose();
  }

  void _watchNotifications() {
    _notificationsSub?.cancel();
    _notificationsSub = _notifs.watch(
      uid: _auth.uid,
      onData: (list) {
        unreadNotifications.value = list.where((n) => !n.read).length;
      },
    );
  }

  void _watchBlocked() {
    _blockedSub?.dispose();
    _blockedSub = _moderation.watchHidden((hidden) {
      // Un blocage — dans un sens comme dans l'autre — doit retirer
      // immédiatement les publications déjà affichées, pas seulement
      // celles chargées ensuite.
      final before = items.length;
      items.removeWhere((e) => hidden.contains(e.authorUid));
      if (items.length != before) items.refresh();
      // Même règle sous « Vente & Achat » : ses annonces disparaissent
      // aussi de la grille du fil.
      final marketBefore = marketItems.length;
      marketItems.removeWhere((e) => hidden.contains(e.sellerUid));
      if (marketItems.length != marketBefore) marketItems.refresh();
    });
  }

  /// Un contenu d'un compte bloqué ne doit jamais atteindre la liste —
  /// filtré à chaque entrée (page, temps réel) plutôt qu'à l'affichage.
  bool _isVisible(FeedItem item) => !_moderation.hides(item.authorUid);

  /// Pendant de [_isVisible] pour les annonces — même règle, autre champ
  /// d'auteur. `MarketController` filtre déjà sa propre grille ainsi ; le
  /// fil doit s'aligner, sinon un compte bloqué reste visible dès qu'on
  /// bascule sur « Vente & Achat ».
  bool _isListingVisible(MarketItem item) => !_moderation.hides(item.sellerUid);

  /// Recale le badge « certifié » des cartes du fil sur le profil de leurs
  /// auteurs.
  ///
  /// `authorVerified` est dénormalisé sur le post au moment de la
  /// publication : un compte certifié plus tard n'aurait jamais de badge
  /// sur ses anciennes publications. On relit donc `users/{uid}.verified`
  /// (groupé et mis en cache par [UserProfileService]) et on ne touche aux
  /// cartes que si la valeur diffère vraiment.
  Future<void> _syncVerifiedBadges() async {
    final uids = items.map((e) => e.authorUid).toSet();
    if (uids.isEmpty) return;
    final verified = await _profiles.verifiedFor(uids);
    if (verified.isEmpty) return;
    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final actual = verified[item.authorUid];
      if (actual == null || actual == item.authorVerified) continue;
      items[i] = item.copyWith(authorVerified: actual);
      changed = true;
    }
    if (changed) items.refresh();
  }

  Future<void> _initialLoad() async {
    // Premier affichage servi par le cache local quand il est chaud : le
    // fil apparaît immédiatement au lieu d'attendre un aller-retour
    // réseau, et l'écoute temps réel ci-dessous le recale dès que le
    // serveur répond.
    _boundUid = _uid;
    await _loadMyLikes();
    await _loadMySaved();
    await refreshFeed(preferCache: true);
    _startWatching();
  }

  /// Recharge la liste des posts aimés par la session. Vide l'ensemble
  /// d'abord : après une déconnexion, aucun like ne doit rester coché.
  Future<void> _loadMyLikes() async {
    final uid = _uid;
    _myLikes.clear();
    if (uid == null) return;
    try {
      _myLikes.addAll(await _feed.myLikedPostIds(uid));
    } catch (e) {
      developer.log('Chargement des likes', name: 'HomeController', error: e);
    }
  }

  /// Recharge les publications enregistrées. Vidé d'abord, pour la même
  /// raison que [_loadMyLikes] : après une déconnexion, aucun signet ne
  /// doit rester allumé.
  Future<void> _loadMySaved() async {
    final uid = _uid;
    savedPostIds.clear();
    if (uid == null) return;
    try {
      savedPostIds.addAll(await _feed.mySavedPostIds(uid));
    } catch (e) {
      developer.log(
        'Chargement des enregistrements',
        name: 'HomeController',
        error: e,
      );
    }
  }

  /// Recharge la liste des comptes suivis. Vidée d'abord, comme les likes
  /// et les enregistrements : après une déconnexion, plus aucun compte
  /// n'est suivi et le fil redevient purement chronologique.
  Future<void> _loadFollowing() async {
    final uid = _uid;
    _followingUids.clear();
    if (uid == null) return;
    try {
      _followingUids.addAll(await _follow.getFollowing(uid, limit: 200));
    } catch (e) {
      developer.log(
        'Chargement des abonnements',
        name: 'HomeController',
        error: e,
      );
    }
  }

  /// Vrai si la session a mis [postId] de côté. `RxSet.contains` passe par
  /// le getter observable de l'ensemble : appelé dans un `Obx`, il abonne
  /// le widget, et chaque signet se remet donc à jour tout seul.
  bool isSavedByMe(String postId) => savedPostIds.contains(postId);

  /// Pose ou retire le signet. Bascule d'abord l'affichage, puis écrit :
  /// l'écriture est un simple document personnel, mais elle passe quand
  /// même par le réseau et le signet doit répondre à l'instant.
  Future<void> toggleSave(FeedItem post) async {
    if (!await _ensureAuthenticated()) return;
    final uid = _auth.uid;
    final saved = !savedPostIds.contains(post.id);

    HapticFeedback.selectionClick();
    if (saved) _memory.bump(post.authorUid, FeedMemory.save);
    if (saved) {
      savedPostIds.add(post.id);
    } else {
      savedPostIds.remove(post.id);
    }

    try {
      await _feed.setSaved(post.id, uid, saved);
      Get.snackbar(
        saved ? 'Publication enregistrée' : 'Retirée des enregistrements',
        saved
            ? 'Retrouvez-la dans « Enregistrés ».'
            : 'Elle n’apparaît plus dans « Enregistrés ».',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      // Retour à l'état d'avant l'appui : un signet allumé qui n'existe
      // pas côté serveur disparaîtrait au prochain lancement sans que
      // personne comprenne pourquoi.
      if (saved) {
        savedPostIds.remove(post.id);
      } else {
        savedPostIds.add(post.id);
      }
      _notifyError('Enregistrement impossible', e);
    }
  }

  /// Répercute l'ensemble sur les posts déjà affichés — utile après un
  /// rechargement du miroir, quand le fil est en place mais coché à faux.
  void _applyMyLikesToItems() {
    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final liked = _myLikes.contains(items[i].id);
      if (items[i].likedByMe != liked) {
        items[i] = items[i].copyWith(likedByMe: liked);
        changed = true;
      }
    }
    if (changed) items.refresh();
  }

  /// Vrai si la session a aimé [postId] — source unique consultée par le
  /// fil, l'écoute temps réel et l'écran de détail.
  bool isLikedByMe(String postId) => _myLikes.contains(postId);

  /// Recharge et réécoute le fil quand la session change (restauration au
  /// lancement, connexion, déconnexion) : `likedByMe` se calcule à partir de
  /// l'uid, il doit être recalculé avec le bon.
  Future<void> _onAuthChanged() async {
    final uid = _uid;
    if (uid == _boundUid) return;
    _boundUid = uid;
    _profiles.clearVerifiedCache();
    // `refreshFeed` s'ignore lui-même tant qu'un chargement tourne : on
    // attend la fin du premier, sinon ce rechargement serait perdu.
    await _firstLoad;
    await _loadMyLikes();
    await _loadMySaved();
    await refreshFeed();
    _applyMyLikesToItems();
    _startWatching();
  }

  void _startWatching() {
    _watchSub?.cancel();
    _marketWatchSub?.cancel();

    _watchSub = _feed.watchPosts(
      isLikedByMe: isLikedByMe,
      onAdded: _onPostArrived,
      onModified: (updated) {
        if (_pool.containsKey(updated.id)) _pool[updated.id] = updated;
        final q = _queue.indexWhere((e) => e.id == updated.id);
        if (q >= 0) _queue[q] = updated;
        final i = items.indexWhere((e) => e.id == updated.id);
        if (i < 0) return;
        if (!_isVisible(updated)) {
          items.removeAt(i);
        } else {
          // Le document du post ne porte qu'une copie figée de
          // `authorVerified` : on garde celle déjà résolue depuis le
          // profil, sinon une simple édition ferait disparaître le badge.
          items[i] = updated.copyWith(authorVerified: items[i].authorVerified);
        }
        items.refresh();
      },
      onRemoved: (id) {
        _pool.remove(id);
        _queue.removeWhere((e) => e.id == id);
        pendingNew.removeWhere((e) => e.id == id);
        items.removeWhere((e) => e.id == id);
        items.refresh();
      },
    );

    _marketWatchSub = _market.watchMarket(
      onAdded: (item) {
        if (marketItems.every((e) => e.id != item.id) &&
            isMarketMode &&
            _isListingVisible(item)) {
          marketItems.insert(0, item);
          marketItems.refresh();
        }
      },
      onModified: (updated) {
        final i = marketItems.indexWhere((e) => e.id == updated.id);
        if (i < 0) return;
        if (!_isListingVisible(updated)) {
          marketItems.removeAt(i);
        } else {
          marketItems[i] = updated;
        }
        marketItems.refresh();
      },
      onRemoved: (id) {
        marketItems.removeWhere((e) => e.id == id);
        marketItems.refresh();
      },
    );
  }

  /// Une publication signalée par l'écoute temps réel.
  ///
  /// - la sienne, à l'instant : en tête, tout de suite ;
  /// - une vraie nouveauté : en tête si l'on est en haut du fil, sinon
  ///   dans la pastille « Nouvelles publications » — rien ne bouge sous
  ///   le doigt pendant la lecture ;
  /// - une plus ancienne, inconnue jusque-là : rejoint les candidates.
  void _onPostArrived(FeedItem item) {
    if (_pool.containsKey(item.id) || items.any((e) => e.id == item.id)) {
      return;
    }
    if (!_matchesFilter(item) || !_isVisible(item)) return;
    _pool[item.id] = item;

    final mine = _uid != null && item.authorUid == _uid;
    final fresh = item.publishedAt.isAfter(
      _visitStart.subtract(const Duration(minutes: 1)),
    );
    if (mine && fresh) {
      items.insert(0, item);
      items.refresh();
      _scrollToTop();
      return;
    }
    if (fresh) {
      if (_nearTop) {
        items.insert(0, item);
        items.refresh();
        unawaited(_syncVerifiedBadges());
      } else {
        pendingNew.insert(0, item);
      }
      return;
    }
    _lateArrivals.add(item);
    _lateTimer?.cancel();
    _lateTimer = Timer(const Duration(milliseconds: 400), _absorbLateArrivals);
  }

  /// Intègre les publications arrivées après coup : si personne n'a encore
  /// fait défiler, tout le fil est reclassé avec elles ; sinon elles
  /// rejoignent les publications à venir, sans toucher à ce qui est lu.
  void _absorbLateArrivals() {
    if (_lateArrivals.isEmpty) return;
    _lateArrivals.clear();
    if (_nearTop) {
      _rankAll();
    } else {
      _rerankQueue(Random(_feedSeed + ++_pageIndex));
    }
    hasMore.value = _queue.isNotEmpty || _morePages;
  }

  bool get _nearTop =>
      !scrollController.hasClients || scrollController.offset < 40;

  void _scrollToTop() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// Affiche les nouvelles publications annoncées par la pastille.
  void showPendingNew() {
    if (pendingNew.isEmpty) return;
    final fresh = pendingNew.where(_isVisible).toList();
    pendingNew.clear();
    items.insertAll(0, fresh);
    items.refresh();
    unawaited(_syncVerifiedBadges());
    _scrollToTop();
  }

  FeedViewer _viewer() =>
      _memory.viewer(uid: _uid, following: _followingUids, liked: _myLikes);

  /// Classe toutes les candidates et repart du haut : un premier lot à
  /// l'écran, le reste en attente.
  void _rankAll() {
    final ranked = FeedRanker.rank(
      _pool.values.where(_isVisible),
      _viewer(),
      random: Random(_feedSeed),
    );
    items.assignAll(ranked.take(_batch));
    _queue = ranked.skip(_batch).toList();
    unawaited(_syncVerifiedBadges());
  }

  /// Reclasse les publications pas encore affichées, en y ajoutant les
  /// candidates qui n'y sont pas encore — ce qui est à l'écran ne bouge pas.
  void _rerankQueue(Random random) {
    final shown = items.map((e) => e.id).toSet();
    _queue = FeedRanker.rank(
      _pool.values.where((e) => !shown.contains(e.id) && _isVisible(e)),
      _viewer(),
      random: random,
    );
  }

  /// La carte [item] est restée à l'écran : vue. Appelé par la carte.
  void markSeen(FeedItem item) => _memory.markSeen(item.id);

  /// On s'est attardé plusieurs secondes sur [item] : signe d'intérêt
  /// pour son auteur.
  void markDwell(FeedItem item) {
    if (_dwelled.add(item.id)) _memory.bump(item.authorUid, FeedMemory.dwell);
  }

  String? _authorOf(String postId) =>
      (_pool[postId] ?? items.firstWhereOrNull((e) => e.id == postId))
          ?.authorUid;

  bool _matchesFilter(FeedItem item) {
    return switch (filter.value) {
      FeedFilter.all => true,
      FeedFilter.population => item.type == FeedType.post,
      FeedFilter.venteAchat => false,
    };
  }

  void _onScroll() {
    if (scrollController.hasClients &&
        scrollController.offset <= 0 &&
        pendingNew.isNotEmpty) {
      showPendingNew();
    }
    if (!scrollController.hasClients || isLoadingMore.value || !hasMore.value) {
      return;
    }
    final pos = scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      loadMore();
    }
  }

  bool get isMarketMode => filter.value == FeedFilter.venteAchat;

  /// [preferCache] n'est vrai qu'au tout premier chargement — un
  /// « tirer pour rafraîchir » doit toujours interroger le serveur.
  Future<void> refreshFeed({bool preferCache = false}) async {
    if (isLoading.value) return;
    isLoading.value = true;
    hasMore.value = true;
    Future<void>? highlights;
    try {
      if (isMarketMode) {
        // `MarketService` ne pagine plus : il sert une fenêtre unique
        // d'annonces (voir `fetchWindow`), il n'y a donc pas de suite à
        // charger sous l'onglet « Vente & Achat ».
        final window = await _market.fetchWindow(preferCache: preferCache);
        marketItems.assignAll(window.where(_isListingVisible));
        hasMore.value = false;
      } else {
        // Nouvelle graine à chaque chargement : c'est ce qui fait qu'on
        // ne retombe pas sur le fil de la veille, à l'identique.
        _feedSeed = DateTime.now().microsecondsSinceEpoch;
        _pageIndex = 0;
        _visitStart = DateTime.now();
        await _memory.use(_uid);
        final page = await _feed.fetchPage(
          filter: filter.value,
          reset: true,
          likedPostIds: _myLikes,
          preferCache: preferCache,
          // Première page volontairement large : le classement a besoin
          // de matière pour choisir ce qui ouvre le fil.
          limit: _firstPoolSize,
        );
        // Basé sur la page brute, pas sur la liste filtrée : masquer des
        // posts (modération, blocage) raccourcit la page sans pour autant
        // signifier qu'on a atteint la fin du fil.
        _morePages = _feed.lastPageWasFull;
        _pool
          ..clear()
          ..addEntries(page.map((e) => MapEntry(e.id, e)));
        pendingNew.clear();
        _lateArrivals.clear();
        _dwelled.clear();
        _rankAll();
        hasMore.value = _queue.isNotEmpty || _morePages;
        // La mise en avant des abonnements demande deux requêtes de plus.
        // Au tout premier affichage (page servie par le cache), on ne les
        // attend pas : le fil chronologique s'affiche tout de suite et se
        // réordonne quand la réponse arrive. Un rafraîchissement demandé
        // par l'utilisateur, lui, doit rendre la main sur le fil final.
        highlights = _refreshFollowingHighlights();
        if (!preferCache) await highlights;
      }
    } finally {
      isLoading.value = false;
    }

    if (highlights == null) return;
    if (preferCache) {
      unawaited(highlights);
    } else {
      await highlights;
    }
  }

  /// Ajoute aux candidates la dernière publication du jour de chaque
  /// compte suivi — souvent absente de la première page — et recharge la
  /// liste des abonnements, qui pèse dans le classement.
  ///
  /// Si l'on n'a pas encore fait défiler, tout le fil est reclassé avec ces
  /// informations ; sinon seules les publications à venir le sont.
  Future<void> _refreshFollowingHighlights() async {
    final wantedFilter = filter.value;
    await _loadFollowing();
    final List<FeedItem> highlights;
    try {
      highlights = await _feed.fetchFollowingHighlights(
        followingUids: _followingUids,
        filter: wantedFilter,
        likedPostIds: _myLikes,
      );
    } catch (e) {
      // Un bonus : son échec laisse le fil tel quel — et, au premier
      // affichage, elle est attendue hors du `await` de `refreshFeed`, où
      // une exception ne serait rattrapée par personne.
      developer.log(
        'Mise en avant des abonnements',
        name: 'HomeController',
        error: e,
      );
      return;
    }
    // Le fil a pu changer de filtre (ou passer en mode marché) pendant les
    // deux requêtes : ces publications ne correspondent plus à ce qui est
    // affiché.
    if (filter.value != wantedFilter || isMarketMode) return;

    for (final h in highlights) {
      _pool.putIfAbsent(h.id, () => h);
    }
    if (_followingUids.isEmpty && highlights.isEmpty) return;
    if (_nearTop) {
      _rankAll();
    } else {
      _rerankQueue(Random(_feedSeed + ++_pageIndex));
    }
    hasMore.value = _queue.isNotEmpty || _morePages;
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      if (isMarketMode) {
        // Fenêtre unique : tout est déjà chargé par `refreshFeed`.
        hasMore.value = false;
        return;
      }

      // Il reste peu de publications classées : on charge une page de
      // plus, que l'on classe avec elles. Une page peut n'apporter aucune
      // publication nouvelle et visible (déjà connues, auteurs bloqués) :
      // on enchaîne alors, sans quoi le défilement s'arrêterait net alors
      // qu'il reste des publications à lire.
      if (_queue.length < _batch && _morePages) {
        for (var chase = 0; chase < _maxEmptyPageChases; chase++) {
          final page = await _feed.fetchPage(
            filter: filter.value,
            likedPostIds: _myLikes,
            limit: _nextPoolSize,
          );
          _morePages = _feed.lastPageWasFull;
          var added = false;
          for (final p in page) {
            if (_pool.containsKey(p.id) || !_isVisible(p)) continue;
            _pool[p.id] = p;
            added = true;
          }
          if (added) {
            _rerankQueue(Random(_feedSeed + ++_pageIndex));
            break;
          }
          if (!_morePages) break;
        }
      }

      // Lot suivant : jamais une histoire déjà à l'écran (une republication
      // dont l'original vient de passer), et pas le même auteur que les
      // dernières cartes quand on peut l'éviter.
      final shownStories = {for (final e in items) e.repostOfId ?? e.id};
      _queue = FeedRanker.diversify(
        _queue
            .where(_isVisible)
            .where((e) => !shownStories.contains(e.repostOfId ?? e.id))
            .toList(),
        before: items,
      );
      final next = _queue.take(_batch).toList();
      _queue = _queue.skip(next.length).toList();
      if (next.isNotEmpty) {
        items.addAll(next);
        unawaited(_syncVerifiedBadges());
      }
      hasMore.value = _queue.isNotEmpty || _morePages;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// Rebat le fil sans rien recharger : nouvelle graine, nouvel ordre.
  ///
  /// Proposé en bas de fil plutôt qu'un « Fin du fil d'actualité » sans
  /// suite — dans une commune, on a vite fait le tour des publications, et
  /// une impasse donne l'impression que l'app est vide.
  void reshuffleFeed() {
    _feedSeed = DateTime.now().microsecondsSinceEpoch;
    _pageIndex = 0;
    // Le classement tient compte de tout ce qui vient d'être vu : ce qui
    // a été lu recule, le reste remonte.
    _rankAll();
    hasMore.value = _queue.isNotEmpty || _morePages;
    _scrollToTop();
  }

  Future<void> setFilter(FeedFilter value) async {
    if (filter.value == value) return;
    filter.value = value;
    await refreshFeed();
    _startWatching();
  }

  /// Bascule le « j'aime » de la session sur [postId].
  ///
  /// L'affichage réagit immédiatement, mais c'est l'état renvoyé par la
  /// transaction qui fait foi : un compteur local incrémenté à l'aveugle
  /// s'accumulait à chaque appui dès que le client se croyait à tort « pas
  /// encore aimé » (l'écriture serveur était alors sans effet, donc rien ne
  /// venait le corriger). Une rafale d'appuis ne lance qu'une écriture à la
  /// fois : les suivants déplacent la cible, appliquée à la fin de celle en
  /// cours.
  Future<void> toggleLike(String postId) async {
    if (!await _ensureAuthenticated()) return;
    final uid = _auth.uid;

    // Le retour haptique part avec l'affichage, pas avec l'écriture : il
    // accompagne le geste, il ne confirme pas l'aller-retour serveur.
    HapticFeedback.selectionClick();

    final index = items.indexWhere((e) => e.id == postId);
    // Le post peut ne pas être dans le fil chargé (ouvert depuis une
    // notification ou un profil) : l'écriture doit tout de même partir,
    // l'écran de détail suit le document en direct.
    final shown = index >= 0 ? items[index] : null;
    final liked = !(_desiredLike[postId] ?? _myLikes.contains(postId));
    _desiredLike[postId] = liked;
    _memory.bump(
      shown?.authorUid ?? _authorOf(postId),
      liked ? FeedMemory.like : FeedMemory.unlike,
    );

    // L'ensemble bascule tout de suite : c'est lui, et non le document du
    // post, qui décide de l'état affiché du cœur — y compris pour les
    // événements temps réel qui vont suivre l'écriture.
    if (liked) {
      _myLikes.add(postId);
    } else {
      _myLikes.remove(postId);
    }

    if (shown != null) {
      items[index] = shown.copyWith(
        likedByMe: liked,
        likesCount: (shown.likesCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
      );
      items.refresh();
    }

    if (_likeInFlight.contains(postId)) return;
    _likeInFlight.add(postId);
    try {
      var target = liked;
      while (true) {
        final state = await _feed.setLike(postId, uid, target);
        if (state.likedByMe) {
          _myLikes.add(postId);
        } else {
          _myLikes.remove(postId);
        }
        _applyLikeState(postId, state.likedByMe, state.likesCount);
        final next = _desiredLike[postId];
        if (next == null || next == target) break;
        target = next;
      }
    } catch (_) {
      // Écriture impossible (réseau) : on revient sur ce qui était affiché
      // avant l'appui, sans remettre en place le reste du post, qui a pu
      // changer entre-temps (commentaires, édition).
      if (shown != null) {
        if (shown.likedByMe) {
          _myLikes.add(postId);
        } else {
          _myLikes.remove(postId);
        }
        _applyLikeState(postId, shown.likedByMe, shown.likesCount);
      }
    } finally {
      _likeInFlight.remove(postId);
      _desiredLike.remove(postId);
    }
  }

  void _applyLikeState(String postId, bool likedByMe, int likesCount) {
    final i = items.indexWhere((e) => e.id == postId);
    if (i < 0) return;
    items[i] = items[i].copyWith(likedByMe: likedByMe, likesCount: likesCount);
    items.refresh();
  }

  Future<void> addComment(
    String postId,
    String text, {
    String? parentCommentId,
    String? replyToName,
  }) async {
    if (!await _ensureAuthenticated()) return;
    final profile = _profiles.profile.value!;
    _memory.bump(_authorOf(postId), FeedMemory.comment);
    await _feed.addComment(
      postId: postId,
      authorUid: _auth.uid,
      authorName: profile.displayName,
      authorPhotoUrl: profile.photoUrl,
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
    await _feed.setCommentLike(postId, commentId, _auth.uid, !currentlyLiked);
  }

  // -----------------------------------------------------------------------
  // Actions sur une publication (auteur : modifier / supprimer / fermer les
  // commentaires — tiers : partager / signaler / bloquer l'auteur)
  // -----------------------------------------------------------------------

  bool isMyPost(FeedItem post) =>
      _auth.isSignedIn && post.authorUid == _auth.uid;

  /// Répercute une version à jour du post dans le fil (et dans le détail,
  /// qui lit la même liste).
  void _replaceItem(FeedItem updated) {
    final i = items.indexWhere((e) => e.id == updated.id);
    if (i >= 0) {
      items[i] = updated;
      items.refresh();
    }
  }

  void _removeItem(String postId) {
    _pool.remove(postId);
    _queue.removeWhere((e) => e.id == postId);
    items.removeWhere((e) => e.id == postId);
    items.refresh();
  }

  Future<void> editPost(FeedItem post) async {
    if (!isMyPost(post)) return;
    final result = await Get.toNamed(
      AppRoutes.compose,
      arguments: post,
      preventDuplicates: false,
    );
    if (result is FeedItem) _replaceItem(result);
  }

  Future<void> deletePost(FeedItem post) async {
    if (!isMyPost(post)) return;

    final confirmed = await confirmAction(
      title: 'Supprimer la publication ?',
      message: post.commentsCount > 0
          ? 'Cette publication et ses ${post.commentsCount} commentaires '
                'seront définitivement supprimés. Cette action est irréversible.'
          : 'Cette publication sera définitivement supprimée. Cette action '
                'est irréversible.',
    );
    if (!confirmed) return;

    // Retiré de la liste avant l'aller-retour réseau : l'utilisateur vient
    // de confirmer, l'attente ne doit pas donner l'impression d'un échec.
    // Le flux temps réel confirmera, et en cas d'erreur on réinsère.
    final index = items.indexWhere((e) => e.id == post.id);
    _removeItem(post.id);

    try {
      await _feed.deletePost(post);
    } catch (e) {
      if (index >= 0 && items.every((x) => x.id != post.id)) {
        items.insert(index.clamp(0, items.length), post);
        items.refresh();
      }
      _notifyError('Suppression impossible', e);
    }
  }

  Future<void> toggleComments(FeedItem post) async {
    if (!isMyPost(post)) return;
    final disabled = !post.commentsDisabled;
    _replaceItem(post.copyWith(commentsDisabled: disabled));
    try {
      await _feed.setCommentsDisabled(post.id, disabled);
    } catch (e) {
      _replaceItem(post);
      _notifyError('Modification impossible', e);
    }
  }

  Future<void> sharePost(FeedItem post) async {
    await SharePlus.instance.share(
      ShareParams(text: post.shareText, subject: post.summaryLine),
    );
  }

  Future<void> repostPost(FeedItem post) async {
    if (!await _ensureAuthenticated()) return;
    final profile = _profiles.profile.value;
    if (profile == null) return;

    _memory.bump(post.authorUid, FeedMemory.repost);
    try {
      await _feed.repostPost(
        original: post,
        authorUid: _auth.uid,
        authorName: profile.displayName,
        authorSubtitle: profile.authorSubtitle,
        authorVerified: profile.verified,
        authorPhotoUrl: profile.photoUrl,
      );
      Get.snackbar(
        'Republication envoyée',
        'La publication apparaît en tête du fil.',
        duration: const Duration(seconds: 3),
      );
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      _notifyError('Republication impossible', e);
    }
  }

  Future<void> reportPost(FeedItem post) async {
    if (!await _ensureAuthenticated()) return;

    final choice = await showReportSheet(targetLabel: 'cette publication');
    if (choice == null) return;

    await _submitReport(
      ContentReport(
        targetType: ReportTargetType.post,
        targetId: post.id,
        targetPath: 'posts/${post.id}',
        targetOwnerUid: post.authorUid,
        reporterUid: _auth.uid,
        reason: choice.reason,
        details: choice.details,
        excerpt: '${post.summaryLine}\n${post.body}'.trim(),
      ),
    );
  }

  Future<void> reportComment(String postId, FeedComment comment) async {
    if (!await _ensureAuthenticated()) return;

    final choice = await showReportSheet(targetLabel: 'ce commentaire');
    if (choice == null) return;

    await _submitReport(
      ContentReport(
        targetType: ReportTargetType.comment,
        targetId: comment.id,
        targetPath: 'posts/$postId/comments/${comment.id}',
        targetOwnerUid: comment.authorUid,
        reporterUid: _auth.uid,
        reason: choice.reason,
        details: choice.details,
        excerpt: comment.text,
      ),
    );
  }

  Future<void> _submitReport(ContentReport report) async {
    try {
      await _moderation.report(report);
      Get.snackbar(
        'Signalement envoyé',
        'Merci. Notre équipe examine ce contenu.',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      _notifyError('Signalement impossible', e);
    }
  }

  /// Bloque l'auteur d'un contenu : ses publications et commentaires
  /// disparaissent immédiatement pour l'utilisateur courant. Le blocage est
  /// unilatéral — la personne bloquée n'en est pas informée.
  Future<void> blockAuthor({
    required String authorUid,
    required String authorName,
  }) async {
    if (!await _ensureAuthenticated()) return;
    if (authorUid.isEmpty || authorUid == _auth.uid) return;

    final confirmed = await confirmAction(
      title: 'Bloquer $authorName ?',
      message:
          'Elle ne pourra plus vous écrire, vous appeler, vous suivre ni '
          'commenter vos publications, et vous ne verrez plus ses '
          'contenus. Elle ne recevra aucune notification, et vous pourrez '
          'la débloquer à tout moment depuis son profil.',
      confirmLabel: 'Bloquer',
    );
    if (!confirmed) return;

    try {
      await _moderation.blockUser(
        myUid: _auth.uid,
        targetUid: authorUid,
        targetName: authorName,
      );
      items.removeWhere((e) => e.authorUid == authorUid);
      items.refresh();
      Get.snackbar(
        'Compte bloqué',
        'Vous ne verrez plus les contenus de $authorName.',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      _notifyError('Blocage impossible', e);
    }
  }

  // -----------------------------------------------------------------------
  // Actions sur un commentaire
  // -----------------------------------------------------------------------

  bool isMyComment(FeedComment comment) =>
      _auth.isSignedIn && comment.authorUid == _auth.uid;

  Future<void> editComment(
    String postId,
    FeedComment comment,
    String newText,
  ) async {
    if (!isMyComment(comment)) return;
    final text = newText.trim();
    if (text.isEmpty || text == comment.text) return;
    try {
      await _feed.updateComment(
        postId: postId,
        commentId: comment.id,
        text: text,
      );
    } catch (e) {
      _notifyError('Modification impossible', e);
    }
  }

  Future<void> deleteComment(String postId, FeedComment comment) async {
    if (!isMyComment(comment)) return;

    final confirmed = await confirmAction(
      title: 'Supprimer le commentaire ?',
      message: comment.replies.isNotEmpty
          ? 'Votre texte sera effacé, mais les ${comment.totalReplyCount} '
                'réponses qu\'il a reçues resteront visibles.'
          : 'Ce commentaire sera définitivement supprimé.',
    );
    if (!confirmed) return;

    try {
      await _feed.deleteComment(postId: postId, commentId: comment.id);
      final i = items.indexWhere((e) => e.id == postId);
      if (i >= 0) {
        final item = items[i];
        items[i] = item.copyWith(
          commentsCount: item.commentsCount > 0 ? item.commentsCount - 1 : 0,
        );
        items.refresh();
      }
    } catch (e) {
      _notifyError('Suppression impossible', e);
    }
  }

  void _notifyError(String title, Object error) {
    developer.log(title, name: 'HomeController', error: error);
    if (Get.overlayContext == null) return;
    Get.snackbar(title, '$error', duration: const Duration(seconds: 6));
  }

  void openPost(FeedItem item) {
    _memory.bump(item.authorUid, FeedMemory.open);
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
        middleText:
            'Les comptes structure doivent être validés par '
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
    _pool[item.id] = item;
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
    if (feature.id == AppFeatureId.annuaire) {
      // Consultable sans compte ; les coordonnées et les avis demandent
      // de se connecter, au moment où on en a besoin.
      Get.toNamed(AppRoutes.directory);
      return;
    }
    if (feature.id == AppFeatureId.communaute) {
      ProfileGate.ensure(reason: 'Pour rejoindre la communauté').then((ok) {
        if (ok) Get.toNamed(AppRoutes.community);
      });
      return;
    }
    if (feature.id == AppFeatureId.messages) {
      ProfileGate.ensure(reason: 'Pour écrire ou appeler').then((ok) {
        if (ok) Get.toNamed(AppRoutes.conversations);
      });
      return;
    }
    if (feature.id == AppFeatureId.lives) {
      openLives();
      return;
    }
    if (feature.id == AppFeatureId.enregistres) {
      if (!_auth.isSignedIn) {
        Get.toNamed(AppRoutes.auth);
        return;
      }
      Get.toNamed(AppRoutes.savedPosts);
      return;
    }
    if (feature.id == AppFeatureId.demarches) {
      Get.toNamed(AppRoutes.demarches);
      return;
    }
    if (feature.id == AppFeatureId.notifications) {
      openNotifications();
      return;
    }
    if (feature.id == AppFeatureId.parametres) {
      // Thème et notifications sont des réglages d'appareil : accessibles
      // sans compte, contrairement au profil ou aux messages.
      Get.toNamed(AppRoutes.settings);
      return;
    }
    if (feature.id == AppFeatureId.profil) {
      // Un compte sans profil n'a rien à afficher : on le complète d'abord.
      ProfileGate.ensure(reason: 'Pour afficher votre profil').then((ok) {
        if (ok) Get.toNamed(AppRoutes.userProfile, arguments: _auth.uid);
      });
      return;
    }
    Get.toNamed(AppRoutes.feature, arguments: feature);
  }

  /// Lives — depuis l'icône de la barre du haut ou le tiroir. Les lives
  /// demandent un compte : chaque spectateur est identifié (blocages,
  /// exclusions, signalements).
  ///
  /// Comme sur TikTok, on entre directement dans un live s'il y en a un en
  /// cours (le plus regardé d'abord, les autres en glissant) ; le menu
  /// pour lancer le sien n'apparaît que lorsqu'il n'y a rien à regarder —
  /// le lecteur garde un bouton pour passer à l'antenne.
  Future<void> openLives() async {
    // Le serveur refuse l'entrée d'un live sans profil : on le demande ici.
    if (!await ProfileGate.ensure(reason: 'Pour regarder ou lancer un live')) {
      return;
    }
    final moderation = Get.find<ModerationService>();
    final myUid = _auth.isSignedIn ? _auth.uid : '';
    final hasLive = Get.find<LiveService>().lives.any(
      (l) => l.hostUid != myUid && !moderation.hides(l.hostUid),
    );
    Get.toNamed(hasLive ? AppRoutes.liveViewer : AppRoutes.lives);
  }

  void openNotifications() {
    if (!_auth.isSignedIn) {
      Get.toNamed(AppRoutes.auth);
      return;
    }
    Get.toNamed(AppRoutes.notifications);
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
