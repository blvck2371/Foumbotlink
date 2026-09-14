import 'package:flutter/material.dart';

/// Texte replié à [maxLines] avec un « Voir plus » quand il déborde.
///
/// Le lien n'apparaît que si le texte dépasse réellement : on mesure avec
/// un [TextPainter] sous la largeur réelle du parent, plutôt que d'afficher
/// un « Voir plus » inerte sous un texte qui tient déjà.
class ExpandableText extends StatefulWidget {
  const ExpandableText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    this.maxLines = 3,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final int maxLines;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le fil recycle ses cartes : si le texte change sous nos pieds (post
    // modifié, liste réordonnée), on repart replié pour ne pas afficher le
    // corps d'une autre publication déjà déplié.
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        final body = Text(
          widget.text,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          style: widget.style,
        );

        if (!overflows) return body;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: SizedBox(width: double.infinity, child: body),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              // Opaque, sinon le tap traverse jusqu'à la carte et ouvre la
              // publication au lieu de la déplier.
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _expanded ? 'Voir moins' : 'Voir plus',
                  style: widget.style.copyWith(
                    color: widget.linkColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
