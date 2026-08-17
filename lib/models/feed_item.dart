enum FeedType { info, annonce, post }

enum FeedFilter { all, infos, annonces, population }

/// Commentaire d'un fil imbriqué à profondeur illimitée (façon TikTok) :
/// chaque commentaire — racine ou réponse — porte sa propre liste de
/// réponses, elles-mêmes rattachables à d'autres réponses.
class FeedComment {
  FeedComment({
    required this.id,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.likesCount = 0,
    this.likedByMe = false,
    this.replyToName,
    List<FeedComment>? replies,
  }) : replies = replies ?? [];

  final String id;
  final String authorName;
  final String text;
  final DateTime createdAt;
  /// Auteur du commentaire parent direct — affiché en préfixe `@Nom`
  /// quand ce commentaire est lui-même une réponse.
  final String? replyToName;
  int likesCount;
  bool likedByMe;
  final List<FeedComment> replies;

  /// Nombre total de réponses en dessous de ce commentaire, à toute
  /// profondeur.
  int get totalReplyCount {
    var total = replies.length;
    for (final reply in replies) {
      total += reply.totalReplyCount;
    }
    return total;
  }

  FeedComment copyWith({
    int? likesCount,
    bool? likedByMe,
    String? replyToName,
    List<FeedComment>? replies,
  }) {
    return FeedComment(
      id: id,
      authorName: authorName,
      text: text,
      createdAt: createdAt,
      replyToName: replyToName ?? this.replyToName,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
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
    required this.authorName,
    required this.authorSubtitle,
    required this.publishedAt,
    this.likesCount = 0,
    this.likedByMe = false,
    List<String>? imageUrls,
    List<FeedComment>? comments,
  }) : imageUrls = imageUrls ?? [],
       comments = comments ?? [];

  final String id;
  final FeedType type;
  final String title;
  final String body;
  final String authorName;
  final String authorSubtitle;
  final DateTime publishedAt;
  int likesCount;
  bool likedByMe;
  /// Photos jointes à la publication, dans l'ordre d'affichage. Vide pour
  /// une publication uniquement textuelle.
  final List<String> imageUrls;
  final List<FeedComment> comments;

  bool get hasImages => imageUrls.isNotEmpty;

  String get typeLabel => switch (type) {
        FeedType.annonce => 'Annonce',
        FeedType.info => 'Info',
        FeedType.post => 'Publication',
      };

  int get commentsCount {
    var total = comments.length;
    for (final c in comments) {
      total += c.totalReplyCount;
    }
    return total;
  }

  FeedItem copyWith({
    int? likesCount,
    bool? likedByMe,
    List<FeedComment>? comments,
  }) {
    return FeedItem(
      id: id,
      type: type,
      title: title,
      body: body,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      publishedAt: publishedAt,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      imageUrls: imageUrls,
      comments: comments ?? List<FeedComment>.from(this.comments),
    );
  }
}
