import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/home_controller.dart';
import '../models/feed_item.dart';
import '../theme/app_colors.dart';

enum _PostAction {
  edit,
  delete,
  toggleComments,
  save,
  repost,
  share,
  report,
  block,
}

/// Menu « … » d'une publication. Les entrées dépendent de qui regarde :
/// l'auteur peut modifier, supprimer et fermer les commentaires ; les
/// autres peuvent signaler le contenu ou bloquer l'auteur. Le partage est
/// ouvert à tous.
///
/// Le menu pilote directement [HomeController] : le fil, l'écran de détail
/// et le profil affichent les mêmes publications et doivent réagir de la
/// même façon, sans que chacun recâble les six actions.
class PostActionsMenu extends StatelessWidget {
  const PostActionsMenu({
    super.key,
    required this.post,
    required this.isDark,
    this.iconSize = 20,
  });

  final FeedItem post;
  final bool isDark;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final isAuthor = home.isMyPost(post);
    // Lu à l'ouverture du menu, pas dans un `Obx` : le menu est reconstruit
    // à chaque appui sur « … », il ne reste jamais affiché assez longtemps
    // pour que l'état change sous lui.
    final saved = home.isSavedByMe(post.id);

    return PopupMenuButton<_PostAction>(
      tooltip: 'Options',
      icon: Icon(Icons.more_horiz, size: iconSize, color: muted),
      color: isDark ? AppColors.blackElevated : AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: PopupMenuPosition.under,
      onSelected: (action) => switch (action) {
        _PostAction.edit => home.editPost(post),
        _PostAction.delete => home.deletePost(post),
        _PostAction.toggleComments => home.toggleComments(post),
        _PostAction.save => home.toggleSave(post),
        _PostAction.repost => home.repostPost(post),
        _PostAction.share => home.sharePost(post),
        _PostAction.report => home.reportPost(post),
        _PostAction.block => home.blockAuthor(
            authorUid: post.authorUid,
            authorName: post.authorName,
          ),
      },
      itemBuilder: (context) => [
        if (isAuthor) ...[
          _item(
            _PostAction.edit,
            Icons.edit_outlined,
            'Modifier',
            ink,
          ),
          _item(
            _PostAction.toggleComments,
            post.commentsDisabled
                ? Icons.chat_bubble_outline
                : Icons.speaker_notes_off_outlined,
            post.commentsDisabled
                ? 'Rouvrir les commentaires'
                : 'Fermer les commentaires',
            ink,
          ),
        ],
        _item(
          _PostAction.save,
          saved ? Icons.bookmark : Icons.bookmark_border,
          saved ? 'Retirer des enregistrements' : 'Enregistrer',
          saved ? AppColors.orange : ink,
        ),
        _item(_PostAction.repost, Icons.repeat_rounded, 'Republier', ink),
        _item(_PostAction.share, Icons.share_outlined, 'Partager', ink),
        if (isAuthor)
          _item(
            _PostAction.delete,
            Icons.delete_outline,
            'Supprimer',
            AppColors.orange,
          )
        else ...[
          _item(
            _PostAction.report,
            Icons.flag_outlined,
            'Signaler',
            AppColors.orange,
          ),
          if (post.authorUid.isNotEmpty)
            _item(
              _PostAction.block,
              Icons.block,
              'Bloquer ${post.authorName}',
              AppColors.orange,
            ),
        ],
      ],
    );
  }

  PopupMenuItem<_PostAction> _item(
    _PostAction value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<_PostAction>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CommentAction { edit, delete, report }

/// Menu « … » d'un commentaire — mêmes principes que [PostActionsMenu].
/// [onEdit] est fourni par l'écran, qui seul sait ouvrir le champ de
/// saisie en mode édition.
class CommentActionsMenu extends StatelessWidget {
  const CommentActionsMenu({
    super.key,
    required this.postId,
    required this.comment,
    required this.isDark,
    required this.onEdit,
  });

  final String postId;
  final FeedComment comment;
  final bool isDark;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final isAuthor = home.isMyComment(comment);

    // Un commentaire déjà supprimé n'a plus d'action possible : il ne
    // subsiste que pour porter ses réponses.
    if (comment.deleted) return const SizedBox.shrink();

    return PopupMenuButton<_CommentAction>(
      tooltip: 'Options du commentaire',
      icon: Icon(Icons.more_horiz, size: 16, color: muted),
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: isDark ? AppColors.blackElevated : AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: PopupMenuPosition.under,
      onSelected: (action) => switch (action) {
        _CommentAction.edit => onEdit(),
        _CommentAction.delete => home.deleteComment(postId, comment),
        _CommentAction.report => home.reportComment(postId, comment),
      },
      itemBuilder: (context) => [
        if (isAuthor) ...[
          PopupMenuItem(
            value: _CommentAction.edit,
            height: 42,
            child: _row(Icons.edit_outlined, 'Modifier', ink),
          ),
          PopupMenuItem(
            value: _CommentAction.delete,
            height: 42,
            child: _row(Icons.delete_outline, 'Supprimer', AppColors.orange),
          ),
        ] else
          PopupMenuItem(
            value: _CommentAction.report,
            height: 42,
            child: _row(Icons.flag_outlined, 'Signaler', AppColors.orange),
          ),
      ],
    );
  }

  Widget _row(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
