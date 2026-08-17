import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/home_controller.dart';
import '../../models/feed_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';

class FeedPostScreen extends StatefulWidget {
  const FeedPostScreen({super.key});

  @override
  State<FeedPostScreen> createState() => _FeedPostScreenState();
}

class _FeedPostScreenState extends State<FeedPostScreen> {
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  final _home = Get.find<HomeController>();
  late String _postId;
  String? _replyToCommentId;
  String? _replyToAuthorName;
  final Set<String> _expandedReplies = {};

  @override
  void initState() {
    super.initState();
    _postId = Get.arguments as String;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  FeedItem? get _post => _home.feedService.getById(_postId);

  void _refresh() => setState(() {});

  void _toggleReplies(String commentId) {
    setState(() {
      if (_expandedReplies.contains(commentId)) {
        _expandedReplies.remove(commentId);
      } else {
        _expandedReplies.add(commentId);
      }
    });
  }

  void _expandReplies(String commentId) {
    setState(() => _expandedReplies.add(commentId));
  }

  void _startReply(FeedComment comment) {
    setState(() {
      _replyToCommentId = comment.id;
      _replyToAuthorName = comment.authorName;
      // Déplie déjà le fil qu'on prolonge, pour voir la réponse arriver.
      _expandedReplies.add(comment.id);
    });
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToAuthorName = null;
    });
  }

  void _submitComment() {
    final text = _commentCtrl.text;
    if (text.trim().isEmpty) return;
    final parentId = _replyToCommentId;
    _home.addComment(
      _postId,
      text,
      parentCommentId: parentId,
    );
    _commentCtrl.clear();
    if (parentId != null) {
      _expandReplies(parentId);
    }
    _refresh();
    _cancelReply();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final textTheme = Theme.of(context).textTheme;

    return Obx(() {
      final isDark = themeController.isDarkMode;
      _home.feedTick.value;
      final post = _post;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      if (post == null) {
        return Scaffold(
          backgroundColor: isDark ? AppColors.black : AppColors.white,
          appBar: FoumbotAppBar(isDark: isDark, title: 'Publication'),
          body: Center(
            child: Text(
              'Publication introuvable',
              style: GoogleFonts.manrope(
                color: isDark ? AppColors.whiteMuted : AppColors.gray,
              ),
            ),
          ),
        );
      }

      final badgeColor = switch (post.type) {
        FeedType.annonce => AppColors.red,
        FeedType.info => AppColors.blue,
        FeedType.post => AppColors.blue,
      };

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: post.typeLabel,
          actions: [
            IconButton(
              tooltip: 'Thème',
              onPressed: themeController.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      AppColors.black,
                      AppColors.blackSoft,
                      AppColors.blackElevated,
                    ]
                  : const [
                      AppColors.white,
                      AppColors.whiteSoft,
                      AppColors.white,
                    ],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: badgeColor.withValues(alpha: 0.15),
                          child: Text(
                            post.authorName.isNotEmpty
                                ? post.authorName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.authorName,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              Text(
                                '${post.authorSubtitle} · ${_home.timeAgo(post.publishedAt)}',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            post.typeLabel.toUpperCase(),
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      post.title,
                      style: textTheme.headlineMedium?.copyWith(
                        color: ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      post.body,
                      style: textTheme.bodyLarge?.copyWith(
                        color: muted,
                        height: 1.5,
                      ),
                    ),
                    if (post.hasImages) ...[
                      const SizedBox(height: 14),
                      FeedImageCarousel(
                        imageUrls: post.imageUrls,
                        isDark: isDark,
                        borderRadius: 16,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      '${post.likesCount} J’aime · ${post.commentsCount} commentaires',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: muted,
                      ),
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: post.likedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: 'J’aime',
                            color: post.likedByMe
                                ? AppColors.red
                                : (isDark
                                    ? AppColors.white
                                    : AppColors.black),
                            onTap: () {
                              _home.toggleLike(post.id);
                              _refresh();
                            },
                          ),
                        ),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.chat_bubble_outline,
                            label: 'Commenter',
                            color: isDark ? AppColors.white : AppColors.black,
                            onTap: () => _commentFocus.requestFocus(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Commentaires',
                      style: textTheme.titleLarge?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 12),
                    if (post.comments.isEmpty)
                      Text(
                        'Soyez le premier à commenter.',
                        style: GoogleFonts.manrope(color: muted),
                      )
                    else
                      ...post.comments.map(
                        (c) => _CommentNode(
                          comment: c,
                          depth: 0,
                          isDark: isDark,
                          ink: ink,
                          muted: muted,
                          timeAgo: _home.timeAgo,
                          expandedIds: _expandedReplies,
                          onToggleReplies: _toggleReplies,
                          onLike: (commentId) {
                            _home.toggleCommentLike(_postId, commentId);
                          },
                          onReply: _startReply,
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.blackSoft : AppColors.white,
                    border: Border(
                      top: BorderSide(
                        color: ink.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_replyToAuthorName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Réponse à $_replyToAuthorName',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: _cancelReply,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentCtrl,
                              focusNode: _commentFocus,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submitComment(),
                              decoration: InputDecoration(
                                hintText: _replyToAuthorName != null
                                    ? 'Répondre à $_replyToAuthorName…'
                                    : 'Écrire un commentaire…',
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.blackElevated
                                    : AppColors.whiteSoft,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _submitComment,
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: AppColors.white,
                            ),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Un nœud du fil de commentaires, à profondeur illimitée : il se
/// dessine lui-même puis, si des réponses existent et sont dépliées,
/// dessine récursivement chacune de ses réponses en dessous, légèrement
/// indentées — comme un fil de commentaires TikTok/Reddit.
class _CommentNode extends StatelessWidget {
  const _CommentNode({
    required this.comment,
    required this.depth,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.timeAgo,
    required this.expandedIds,
    required this.onToggleReplies,
    required this.onLike,
    required this.onReply,
  });

  final FeedComment comment;
  final int depth;
  final bool isDark;
  final Color ink;
  final Color muted;
  final String Function(DateTime) timeAgo;
  final Set<String> expandedIds;
  final void Function(String commentId) onToggleReplies;
  final void Function(String commentId) onLike;
  final void Function(FeedComment comment) onReply;

  static const double _rootAvatar = 36;
  static const double _replyAvatar = 28;
  static const double _lineWidth = 2;
  // Au-delà de cette profondeur, l'indentation cesse d'augmenter pour ne
  // pas écraser le texte — le fil reste logiquement illimité, seul
  // l'affichage se stabilise (comme sur Instagram/Reddit).
  static const int _maxIndentDepth = 4;

  double get _avatarSize => depth == 0 ? _rootAvatar : _replyAvatar;

  @override
  Widget build(BuildContext context) {
    final lineColor = ink.withValues(alpha: isDark ? 0.28 : 0.16);
    final replies = comment.replies;
    final replyCount = replies.length;
    final isExpanded = expandedIds.contains(comment.id);
    final avatarSize = _avatarSize;

    return Padding(
      padding: EdgeInsets.only(bottom: depth == 0 ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: avatarSize / 2,
                backgroundColor: AppColors.blue.withValues(alpha: 0.15),
                child: Text(
                  comment.authorName.isNotEmpty
                      ? comment.authorName[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.manrope(
                    fontSize: depth == 0 ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CommentBody(
                  comment: comment,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  timeAgo: timeAgo,
                  onLike: onLike,
                  onReply: onReply,
                ),
              ),
            ],
          ),
          if (replyCount > 0) ...[
            Padding(
              padding: EdgeInsets.only(left: avatarSize + 10, top: 4),
              child: InkWell(
                onTap: () => onToggleReplies(comment.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    isExpanded
                        ? 'Masquer les réponses'
                        : replyCount == 1
                            ? 'Voir 1 réponse'
                            : 'Voir $replyCount réponses',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding:
                    EdgeInsets.only(left: (avatarSize - _lineWidth) / 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: lineColor, width: _lineWidth),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: depth < _maxIndentDepth ? 18 : 10,
                      top: 10,
                    ),
                    child: Column(
                      children: [
                        for (final reply in replies)
                          _CommentNode(
                            comment: reply,
                            depth: depth + 1,
                            isDark: isDark,
                            ink: ink,
                            muted: muted,
                            timeAgo: timeAgo,
                            expandedIds: expandedIds,
                            onToggleReplies: onToggleReplies,
                            onLike: onLike,
                            onReply: onReply,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommentBody extends StatelessWidget {
  const _CommentBody({
    required this.comment,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.timeAgo,
    required this.onLike,
    required this.onReply,
  });

  final FeedComment comment;
  final bool isDark;
  final Color ink;
  final Color muted;
  final String Function(DateTime) timeAgo;
  final void Function(String commentId) onLike;
  final void Function(FeedComment comment) onReply;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comment.authorName,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: ink,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    if (comment.replyToName != null) ...[
                      TextSpan(
                        text: '@${comment.replyToName} ',
                        style: GoogleFonts.manrope(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                    TextSpan(
                      text: comment.text,
                      style: GoogleFonts.manrope(
                        color: muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Text(
                timeAgo(comment.createdAt),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: muted,
                ),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () => onLike(comment.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        comment.likedByMe
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 14,
                        color: comment.likedByMe ? AppColors.red : muted,
                      ),
                      if (comment.likesCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${comment.likesCount}',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: comment.likedByMe ? AppColors.red : muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: () => onReply(comment),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Text(
                    'Répondre',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
