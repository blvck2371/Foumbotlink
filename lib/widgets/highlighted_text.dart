import 'package:flutter/material.dart';

import '../models/search_text.dart';

/// Texte dont les mots qui répondent à la recherche sont mis en valeur —
/// accents et majuscules confondus : « eco » souligne « École ».
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.tokens,
    required this.style,
    required this.highlight,
    this.maxLines = 1,
  });

  final String text;
  final List<String> tokens;
  final TextStyle style;
  final TextStyle highlight;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: spans(text, tokens, style, highlight)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  static final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Découpe [text] en morceaux normaux et mis en valeur.
  static List<TextSpan> spans(
    String text,
    List<String> tokens,
    TextStyle style,
    TextStyle highlight,
  ) {
    if (tokens.isEmpty) return [TextSpan(text: text, style: style)];
    final out = <TextSpan>[];
    final chars = text.characters.toList();
    var plain = StringBuffer();
    var i = 0;
    while (i < chars.length) {
      if (!_wordChar.hasMatch(chars[i])) {
        plain.write(chars[i]);
        i++;
        continue;
      }
      var end = i;
      while (end < chars.length && _wordChar.hasMatch(chars[end])) {
        end++;
      }
      final word = chars.sublist(i, end);
      final lit = _litLength(word, tokens);
      if (lit > 0) {
        if (plain.isNotEmpty) {
          out.add(TextSpan(text: plain.toString(), style: style));
          plain = StringBuffer();
        }
        out.add(TextSpan(text: word.take(lit).join(), style: highlight));
        plain.write(word.skip(lit).join());
      } else {
        plain.write(word.join());
      }
      i = end;
    }
    if (plain.isNotEmpty) {
      out.add(TextSpan(text: plain.toString(), style: style));
    }
    return out;
  }

  /// Nombre de caractères (d'origine) du mot à mettre en valeur.
  static int _litLength(List<String> word, List<String> tokens) {
    final normalized = normalizeForSearch(word.join());
    var bestNormLen = 0;
    for (final t in tokens) {
      final m = tokenMatch(t, normalized);
      if (m == 0) continue;
      final len = t.length > normalized.length ? normalized.length : t.length;
      if (len > bestNormLen) bestNormLen = len;
    }
    if (bestNormLen == 0) return 0;
    // Remonte de la longueur normalisée aux caractères d'origine (« œ »
    // devient deux lettres une fois normalisé).
    var acc = 0;
    for (var k = 0; k < word.length; k++) {
      acc += normalizeForSearch(word[k]).length;
      if (acc >= bestNormLen) return k + 1;
    }
    return word.length;
  }
}
