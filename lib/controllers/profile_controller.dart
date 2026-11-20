import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/feed_item.dart';
import '../models/report.dart';
import '../models/user_profile.dart';
import '../models/user_status.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/moderation_service.dart';
import '../services/status_service.dart';
import '../services/user_profile_service.dart';
import '../screens/status/status_composer_screen.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/report_sheet.dart';

class ProfileController extends GetxController {
  final targetUid = ''.obs;
  final profile = Rxn<UserProfile>();
  final posts = <FeedItem>[].obs;
  final isFollowing = false.obs;
  final isLoadingProfile = true.obs;
  final isLoadingPosts = true.obs;
  final isToggling = false.obs;
  final isBlocked = false.obs;
  final isUploadingPhoto = false.obs;

  /// Statuts encore vivants de ce profil, du plus ancien au plus récent.
  final statuses = <UserStatus>[].obs;
  final isPublishingStatus = false.obs;

  AuthService get _auth => Get.find<AuthService>();
  FollowService get _follow => Get.find<FollowService>();
  ModerationService get _moderation => Get.find<ModerationService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();
  StatusService get _statuses => Get.find<StatusService>();

  StreamSubscription? _profileSub;
  StreamSubscription? _followSub;
  StreamSubscription? _postsSub;
  StreamSubscription? _statusSub;

  bool get isOwnProfile => _auth.isSignedIn && _auth.uid == targetUid.value;

  bool get hasStatuses => statuses.isNotEmpty;

  /// Vrai s'il reste au moins un statut que la session n'a pas ouvert —
  /// c'est ce qui allume l'anneau autour de l'avatar. Ses propres statuts
  /// ne sont jamais « neufs » pour soi-même.
  bool get hasUnseenStatuses =>
      !isOwnProfile && statuses.any((s) => !s.viewedByMe);

  @override
  void onInit() {
    super.onInit();
    final uid = Get.arguments as String;
    targetUid.value = uid;
    _watchProfile(uid);
    _watchPosts(uid);
    _watchStatuses(uid);
    if (_auth.isSignedIn && !isOwnProfile) {
      _watchFollowStatus(uid);
      isBlocked.value = _moderation.isBlocked(uid);
    }
  }

  @override
  void onClose() {
    _profileSub?.cancel();
    _followSub?.cancel();
    _postsSub?.cancel();
    _statusSub?.cancel();
    super.onClose();
  }

  void _watchProfile(String uid) {
    _profileSub = _follow.watchUserProfile(
      uid: uid,
      onData: (data) {
        if (data != null) {
          profile.value = UserProfile.fromMap(uid, data);
        } else {
          profile.value = null;
        }
        isLoadingProfile.value = false;
      },
    );
  }

  void _watchFollowStatus(String uid) {
    _followSub?.cancel();
    _followSub = _follow.watchFollowStatus(
      myUid: _auth.uid,
      targetUid: uid,
      onData: (following) {
        isFollowing.value = following;
      },
    );
  }

  /// Publications de ce profil, en flux plutôt qu'en lecture unique : sans
  /// cela, supprimer ou modifier un post depuis l'écran de détail laissait
  /// la grille du profil périmée jusqu'à sa réouverture.
  void _watchPosts(String uid) {
    _postsSub?.cancel();
    _postsSub = FirebaseFirestore.instance
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .orderBy('publishedAt', descending: true)
        .limit(30)
        .snapshots()
        .listen(
          (snap) {
            posts.assignAll(
              snap.docs.map(_itemFromDoc).where((item) => !item.hidden),
            );
            isLoadingPosts.value = false;
          },
          onError: (Object e) {
            // Index pas encore prêt ou erreur réseau — on laisse la liste vide
            developer.log(
              'Flux des posts du profil',
              name: 'ProfileController',
              error: e,
            );
            isLoadingPosts.value = false;
          },
        );
  }

  FeedItem _itemFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
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
      authorVerified: d['authorVerified'] as bool? ?? false,
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      repostOfId: d['repostOfId'] as String?,
      repostOfAuthorUid: d['repostOfAuthorUid'] as String?,
      repostOfAuthorName: d['repostOfAuthorName'] as String?,
      repostOfAuthorPhotoUrl: d['repostOfAuthorPhotoUrl'] as String?,
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
      likesCount: d['likesCount'] as int? ?? 0,
      // La grille du profil n'affiche qu'un compteur sous une icône fixe,
      // jamais l'état personnel du cœur : le résoudre coûterait une lecture
      // par vignette dans `posts/{id}/likes/{uid}` pour rien.
      likedByMe: false,
      commentsCount: d['commentsCount'] as int? ?? 0,
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
      commentsDisabled: d['commentsDisabled'] as bool? ?? false,
      hidden: d['hidden'] as bool? ?? false,
    );
  }

  // -----------------------------------------------------------------------
  // Statuts éphémères (24 h)
  // -----------------------------------------------------------------------

  /// Écoute les statuts encore vivants de ce profil.
  ///
  /// Les miroirs personnels — ce que j'ai vu, ce que j'ai aimé — sont
  /// chargés d'abord, en une requête chacun. Sans le premier, tous les
  /// statuts s'afficheraient comme neufs à chaque ouverture du profil ;
  /// sans le second, la visionneuse montrerait un cœur vide sur un statut
  /// déjà aimé.
  Future<void> _watchStatuses(String uid) async {
    var viewed = <String>{};
    var liked = <String>{};
    if (_auth.isSignedIn) {
      try {
        viewed = await _statuses.myViewedStatusIds(_auth.uid);
      } catch (e) {
        developer.log(
          'Statuts déjà vus',
          name: 'ProfileController',
          error: e,
        );
      }
      try {
        liked = await _statuses.myLikedStatusIds(_auth.uid);
      } catch (e) {
        developer.log(
          'Statuts aimés',
          name: 'ProfileController',
          error: e,
        );
      }
    }

    _statusSub?.cancel();
    _statusSub = _statuses.watchUserStatuses(
      uid: uid,
      viewedIds: viewed,
      likedIds: liked,
      onData: statuses.assignAll,
      onError: (e) {
        // Index absent, hors ligne, règles : un profil sans statuts reste
        // un profil parfaitement consultable.
        developer.log('Flux des statuts', name: 'ProfileController', error: e);
        statuses.clear();
      },
    );
  }

  /// Recale l'anneau après un passage dans la visionneuse.
  ///
  /// C'est la visionneuse qui enregistre les vues, statut par statut, à
  /// mesure qu'ils s'affichent. On relit donc le miroir plutôt que de
  /// tout marquer comme vu : quelqu'un qui referme après le premier
  /// statut n'a pas vu les suivants, et l'anneau doit continuer de le
  /// signaler.
  Future<void> refreshSeenStatuses() async {
    if (!_auth.isSignedIn || statuses.isEmpty) return;
    try {
      final viewed = await _statuses.myViewedStatusIds(_auth.uid);
      statuses.assignAll([
        for (final status in statuses)
          status.copyWith(viewedByMe: viewed.contains(status.id)),
      ]);
    } catch (e) {
      developer.log('Statuts vus', name: 'ProfileController', error: e);
    }
  }

  /// Photo de statut : compressée à la sélection comme celles des
  /// publications — un statut se regarde quelques secondes, il ne justifie
  /// pas d'envoyer l'original de l'appareil photo.
  Future<String?> pickStatusPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      return picked?.path;
    } catch (e) {
      developer.log('Photo de statut', name: 'ProfileController', error: e);
      Get.snackbar(
        'Photos indisponibles',
        'Impossible d’ouvrir la galerie.',
        duration: const Duration(seconds: 4),
      );
      return null;
    }
  }

  /// Vidéo de statut : bornée en durée à la prise de vue. Un statut se
  /// regarde d'une traite — au-delà d'une demi-minute, ce n'est plus un
  /// statut, et le fichier pèserait sur le forfait de qui le publie comme
  /// de qui le regarde.
  Future<String?> pickStatusVideo(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      return picked?.path;
    } catch (e) {
      developer.log('Vidéo de statut', name: 'ProfileController', error: e);
      Get.snackbar(
        'Vidéo indisponible',
        'Impossible d’ouvrir la vidéo choisie.',
        duration: const Duration(seconds: 4),
      );
      return null;
    }
  }

  /// Publie le statut composé. Le flux se recale tout seul ensuite : rien
  /// n'est inséré à la main dans [statuses].
  Future<void> publishStatus(StatusDraft draft) async {
    if (!isOwnProfile || draft.isEmpty || isPublishingStatus.value) return;
    final me = _profiles.profile.value;
    if (me == null) return;

    isPublishingStatus.value = true;
    try {
      await _statuses.createStatus(
        authorUid: _auth.uid,
        authorName: me.displayName,
        authorPhotoUrl: me.photoUrl,
        localImagePath: draft.imagePath,
        localVideoPath: draft.videoPath,
        text: draft.text,
        backgroundColor: draft.backgroundColor,
      );
      Get.snackbar(
        'Statut publié',
        'Il disparaîtra dans 24 heures.',
        duration: const Duration(seconds: 3),
      );
    } on StatusMediaTooLarge catch (e) {
      Get.snackbar(
        'Vidéo trop lourde',
        'Elle pèse ${e.sizeLabel} ; le maximum est ${e.maxLabel}. '
            'Filmez une séquence plus courte, ou baissez la définition '
            'vidéo dans les réglages de l’appareil.',
        duration: const Duration(seconds: 8),
      );
    } on FirebaseException catch (e) {
      // Le code d'erreur est montré tel quel : « unauthorized » (règles
      // Storage non déployées, ou fichier hors plafond) ne se corrige pas
      // du tout comme « retry-limit-exceeded » (réseau). Un message unique
      // « vérifiez votre connexion » envoyait sur la mauvaise piste.
      developer.log('Publication du statut',
          name: 'ProfileController', error: e);
      Get.snackbar(
        'Publication impossible',
        '${e.code} — ${e.message ?? 'erreur inconnue'}',
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      developer.log('Publication du statut',
          name: 'ProfileController', error: e);
      Get.snackbar(
        'Publication impossible',
        '$e',
        duration: const Duration(seconds: 8),
      );
    } finally {
      isPublishingStatus.value = false;
    }
  }

  /// Retire un statut avant son échéance. Les vues et la photo sont
  /// purgées côté serveur (`onStatusDeleted`).
  Future<void> deleteStatus(UserStatus status) async {
    if (!isOwnProfile) return;
    try {
      await _statuses.deleteStatus(status.id);
      statuses.removeWhere((s) => s.id == status.id);
    } catch (e) {
      developer.log('Suppression du statut',
          name: 'ProfileController', error: e);
      Get.snackbar(
        'Suppression impossible',
        'Réessayez dans un instant.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Partage et modération du profil
  // -----------------------------------------------------------------------

  Future<void> shareProfile() async {
    final p = profile.value;
    if (p == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Découvrez le profil de ${p.displayName} sur Foumbot Link.',
        subject: p.displayName,
      ),
    );
  }

  Future<void> reportProfile() async {
    final p = profile.value;
    if (p == null || !_auth.isSignedIn) {
      if (!_auth.isSignedIn) await Get.toNamed(AppRoutes.auth);
      return;
    }

    final choice = await showReportSheet(targetLabel: 'ce profil');
    if (choice == null) return;

    try {
      await _moderation.report(
        ContentReport(
          targetType: ReportTargetType.user,
          targetId: p.uid,
          targetPath: 'users/${p.uid}',
          targetOwnerUid: p.uid,
          reporterUid: _auth.uid,
          reason: choice.reason,
          details: choice.details,
          excerpt: p.displayName,
        ),
      );
      Get.snackbar(
        'Signalement envoyé',
        'Merci. Notre équipe examine ce profil.',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      developer.log(
        'Signalement du profil',
        name: 'ProfileController',
        error: e,
      );
      Get.snackbar(
        'Signalement impossible',
        '$e',
        duration: const Duration(seconds: 6),
      );
    }
  }

  /// Bascule le blocage. Le serveur coupe ensuite tout échange dans les
  /// deux sens (voir ModerationService).
  Future<void> toggleBlock() async {
    final p = profile.value;
    if (p == null || isOwnProfile) return;
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return;
    }

    if (isBlocked.value) {
      await _moderation.unblockUser(myUid: _auth.uid, targetUid: p.uid);
      isBlocked.value = false;
      Get.snackbar(
        'Compte débloqué',
        'Vous pouvez de nouveau échanger avec ${p.displayName}.',
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final confirmed = await confirmAction(
      title: 'Bloquer ${p.displayName} ?',
      message:
          'Elle ne pourra plus vous écrire, vous appeler, vous suivre ni '
          'commenter vos publications, et vous ne verrez plus ses '
          'contenus. Elle ne recevra aucune notification, et vous pourrez '
          'la débloquer à tout moment depuis cet écran.',
      confirmLabel: 'Bloquer',
    );
    if (!confirmed) return;

    await _moderation.blockUser(
      myUid: _auth.uid,
      targetUid: p.uid,
      targetName: p.displayName,
    );
    isBlocked.value = true;
    Get.snackbar(
      'Compte bloqué',
      'Vous ne verrez plus les contenus de ${p.displayName}.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> toggleFollow() async {
    if (isOwnProfile || isToggling.value) return;
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return;
      _watchFollowStatus(targetUid.value);
    }
    // Pas d'abonnement entre deux comptes dont l'un a bloqué l'autre
    // (refusé par les règles) ; se désabonner reste toujours possible.
    if (!isFollowing.value && _moderation.hides(targetUid.value)) {
      Get.snackbar(
        'Abonnement impossible',
        _moderation.isBlocked(targetUid.value)
            ? 'Débloquez ce compte pour pouvoir le suivre.'
            : 'Vous ne pouvez pas suivre ce compte.',
      );
      return;
    }
    isToggling.value = true;
    try {
      if (isFollowing.value) {
        await _follow.unfollow(_auth.uid, targetUid.value);
      } else {
        await _follow.follow(_auth.uid, targetUid.value);
      }
    } on FirebaseException catch (_) {
      // Erreur réseau ou permissions — le bouton revient à son état
    } finally {
      isToggling.value = false;
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

  Future<void> pickProfilePhoto(ImageSource source) async {
    if (!isOwnProfile || isUploadingPhoto.value) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    isUploadingPhoto.value = true;
    try {
      await _profiles.uploadProfilePhoto(picked.path);
      Get.snackbar(
        'Photo mise à jour',
        'Votre photo de profil a été enregistrée.',
        duration: const Duration(seconds: 3),
      );
    } on FirebaseException catch (e) {
      Get.snackbar(
        'Échec de l’envoi',
        e.message ?? '$e',
        duration: const Duration(seconds: 6),
      );
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<void> removeProfilePhoto() async {
    if (!isOwnProfile || isUploadingPhoto.value) return;
    if (profile.value?.photoUrl == null) return;

    isUploadingPhoto.value = true;
    try {
      await _profiles.removeProfilePhoto();
      Get.snackbar(
        'Photo supprimée',
        'Votre photo de profil a été retirée.',
        duration: const Duration(seconds: 3),
      );
    } on FirebaseException catch (e) {
      Get.snackbar(
        'Suppression impossible',
        e.message ?? '$e',
        duration: const Duration(seconds: 6),
      );
    } finally {
      isUploadingPhoto.value = false;
    }
  }
}
