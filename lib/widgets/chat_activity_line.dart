import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/chat_service.dart' show ChatActivity;
import '../theme/app_colors.dart';

/// Ligne « en train d'écrire… » / « en train d'enregistrer… » façon
/// WhatsApp. Partagée par l'en-tête de la discussion (sous le nom de
/// l'interlocuteur) et par la liste des conversations (à la place de
/// l'aperçu du dernier message), pour que les deux affichent exactement le
/// même libellé, la même couleur et la même animation.
class ChatActivityLine extends StatelessWidget {
  const ChatActivityLine({
    super.key,
    required this.activity,
    this.fontSize = 11,
    this.compact = false,
  });

  final ChatActivity activity;
  final double fontSize;

  /// Libellé raccourci pour les emplacements étroits — la tuile de la liste
  /// des conversations, où le nom occupe déjà la ligne du dessus.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final recording = activity == ChatActivity.recording;
    final color = recording ? AppColors.orange : AppColors.blue;
    final label = recording
        ? (compact
              ? 'en train d’enregistrer…'
              : 'en train d’enregistrer un vocal…')
        : 'en train d’écrire…';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recording)
          _PulsingMic(color: color, size: fontSize + 4)
        else
          TypingDots(color: color, size: fontSize * 0.42),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Les trois points qui rebondissent en cascade, façon bulle « … ».
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color, this.size = 4.5});

  final Color color;

  /// Diamètre d'un point ; l'ensemble occupe environ 5× cette largeur.
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Hauteur relative (0 → 1 → 0) du point `i`. Chaque point est décalé
  /// d'un sixième de cycle sur le précédent, et reste au repos pendant la
  /// seconde moitié — d'où la vague qui repart de la gauche.
  double _bounce(int i) {
    final t = (_ctrl.value - i * 0.16) % 1.0;
    if (t >= 0.5) return 0;
    return math.sin(t * 2 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    return SizedBox(
      width: d * 4.4,
      height: d * 2.4,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => Stack(
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: i * d * 1.7,
                bottom: d * 1.1 * _bounce(i),
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: 0.4 + 0.6 * _bounce(i),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Micro qui pulse pendant l'enregistrement d'un vocal.
class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Icon(Icons.mic, size: widget.size, color: widget.color),
    );
  }
}
