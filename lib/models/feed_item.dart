import 'post_text.dart';

enum FeedType { info, annonce, post }

enum FeedFilter { all, population, venteAchat }

class FeedComment {
  FeedComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.authorPhotoUrl,
    this.parentCommentId,
    this.replyToName,
    this.likesCount = 0,
    this.likedByMe = false,
    this.editedAt,
    this.deleted = false,
    List<FeedComment>? replies,
  }) : replies = replies ?? [];

  final String id;
  final String authorUid;
  final String authorName;

  /// Photo de profil de l'auteur, dénormalisée sur le commentaire comme
  /// l'est déjà [authorName] — `null` sur les commentaires écrits avant
  /// ce champ, et l'UI retombe alors sur les initiales.
  final String? authorPhotoUrl;

  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToName;
  final int likesCount;
  final bool likedByMe;

  /// Date de la dernière modification par l'auteur — `null` si jamais
  /// édité. Sert à afficher la mention « modifié ».
  final DateTime? editedAt;

  /// Suppression douce : un commentaire qui porte des réponses ne peut pas
  /// être effacé sans faire disparaître tout son sous-arbre (les réponses
  /// sont rattachées par `parentCommentId` — voir `_buildTree`). On le
  /// vide donc de son contenu et on l'affiche « Commentaire supprimé »,
  /// ce qui préserve le fil de discussion.
  final bool deleted;

  final List<FeedComment> replies;

  bool get isEdited => editedAt != null;

  int get totalReplyCount {
    var total = replies.length;
    for (final reply in replies) {
      total += reply.totalReplyCount;
    }
    return total;
  }

  FeedComment copyWith({
    String? text,
    int? likesCount,
    bool? likedByMe,
    String? replyToName,
    DateTime? editedAt,
    bool? deleted,
    List<FeedComment>? replies,
  }) {
    return FeedComment(
      id: id,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      text: text ?? this.text,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
      replyToName: replyToName ?? this.replyToName,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      editedAt: editedAt ?? this.editedAt,
      deleted: deleted ?? this.deleted,
      replies: replies ?? List<FeedComment>.from(this.replies),
    );
  }
}

class FeedItem {
  FeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.authorUid,
    required this.authorName,
    required this.authorSubtitle,
    required this.publishedAt,
    this.authorVerified = false,
    this.authorPhotoUrl,
    this.repostOfId,
    this.repostOfAuthorUid,
    this.repostOfAuthorName,
    this.repostOfAuthorPhotoUrl,
    this.likesCount = 0,
    this.likedByMe = false,
    this.commentsCount = 0,
    this.editedAt,
    this.commentsDisabled = false,
    this.hidden = false,
    this.videos = const [],
    this.mentions = const [],
    this.hashtags = const [],
    List<String>? imageUrls,
    List<FeedComment>? comments,
  }) : imageUrls = imageUrls ?? [],
       comments = comments ?? [];

  final String id;
  final FeedType type;
  final String title;
  final String body;
  final String authorUid;
  final String authorName;
  final String authorSubtitle;
  final DateTime publishedAt;
  final bool authorVerified;
  final String? authorPhotoUrl;
  final String? repostOfId;
  final String? repostOfAuthorUid;
  final String? repostOfAuthorName;
  final String? repostOfAuthorPhotoUrl;
  final int likesCount;
  final bool likedByMe;
  final int commentsCount;

  /// Date de la dernière modification par l'auteur — `null` si jamais
  /// édité. Sert à afficher « · modifié » à côté de l'horodatage.
  final DateTime? editedAt;

  /// L'auteur a fermé les commentaires sur cette publication.
  final bool commentsDisabled;

  /// Masqué automatiquement après avoir dépassé le seuil de signalements
  /// (voir `onReportCreated` dans functions/index.js). Le document reste
  /// en base pour la modération, mais n'est plus servi au fil.
  final bool hidden;

  final List<String> imageUrls;
  final List<FeedComment> comments;

  /// Vidéos de la publication, dans l'ordre (réduites avant l'envoi
  /// au-delà de 8 Mo).
  final List<PostVideoItem> videos;

  PostVideoItem? get _firstVideo => videos.isEmpty ? null : videos.first;

  /// Première vidéo — sert de vignette (grille du profil, recherche).
  String? get videoUrl => _firstVideo?.url;
  String? get videoThumbUrl => _firstVideo?.thumbUrl;
  int? get videoDurationMs => _firstVideo?.durationMs;
  double? get videoAspectRatio => _firstVideo?.aspectRatio;

  /// À qui renvoie chaque « @Nom » du message.
  final List<PostMention> mentions;

  /// Hashtags du message, normalisés (`fete_foumbot`) — recherchables.
  final List<String> hashtags;

  bool get hasImages => imageUrls.isNotEmpty;

  bool get hasVideo => videos.isNotEmpty;

  /// « 1:05 » pour la première vidéo, ou vide si la durée est inconnue.
  String get videoDurationLabel => _firstVideo?.durationLabel ?? '';

  /// Le titre est facultatif (voir `ComposeController.canSubmit`) : une
  /// publication peut n'être qu'un message, ou que des photos. Les écrans
  /// doivent donc décider d'afficher le bloc titre plutôt que rendre une
  /// chaîne vide, qui laisserait une ligne creuse dans la carte.
  bool get hasTitle => title.trim().isNotEmpty;

  bool get hasBody => body.trim().isNotEmpty;

  bool get isRepost => repostOfId != null && repostOfId!.isNotEmpty;

  bool get isEdited => editedAt != null;

  String get typeLabel => switch (type) {
    FeedType.annonce => 'Annonce',
    FeedType.info => 'Info',
    FeedType.post => 'Publication',
  };

  /// Texte partagé via la feuille de partage native. Titre et message
  /// peuvent être vides l'un ou l'autre — on ne partage que ce qui existe,
  /// sans lignes vides en tête.
  String get shareText {
    final buffer = StringBuffer();
    if (hasTitle) buffer.writeln('${title.trim()}\n');
    if (hasBody) buffer.writeln('${body.trim()}\n');
    buffer.write('Publié par $authorName sur Foumbot Link');
    return buffer.toString();
  }

  /// Résumé d'une ligne pour les endroits qui ne peuvent pas afficher la
  /// publication entière (notifications, aperçu de republication) : le
  /// titre s'il existe, sinon le début du message, sinon la mention des
  /// photos — jamais une chaîne vide.
  String get summaryLine {
    if (hasTitle) return title.trim();
    if (hasBody) return body.trim();
    if (hasVideo) return videos.length > 1 ? '${videos.length} vidéos' : 'Vidéo';
    return imageUrls.length > 1 ? '${imageUrls.length} photos' : 'Photo';
  }

  FeedItem copyWith({
    FeedType? type,
    String? title,
    String? body,
    bool? authorVerified,
    int? likesCount,
    bool? likedByMe,
    int? commentsCount,
    DateTime? editedAt,
    bool? commentsDisabled,
    bool? hidden,
    List<String>? imageUrls,
    List<FeedComment>? comments,
    List<PostVideoItem>? videos,
    List<PostMention>? mentions,
    List<String>? hashtags,
  }) {
    return FeedItem(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      authorUid: authorUid,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      publishedAt: publishedAt,
      authorVerified: authorVerified ?? this.authorVerified,
      authorPhotoUrl: authorPhotoUrl,
      repostOfId: repostOfId,
      repostOfAuthorUid: repostOfAuthorUid,
      repostOfAuthorName: repostOfAuthorName,
      repostOfAuthorPhotoUrl: repostOfAuthorPhotoUrl,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      editedAt: editedAt ?? this.editedAt,
      commentsDisabled: commentsDisabled ?? this.commentsDisabled,
      hidden: hidden ?? this.hidden,
      imageUrls: imageUrls ?? this.imageUrls,
      comments: comments ?? List<FeedComment>.from(this.comments),
      videos: videos ?? this.videos,
      mentions: mentions ?? this.mentions,
      hashtags: hashtags ?? this.hashtags,
    );
  }
}

/// Une vidéo d'une publication.
class PostVideoItem {
  const PostVideoItem({
    required this.url,
    this.thumbUrl,
    this.durationMs,
    this.aspectRatio,
  });

  final String url;

  /// Image d'aperçu — absente sur le web, où le navigateur ne sait pas
  /// l'extraire ; la carte affiche alors une tuile sombre.
  final String? thumbUrl;
  final int? durationMs;

  /// Largeur / hauteur, pour réserver la bonne place avant la lecture.
  final double? aspectRatio;

  /// « 1:05 », ou vide si la durée est inconnue.
  String get durationLabel {
    final ms = durationMs;
    if (ms == null || ms <= 0) return '';
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  factory PostVideoItem.fromMap(Map<String, dynamic> m) => PostVideoItem(
    url: m['url'] as String? ?? '',
    thumbUrl: m['thumbUrl'] as String?,
    durationMs: (m['durationMs'] as num?)?.toInt(),
    aspectRatio: (m['aspectRatio'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'url': url,
    'thumbUrl': thumbUrl,
    'durationMs': durationMs,
    'aspectRatio': aspectRatio,
  };

  /// Lit les vidéos d'un document : la liste `videos`, ou à défaut
  /// l'ancien format à une seule vidéo (`videoUrl`, …) des publications
  /// faites avant les vidéos multiples.
  static List<PostVideoItem> listFromDoc(Map<String, dynamic> d) {
    final raw = d['videos'];
    if (raw is List && raw.isNotEmpty) {
      return [
        for (final v in raw)
          if (v is Map)
            PostVideoItem.fromMap(Map<String, dynamic>.from(v)),
      ].where((v) => v.url.isNotEmpty).toList();
    }
    final url = d['videoUrl'];
    if (url is String && url.isNotEmpty) {
      return [
        PostVideoItem(
          url: url,
          thumbUrl: d['videoThumbUrl'] as String?,
          durationMs: (d['videoDurationMs'] as num?)?.toInt(),
          aspectRatio: (d['videoAspectRatio'] as num?)?.toDouble(),
        ),
      ];
    }
    return const [];
  }

  /// Champs écrits dans le document : la liste, plus la première vidéo
  /// dans l'ancien format — une version de l'app installée avant les
  /// vidéos multiples affiche ainsi au moins celle-là.
  static Map<String, dynamic> docFields(List<PostVideoItem> videos) {
    if (videos.isEmpty) return const {'videos': <Object>[]};
    final first = videos.first;
    return {
      'videos': [for (final v in videos) v.toMap()],
      'videoUrl': first.url,
      'videoThumbUrl': first.thumbUrl,
      'videoDurationMs': first.durationMs,
      'videoAspectRatio': first.aspectRatio,
    };
  }
}
