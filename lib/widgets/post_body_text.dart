import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/search_controller.dart';
import '../models/post_text.dart';
import '../routes/app_routes.dart';
import 'expandable_text.dart';

/// Ouvre ce qu'une @mention désigne : le profil d'un compte (habitant ou
/// structure), ou la fiche d'un professionnel de l'annuaire.
void openMention(PostMention m) {
  if (m.id.isEmpty) return;
  switch (m.kind) {
    case MentionKind.user:
      Get.toNamed(AppRoutes.userProfile, arguments: m.id,
          preventDuplicates: false);
    case MentionKind.pro:
      Get.toNamed(AppRoutes.directoryDetail, arguments: m.id,
          preventDuplicates: false);
  }
}

/// Un hashtag est une recherche : il ouvre les publications qui le portent.
///
/// Si la recherche est déjà ouverte plus bas dans la pile (on vient d'un
/// résultat), on y revient plutôt que d'empiler un second écran qui
/// partagerait le même contrôleur.
void openHashtag(String tag) {
  if (Get.isRegistered<AppSearchController>()) {
    Get.until((route) => route.settings.name == AppRoutes.search);
    final c = Get.find<AppSearchController>();
    c.tab.value = SearchTab.posts;
    c.useRecent('#$tag');
    return;
  }
  Get.toNamed(AppRoutes.search, arguments: '#$tag');
}

/// Message d'une publication avec @mentions et #hashtags cliquables.
class PostBodyText extends StatefulWidget {
  const PostBodyText({
    super.key,
    required this.text,
    required this.mentions,
    required this.style,
    required this.linkColor,
    this.maxLines,
    this.expandable = true,
  });

  final String text;
  final List<PostMention> mentions;
  final TextStyle style;
  final Color linkColor;

  /// Avec [expandable] : lignes avant « Voir plus ». Sans : coupe nette.
  final int? maxLines;
  final bool expandable;

  @override
  State<PostBodyText> createState() => _PostBodyTextState();
}

class _PostBodyTextState extends State<PostBodyText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _span() {
    _disposeRecognizers();
    final link = widget.style.copyWith(
      color: widget.linkColor,
      fontWeight: FontWeight.w700,
    );
    return TextSpan(
      children: [
        for (final part in splitPostText(widget.text, widget.mentions))
          switch (part) {
            PlainPart() => TextSpan(text: part.text),
            MentionPart(:final mention) => TextSpan(
              text: part.text,
              style: link,
              recognizer: _tap(() => openMention(mention)),
            ),
            HashtagPart(:final tag) => TextSpan(
              text: part.text,
              style: link,
              recognizer: _tap(() => openHashtag(tag)),
            ),
          },
      ],
    );
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final span = _span();
    if (widget.expandable) {
      return ExpandableText(
        text: widget.text,
        span: span,
        style: widget.style,
        linkColor: widget.linkColor,
        maxLines: widget.maxLines ?? 3,
      );
    }
    return Text.rich(
      span,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
