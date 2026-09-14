import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/feed_item.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/upload_failure.dart';
import '../services/user_profile_service.dart';

/// Rédaction d'une publication — création, ou édition d'un post existant
/// quand la route reçoit un [FeedItem] en argument (voir
/// `HomeController.editPost`). Les deux modes partagent le même écran :
/// seuls le titre de la page, le libellé du bouton et l'appel final au
/// service changent.
class ComposeController extends GetxController {
  static const _maxImages = 5;

  final postKind = FeedType.info.obs;

  /// Fichiers choisis dans la galerie pendant cette session, pas encore
  /// uploadés.
  final images = <String>[].obs;

  /// En édition : images déjà en ligne que l'auteur a conservées. Retirer
  /// une entrée ici demande sa suppression de Storage à l'enregistrement.
  final existingImageUrls = <String>[].obs;

  final isPublishing = false.obs;
  final _formTick = 0.obs;

  final titleCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();

  /// Post en cours d'édition, `null` en création.
  FeedItem? editing;

  bool get isEditing => editing != null;

  FeedService get _feed => Get.find<FeedService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  bool get canPublishOfficialContent =>
      _profiles.profile.value?.accountType.canPublishOfficialContent ?? false;

  int get totalImages => existingImageUrls.length + images.length;

  bool get canAddImages => totalImages < _maxImages;

  String get screenTitle =>
      isEditing ? 'Modifier la publication' : 'Nouvelle publication';

  String get submitLabel => isEditing ? 'Enregistrer' : 'Publier';

  @override
  void onInit() {
    super.onInit();

    final args = Get.arguments;
    if (args is FeedItem) {
      editing = args;
      postKind.value = args.type;
      titleCtrl.text = args.title;
      bodyCtrl.text = args.body;
      existingImageUrls.assignAll(args.imageUrls);
    }

    titleCtrl.addListener(_bumpFormTick);
    bodyCtrl.addListener(_bumpFormTick);
  }

  void _bumpFormTick() => _formTick.value++;

  /// Le titre est facultatif : une publication peut n'être qu'un message,
  /// ou même que des photos (comme sur Facebook). Il faut simplement
  /// qu'elle porte quelque chose — du texte ou au moins une image —, sans
  /// quoi il n'y a rien à publier.
  bool get canSubmit {
    _formTick.value;
    final hasText =
        bodyCtrl.text.trim().isNotEmpty || titleCtrl.text.trim().isNotEmpty;
    return (hasText || totalImages > 0) && !isPublishing.value;
  }

  /// Vrai si le formulaire diverge du post d'origine — sert à prévenir
  /// avant d'abandonner une édition en cours.
  bool get hasUnsavedChanges {
    final post = editing;
    if (post == null) {
      return titleCtrl.text.trim().isNotEmpty ||
          bodyCtrl.text.trim().isNotEmpty ||
          images.isNotEmpty;
    }
    return titleCtrl.text.trim() != post.title ||
        bodyCtrl.text.trim() != post.body ||
        postKind.value != post.type ||
        images.isNotEmpty ||
        existingImageUrls.length != post.imageUrls.length;
  }

  void selectPostKind(FeedType kind) {
    postKind.value = kind;
  }

  /// Les photos sont redimensionnées et recompressées **à la sélection**,
  /// pas à l'envoi : une photo d'appareil récent pèse plusieurs mégaoctets
  /// et ce poids se paie deux fois — à la publication, puis à chaque
  /// ouverture du fil par chaque habitant, pour une image affichée sur
  /// quelques centaines de pixels. 1600 px et qualité 80 restent nets en
  /// plein écran tout en divisant le poids par cinq à dix, ce qui est le
  /// vrai levier sur le temps de chargement des images.
  Future<void> pickImages() async {
    final remaining = _maxImages - totalImages;
    if (remaining <= 0) return;
    try {
      final picked = await ImagePicker().pickMultiImage(
        limit: remaining,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked.isEmpty) return;
      // `limit` n'est qu'une indication sur certaines galeries Android :
      // on retronque nous-mêmes pour ne jamais dépasser le plafond.
      images.addAll(picked.take(remaining).map((f) => f.path));
    } catch (e) {
      developer.log('Sélection de photos', name: 'ComposeController', error: e);
      _notify('Photos indisponibles', 'Impossible d’ouvrir la galerie.');
    }
  }

  void removeImage(int index) => images.removeAt(index);

  void removeExistingImage(int index) => existingImageUrls.removeAt(index);

  Future<FeedItem?> submit() async {
    if (isPublishing.value) return null;
    isPublishing.value = true;
    try {
      final post = editing;
      if (post != null) {
        return await _feed.updatePost(
          original: post,
          // Le type reste modifiable seulement pour les comptes habilités :
          // un compte citoyen ne doit pas pouvoir requalifier son post en
          // annonce officielle depuis l'écran d'édition.
          type: canPublishOfficialContent ? postKind.value : post.type,
          title: titleCtrl.text,
          body: bodyCtrl.text,
          keptImageUrls: List<String>.from(existingImageUrls),
          newLocalImagePaths: List<String>.from(images),
        );
      }

      final profile = _profiles.profile.value!;
      final official = profile.accountType.canPublishOfficialContent;
      final feedType = official ? postKind.value : FeedType.post;
      final authorSubtitle = official
          ? (postKind.value == FeedType.annonce
                ? 'Annonce officielle'
                : 'Information')
          : profile.authorSubtitle;

      return await _feed.createPost(
        type: feedType,
        title: titleCtrl.text,
        body: bodyCtrl.text,
        authorUid: _auth.uid,
        authorName: profile.displayName,
        authorSubtitle: authorSubtitle,
        authorVerified: profile.verified,
        authorPhotoUrl: profile.photoUrl,
        localImagePaths: images,
      );
    } catch (e) {
      // Sans ce filet, l'échec d'un envoi de photo (droits Storage,
      // coupure réseau) remontait dans le vide : le bouton reprenait son
      // état normal et rien ne disait que la publication n'était pas
      // partie.
      developer.log('Publication', name: 'ComposeController', error: e);
      _notify(
        isEditing ? 'Enregistrement impossible' : 'Publication impossible',
        uploadFailureMessage(e),
      );
      return null;
    } finally {
      isPublishing.value = false;
    }
  }

  void _notify(String title, String message) {
    if (Get.overlayContext == null) return;
    Get.snackbar(title, message, duration: const Duration(seconds: 4));
  }

  @override
  void onClose() {
    titleCtrl.dispose();
    bodyCtrl.dispose();
    super.onClose();
  }
}
