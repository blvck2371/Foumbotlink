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
    List<String>? imageUrls,
    List<FeedComment>? comments,
  })  : imageUrls = imageUrls ?? [],
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

  bool get hasImages => imageUrls.isNotEmpty;

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
    return imageUrls.length > 1
        ? '${imageUrls.length} photos'
        : 'Photo';
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
    );
  }
}
