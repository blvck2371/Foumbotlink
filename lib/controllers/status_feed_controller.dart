import 'dart:async';
import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../models/user_status.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/moderation_service.dart';
import '../services/status_service.dart';
import '../services/user_profile_service.dart';

/// Les statuts d'une même personne, regroupés en une pastille de la barre
/// d'accueil.
///
/// On ne montre jamais un statut isolé dans la barre : c'est un compte
/// qu'on ouvre, et ses statuts défilent ensuite les uns après les autres.
class StatusBubble {
  const StatusBubble({
    required this.authorUid,
    required this.authorName,
    required this.statuses,
    this.authorPhotoUrl,
    this.isMine = false,
  });

  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;

  /// Du plus ancien au plus récent — l'ordre dans lequel on les regarde.
  final List<UserStatus> statuses;

  final bool isMine;

  bool get hasStatuses => statuses.isNotEmpty;

  /// Vrai tant qu'il reste au moins un statut non vu : c'est ce qui allume
  /// l'anneau en orange.
  bool get hasUnseen => statuses.any((s) => !s.viewedByMe);

  /// Premier statut non vu, ou le premier tout court si tout a été vu —
  /// on reprend là où on s'était arrêté, comme sur Instagram.
  int get startIndex {
    final i = statuses.indexWhere((s) => !s.viewedByMe);
    return i < 0 ? 0 : i;
  }

  DateTime get latestAt => statuses.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : statuses.last.createdAt;
}

/// Barre de statuts de l'accueil.
///
/// Ne montre que les comptes **auxquels on est abonné** — un statut n'est
/// pas une publication du fil, il s'adresse à ceux qu'on a choisi de
/// suivre —, plus les siens en première position.
///
/// Contrôleur à part plutôt qu'un ajout à `HomeController` : la barre a son
/// propre flux temps réel, sa propre liste d'abonnements et son propre
/// cycle de rafraîchissement, et l'accueil est déjà assez chargé.
class StatusFeedController extends GetxController {
  /// Pastilles affichées, la sienne en tête puis les autres, les non vues
  /// d'abord.
  final bubbles = <StatusBubble>[].obs;

  /// Mes propres statuts en cours — pastille « Votre statut ».
  final myStatuses = <UserStatus>[].obs;

  final isLoading = true.obs;

  StatusService get _statuses => Get.find<StatusService>();
  AuthService get _auth => Get.find<AuthService>();
  FollowService get _follow => Get.find<FollowService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  Workers? _hiddenWorker;

  String? get _uid => _auth.isSignedIn ? _auth.uid : null;

  StatusFeedSubscription? _followedSub;
  StreamSubscription? _mineSub;

  final _followingUids = <String>{};
  final _viewedIds = <String>{};
  final _likedIds = <String>{};

  /// Derniers statuts reçus des comptes suivis, avant regroupement.
  final _followedStatuses = <UserStatus>[];

  /// Uid pour lequel les flux sont ouverts — sert à ne pas tout relancer
  /// quand l'état d'authentification est notifié sans avoir changé.
  String? _boundUid;

  @override
  void onInit() {
    super.onInit();
    ever(_auth.firebaseUser, (_) => unawaited(_bind()));
    unawaited(_bind());
    _hiddenWorker = _moderation.watchHidden((_) => _rebuild());
  }

  @override
  void onClose() {
    unawaited(_followedSub?.cancel());
    _mineSub?.cancel();
    _hiddenWorker?.dispose();
    super.onClose();
  }

  /// (Re)branche les flux sur la session courante.
  Future<void> _bind() async {
    final uid = _uid;
    if (uid == _boundUid) return;
    _boundUid = uid;

    await _followedSub?.cancel();
    _mineSub?.cancel();
    _followedSub = null;
    _mineSub = null;
    _followedStatuses.clear();
    myStatuses.clear();
    bubbles.clear();

    if (uid == null) {
      isLoading.value = false;
      return;
    }

    isLoading.value = true;
    await _loadMirrors(uid);
    await _loadFollowing(uid);
    _watchMine(uid);
    _watchFollowed();
    isLoading.value = false;
  }

  /// Miroirs personnels : ce que j'ai vu et ce que j'ai aimé. Deux
  /// requêtes au lancement, contre une par statut affiché si on
  /// interrogeait chaque document.
  Future<void> _loadMirrors(String uid) async {
    try {
      final viewed = await _statuses.myViewedStatusIds(uid);
      _viewedIds
        ..clear()
        ..addAll(viewed);
    } catch (e) {
      developer.log('Statuts vus', name: 'StatusFeedController', error: e);
    }
    try {
      final liked = await _statuses.myLikedStatusIds(uid);
      _likedIds
        ..clear()
        ..addAll(liked);
    } catch (e) {
      developer.log('Statuts aimés', name: 'StatusFeedController', error: e);
    }
  }

  Future<void> _loadFollowing(String uid) async {
    _followingUids.clear();
    try {
      _followingUids.addAll(await _follow.getFollowing(uid, limit: 200));
    } catch (e) {
      developer.log(
        'Abonnements',
        name: 'StatusFeedController',
        error: e,
      );
    }
  }

  void _watchMine(String uid) {
    _mineSub = _statuses.watchUserStatuses(
      uid: uid,
      includeHidden: true,
      viewedIds: _viewedIds,
      likedIds: _likedIds,
      onData: (list) {
        myStatuses.assignAll(list);
        _rebuild();
      },
      onError: (e) {
        developer.log('Mes statuts', name: 'StatusFeedController', error: e);
        myStatuses.clear();
        _rebuild();
      },
    );
  }

  void _watchFollowed() {
    _followedSub = _statuses.watchFollowedStatuses(
      followingUids: _followingUids,
      viewedIds: _viewedIds,
      likedIds: _likedIds,
      onData: (list) {
        _followedStatuses
          ..clear()
          ..addAll(list);
        _rebuild();
      },
      onError: (e) {
        // Index absent, hors ligne, droits : l'accueil doit rester
        // consultable sans sa barre de statuts.
        developer.log(
          'Statuts des abonnements',
          name: 'StatusFeedController',
          error: e,
        );
      },
    );
  }

  /// Regroupe les statuts par auteur et ordonne la barre.
  ///
  /// Les comptes ayant du neuf passent devant, puis les plus récents :
  /// c'est ce qui fait qu'on voit d'un coup d'œil où il reste quelque
  /// chose à découvrir, sans rien lire.
  void _rebuild() {
    final uid = _uid;
    final grouped = <String, List<UserStatus>>{};
    for (final status in _followedStatuses) {
      if (status.authorUid == uid) continue; // les miens ont leur pastille
      if (_moderation.hides(status.authorUid)) continue; // blocage
      grouped.putIfAbsent(status.authorUid, () => []).add(status);
    }

    final others = <StatusBubble>[];
    for (final entry in grouped.entries) {
      final list = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      others.add(
        StatusBubble(
          authorUid: entry.key,
          authorName: list.last.authorName,
          authorPhotoUrl: list.last.authorPhotoUrl,
          statuses: list,
        ),
      );
    }

    others.sort((a, b) {
      if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
      return b.latestAt.compareTo(a.latestAt);
    });

    final profile = _profiles.profile.value;
    final mine = StatusBubble(
      authorUid: uid ?? '',
      authorName: profile?.displayName ?? 'Vous',
      authorPhotoUrl: profile?.photoUrl,
      statuses: List<UserStatus>.from(myStatuses)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      isMine: true,
    );

    bubbles.assignAll([mine, ...others]);
  }

  /// Recale les anneaux après un passage dans la visionneuse.
  ///
  /// C'est la visionneuse qui enregistre les vues, statut par statut, à
  /// mesure qu'ils s'affichent : on relit donc le miroir plutôt que de
  /// tout marquer comme vu. Quelqu'un qui referme après le premier statut
  /// n'a pas vu les suivants, et l'anneau doit continuer de le signaler.
  Future<void> refreshSeen() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final viewed = await _statuses.myViewedStatusIds(uid);
      _viewedIds
        ..clear()
        ..addAll(viewed);
    } catch (e) {
      developer.log('Statuts vus', name: 'StatusFeedController', error: e);
      return;
    }
    _applyMirrors();
  }

  /// Retire un de ses propres statuts avant son échéance. Les vues, les
  /// « j'aime » et le fichier sont purgés côté serveur
  /// (`onStatusDeleted`) ; le flux temps réel retire la pastille de
  /// lui-même.
  Future<void> deleteMyStatus(String statusId) async {
    try {
      await _statuses.deleteStatus(statusId);
      myStatuses.removeWhere((s) => s.id == statusId);
      _rebuild();
    } catch (e) {
      developer.log(
        'Suppression du statut',
        name: 'StatusFeedController',
        error: e,
      );
      Get.snackbar(
        'Suppression impossible',
        'Réessayez dans un instant.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Répercute un « j'aime » posé depuis la visionneuse, pour que l'état
  /// survive à sa fermeture.
  void applyLike(String statusId, bool liked) {
    if (liked) {
      _likedIds.add(statusId);
    } else {
      _likedIds.remove(statusId);
    }
    _applyMirrors();
  }

  /// Réapplique les miroirs (vus, aimés) aux statuts déjà en mémoire,
  /// sans relancer les flux.
  void _applyMirrors() {
    UserStatus withMirrors(UserStatus s) => s.copyWith(
          viewedByMe: _viewedIds.contains(s.id),
          likedByMe: _likedIds.contains(s.id),
        );

    for (var i = 0; i < _followedStatuses.length; i++) {
      _followedStatuses[i] = withMirrors(_followedStatuses[i]);
    }
    myStatuses.assignAll(myStatuses.map(withMirrors));
    _rebuild();
  }

  /// Relit abonnements et miroirs, puis relance le flux — après un
  /// nouvel abonnement, ou sur un « tirer pour rafraîchir ».
  @override
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    await _loadMirrors(uid);
    await _loadFollowing(uid);
    await _followedSub?.cancel();
    _watchFollowed();
  }
}
