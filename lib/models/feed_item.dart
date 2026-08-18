enum FeedType { info, annonce, post }

enum FeedFilter { all, infos, annonces, population, venteAchat }

class FeedComment {
  FeedComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
    this.replyToName,
    this.likesCount = 0,
    this.likedByMe = false,
    List<FeedComment>? replies,
  }) : replies = replies ?? [];

  final String id;
  final String authorUid;
  final String authorName;
  final String text;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? replyToName;
  final int likesCount;
  final bool likedByMe;
  final List<FeedComment> replies;

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
      authorUid: authorUid,
      authorName: authorName,
      text: text,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
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
    required this.authorUid,
    required this.authorName,
    required this.authorSubtitle,
    required this.publishedAt,
    this.likesCount = 0,
    this.likedByMe = false,
    this.commentsCount = 0,
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
  final int likesCount;
  final bool likedByMe;
  final int commentsCount;
  final List<String> imageUrls;
  final List<FeedComment> comments;

  bool get hasImages => imageUrls.isNotEmpty;

  String get typeLabel => switch (type) {
        FeedType.annonce => 'Annonce',
        FeedType.info => 'Info',
        FeedType.post => 'Publication',
      };

  FeedItem copyWith({
    int? likesCount,
    bool? likedByMe,
    int? commentsCount,
    List<FeedComment>? comments,
  }) {
    return FeedItem(
      id: id,
      type: type,
      title: title,
      body: body,
      authorUid: authorUid,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      publishedAt: publishedAt,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      imageUrls: imageUrls,
      comments: comments ?? List<FeedComment>.from(this.comments),
    );
  }
}
