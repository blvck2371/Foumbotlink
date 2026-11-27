import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/feed_item.dart';
import '../models/post_text.dart';
import '../models/video_compression_policy.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/mention_service.dart';
import '../services/upload_failure.dart';
import '../services/user_profile_service.dart';
import '../services/video_compression_service.dart';
import '../utils/local_media.dart';

/// Étape de l'envoi d'une vidéo, affichée sur le bouton.
enum VideoStage { none, compressing, uploading }

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

  /// Plafond d'une vidéo après compression — aligné sur storage.rules.
  static const maxVideoBytes = 60 * 1024 * 1024;

  /// Vidéos par publication. Chacune peut peser jusqu'à
  /// [maxVideoBytes] après réduction : au-delà de trois, l'envoi sur une
  /// connexion mobile devient trop long pour réussir.
  static const maxVideos = 3;

  /// Vidéos choisies dans cette session (fichiers locaux), pas encore
  /// envoyées.
  final newVideos = <LocalVideo>[].obs;

  /// En édition : vidéos déjà publiées que l'auteur garde.
  final existingVideos = <PostVideoItem>[].obs;

  final videoStage = VideoStage.none.obs;
  final videoProgress = 0.0.obs;

  /// Vidéo en cours de réduction ou d'envoi (0 = première), et leur nombre.
  final videoIndex = 0.obs;
  int _videoCount = 0;

  /// @mentions choisies dans les suggestions.
  final mentions = <PostMention>[];

  /// Propositions affichées sous le message pendant qu'on tape « @… ».
  final mentionSuggestions = <MentionSuggestion>[].obs;
  final _mentionService = MentionService();
  Timer? _mentionTimer;
  int _mentionRequest = 0;

  int get totalVideos => existingVideos.length + newVideos.length;

  bool get hasVideo => totalVideos > 0;

  /// Libellé du bouton pendant l'envoi des vidéos : « Envoi de la vidéo
  /// 2/3… 40 % ».
  String get progressLabel {
    final pct = (videoProgress.value * 100).round();
    final which = _videoCount > 1
        ? ' ${videoIndex.value + 1}/$_videoCount'
        : '';
    return switch (videoStage.value) {
      VideoStage.compressing => 'Réduction de la vidéo$which… $pct %',
      VideoStage.uploading => 'Envoi de la vidéo$which… $pct %',
      VideoStage.none => '',
    };
  }

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
      existingVideos.assignAll(args.videos);
      mentions.addAll(args.mentions);
    }

    titleCtrl.addListener(_bumpFormTick);
    bodyCtrl.addListener(_bumpFormTick);
    bodyCtrl.addListener(_onBodyChanged);
  }

  // ---------------------------------------------------------------------
  // @mentions
  // ---------------------------------------------------------------------

  void _onBodyChanged() {
    final sel = bodyCtrl.selection;
    final trigger = sel.isValid && sel.isCollapsed
        ? activeTrigger(bodyCtrl.text, sel.baseOffset)
        : null;
    _mentionTimer?.cancel();
    if (trigger == null || trigger.trigger != '@') {
      _mentionRequest++;
      if (mentionSuggestions.isNotEmpty) mentionSuggestions.clear();
      return;
    }
    _mentionTimer = Timer(const Duration(milliseconds: 200), () async {
      final id = ++_mentionRequest;
      final list = await _mentionService.suggest(
        trigger.query,
        myUid: _auth.isSignedIn ? _auth.uid : null,
      );
      if (id == _mentionRequest) mentionSuggestions.assignAll(list);
    });
  }

  /// Remplace « @jea » par « @Jean Dupont » et retient à qui il renvoie.
  void pickMention(MentionSuggestion s) {
    final text = bodyCtrl.text;
    final cursor = bodyCtrl.selection.baseOffset;
    final trigger = activeTrigger(text, cursor);
    if (trigger == null) return;
    final insert = '${s.mention.token} ';
    final next = text.replaceRange(trigger.start, cursor, insert);
    if (!mentions.contains(s.mention)) mentions.add(s.mention);
    _mentionRequest++;
    mentionSuggestions.clear();
    bodyCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: trigger.start + insert.length,
      ),
    );
  }

  /// Ajoute « @ » au curseur — raccourci pour qui ne connaît pas le geste.
  void insertAt(String symbol) {
    final sel = bodyCtrl.selection;
    final text = bodyCtrl.text;
    final at = sel.isValid ? sel.baseOffset : text.length;
    final needsSpace = at > 0 && text[at - 1].trim().isNotEmpty;
    final insert = '${needsSpace ? ' ' : ''}$symbol';
    bodyCtrl.value = TextEditingValue(
      text: text.replaceRange(at, sel.isValid ? sel.extentOffset : at, insert),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
  }

  // ---------------------------------------------------------------------
  // Vidéo
  // ---------------------------------------------------------------------

  /// Un seul geste pour tout ajouter : la galerie s'ouvre sur les photos
  /// **et** les vidéos, avec sélection multiple. Les photos sont réduites
  /// dès la sélection (1600 px, qualité 80 : nettes en plein écran, cinq à
  /// dix fois plus légères, ce qui se paie à chaque ouverture du fil) ; la
  /// vidéo, elle, n'est réduite qu'à la publication, avec sa progression
  /// affichée — la réduire ici bloquerait l'écran sans explication.
  ///
  /// Une publication porte au plus [_maxImages] photos et une vidéo : le
  /// surplus est écarté avec un message plutôt qu'en silence.
  Future<void> pickMedia() async {
    final roomImages = _maxImages - totalImages;
    final roomVideo = maxVideos - totalVideos;
    final room = roomImages + roomVideo;
    if (room <= 0) {
      _notify(
        'Médias',
        'Maximum $_maxImages photos et $maxVideos vidéos par publication.',
      );
      return;
    }
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultipleMedia(
        limit: room,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      developer.log('Sélection de médias', name: 'ComposeController', error: e);
      _notify('Médias indisponibles', 'Impossible d’ouvrir la galerie.');
      return;
    }
    if (picked.isEmpty) return;

    var skippedImages = 0;
    var skippedVideos = 0;
    for (final file in picked) {
      if (isVideoFile(file)) {
        if (totalVideos >= maxVideos) {
          skippedVideos++;
        } else {
          await _addVideo(file.path);
        }
      } else if (totalImages < _maxImages) {
        images.add(file.path);
      } else {
        skippedImages++;
      }
    }
    if (skippedImages + skippedVideos > 0) {
      _notify(
        'Certains médias n’ont pas été ajoutés',
        'Une publication porte au plus $_maxImages photos et $maxVideos '
            'vidéos.',
      );
    }
  }

  /// Vidéo ou photo ? Le type MIME quand la plateforme le donne (web,
  /// iOS), l'extension sinon (Android rend souvent un simple chemin).
  static bool isVideoFile(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.isNotEmpty) return mime.startsWith('video/');
    return isVideoPath(file.path.isNotEmpty ? file.path : file.name);
  }

  static bool isVideoPath(String path) => RegExp(
    r'\.(mp4|mov|m4v|3gp|3gpp|webm|mkv|avi|qt)$',
    caseSensitive: false,
  ).hasMatch(path);

  Future<void> _addVideo(String path) async {
    try {
      final bytes = await LocalMedia.length(path);
      // Sur le web, pas d'encodeur : ce qui dépasse le plafond ne pourra
      // pas être réduit, inutile de laisser l'auteur attendre l'échec.
      if (kIsWeb && bytes >= maxVideoBytes) {
        _notify(
          'Vidéo trop lourde',
          'Cette vidéo fait ${_mb(bytes)} Mo, le maximum depuis le site est '
              '${_mb(maxVideoBytes)} Mo. Publiez-la depuis l’application : '
              'elle y sera réduite automatiquement.',
        );
        return;
      }
      final (durationMs, aspectRatio) = await _probe(path);
      newVideos.add(
        LocalVideo(
          path: path,
          bytes: bytes,
          durationMs: durationMs,
          aspectRatio: aspectRatio,
          thumbPath: await _thumbnail(path, durationMs),
        ),
      );
    } catch (e) {
      developer.log('Vidéo', name: 'ComposeController', error: e);
      _notify('Vidéo indisponible', 'Impossible d’ouvrir cette vidéo.');
    }
  }

  /// Médias ajoutables encore : le bouton « + » disparaît une fois pleins.
  bool get canAddMedia => totalImages < _maxImages || totalVideos < maxVideos;

  static const maxImages = _maxImages;

  void removeNewVideo(int index) => newVideos.removeAt(index);

  void removeExistingVideo(int index) => existingVideos.removeAt(index);

  /// Les vidéos de plus de 8 Mo seront réduites : on le dit avant
  /// d'envoyer.
  int get videosToReduce => kIsWeb
      ? 0
      : newVideos
            .where(
              (v) => VideoCompressionPolicy.shouldCompress(
                v.bytes,
                threshold: VideoCompressionPolicy.feedCompressAboveBytes,
              ),
            )
            .length;

  /// Durée et format de la vidéo, lus sur le fichier local.
  Future<(int?, double?)> _probe(String path) async {
    final probe = LocalMedia.video(path);
    try {
      await probe.initialize();
      final v = probe.value;
      return (
        v.duration > Duration.zero ? v.duration.inMilliseconds : null,
        v.size.width > 0 && v.size.height > 0
            ? v.size.width / v.size.height
            : null,
      );
    } on Object catch (e) {
      developer.log('Lecture de la vidéo', name: 'ComposeController', error: e);
      return (null, null);
    } finally {
      await probe.dispose();
    }
  }

  /// Image d'aperçu prise à 1 s (la première image d'une vidéo filmée au
  /// téléphone est souvent noire). Pas de vignette sur le web.
  Future<String?> _thumbnail(String path, int? durationMs) async {
    if (kIsWeb) return null;
    try {
      final dir = await getTemporaryDirectory();
      final thumb = await VideoThumbnail.thumbnailFile(
        video: path,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: (durationMs ?? 2000) < 1000 ? 0 : 1000,
        maxWidth: 720,
        quality: 75,
      );
      return thumb.path;
    } on Object catch (e) {
      developer.log('Vignette', name: 'ComposeController', error: e);
      return null;
    }
  }

  /// Réduit au besoin (au-delà de 8 Mo) chaque nouvelle vidéo, l'une
  /// après l'autre, et vérifie le plafond. Les fichiers temporaires sont
  /// ajoutés à [temp] pour être jetés après l'envoi, réussi ou non.
  Future<List<PostVideoDraft>> _prepareVideos(List<PreparedVideo> temp) async {
    final drafts = <PostVideoDraft>[];
    _videoCount = newVideos.length;
    for (var i = 0; i < newVideos.length; i++) {
      final v = newVideos[i];
      videoIndex.value = i;
      videoStage.value = VideoStage.compressing;
      videoProgress.value = 0;
      final prepared = await VideoCompressionService.prepare(
        v.path,
        compressAboveBytes: VideoCompressionPolicy.feedCompressAboveBytes,
        onProgress: (p) => videoProgress.value = p,
      );
      temp.add(prepared);
      if (prepared.bytes >= maxVideoBytes) {
        throw _VideoTooLarge(prepared.bytes, i, newVideos.length);
      }
      drafts.add(
        PostVideoDraft(
          path: prepared.path,
          thumbPath: v.thumbPath,
          durationMs: v.durationMs,
          aspectRatio: v.aspectRatio,
        ),
      );
    }
    return drafts;
  }

  void _onUploadProgress(int index, double p) {
    videoStage.value = VideoStage.uploading;
    videoIndex.value = index;
    videoProgress.value = p;
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  void _bumpFormTick() => _formTick.value++;

  /// Le titre est facultatif : une publication peut n'être qu'un message,
  /// ou même que des photos (comme sur Facebook). Il faut simplement
  /// qu'elle porte quelque chose — du texte ou au moins une image —, sans
  /// quoi il n'y a rien à publier.
  bool get canSubmit {
    _formTick.value;
    final hasText =
        bodyCtrl.text.trim().isNotEmpty || titleCtrl.text.trim().isNotEmpty;
    return (hasText || totalImages > 0 || hasVideo) && !isPublishing.value;
  }

  /// Vrai si le formulaire diverge du post d'origine — sert à prévenir
  /// avant d'abandonner une édition en cours.
  bool get hasUnsavedChanges {
    final post = editing;
    if (post == null) {
      return titleCtrl.text.trim().isNotEmpty ||
          bodyCtrl.text.trim().isNotEmpty ||
          images.isNotEmpty ||
          newVideos.isNotEmpty;
    }
    return titleCtrl.text.trim() != post.title ||
        bodyCtrl.text.trim() != post.body ||
        postKind.value != post.type ||
        images.isNotEmpty ||
        newVideos.isNotEmpty ||
        existingVideos.length != post.videos.length ||
        existingImageUrls.length != post.imageUrls.length;
  }

  void selectPostKind(FeedType kind) {
    postKind.value = kind;
  }

  void removeImage(int index) => images.removeAt(index);

  void removeExistingImage(int index) => existingImageUrls.removeAt(index);

  Future<FeedItem?> submit() async {
    if (isPublishing.value) return null;
    isPublishing.value = true;
    final temp = <PreparedVideo>[];
    try {
      final videos = await _prepareVideos(temp);
      if (videos.isNotEmpty) _onUploadProgress(0, 0);
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
          keptVideos: List<PostVideoItem>.from(existingVideos),
          newVideos: videos,
          mentions: mentions,
          onVideoProgress: _onUploadProgress,
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
        videos: videos,
        mentions: mentions,
        onVideoProgress: _onUploadProgress,
      );
    } on _VideoTooLarge catch (e) {
      _notify(
        'Vidéo trop longue',
        '${e.total > 1 ? 'La vidéo ${e.index + 1}' : 'La vidéo'} fait '
            'encore ${_mb(e.bytes)} Mo une fois réduite (maximum '
            '${_mb(maxVideoBytes)} Mo). Coupez-la avant de la publier.',
      );
      return null;
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
      for (final t in temp) {
        await t.discard();
      }
      videoStage.value = VideoStage.none;
      isPublishing.value = false;
    }
  }

  void _notify(String title, String message) {
    if (Get.overlayContext == null) return;
    Get.snackbar(title, message, duration: const Duration(seconds: 4));
  }

  @override
  void onClose() {
    _mentionTimer?.cancel();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    super.onClose();
  }
}

class _VideoTooLarge implements Exception {
  const _VideoTooLarge(this.bytes, this.index, this.total);
  final int bytes;
  final int index;
  final int total;
}

/// Vidéo choisie dans la galerie, pas encore envoyée.
class LocalVideo {
  const LocalVideo({
    required this.path,
    required this.bytes,
    this.thumbPath,
    this.durationMs,
    this.aspectRatio,
  });

  final String path;
  final int bytes;
  final String? thumbPath;
  final int? durationMs;
  final double? aspectRatio;

  String get durationLabel => PostVideoItem(
    url: path,
    durationMs: durationMs,
  ).durationLabel;
}
