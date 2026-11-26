import 'dart:async';

import 'package:flutter/widgets.dart';

/// Mesure ce que la personne regarde vraiment dans le fil.
///
/// [onSeen] part quand au moins la moitié de la carte (ou la moitié de
/// l'écran, pour une carte plus haute que lui) est restée visible
/// [seenAfter] ; [onDwell] quand elle l'est restée [dwellAfter] — signe
/// qu'on lit, pas qu'on passe. Une carte simplement préparée hors écran
/// par la liste ne compte pas.
///
/// Chaque rappel ne part qu'une fois par carte montée. Vérification par
/// sondage léger (quelques cartes montées à la fois), arrêtée dès que les
/// deux mesures sont faites.
class FeedImpression extends StatefulWidget {
  const FeedImpression({
    super.key,
    required this.child,
    required this.onSeen,
    this.onDwell,
    this.seenAfter = const Duration(milliseconds: 900),
    this.dwellAfter = const Duration(seconds: 5),
  });

  final Widget child;
  final VoidCallback onSeen;
  final VoidCallback? onDwell;
  final Duration seenAfter;
  final Duration dwellAfter;

  @override
  State<FeedImpression> createState() => _FeedImpressionState();
}

class _FeedImpressionState extends State<FeedImpression> {
  static const _tick = Duration(milliseconds: 300);

  Timer? _timer;
  Duration _visibleFor = Duration.zero;
  bool _seen = false;
  bool _dwelled = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => _check());
  }

  void _check() {
    if (!mounted) return;
    if (_isVisible()) {
      _visibleFor += _tick;
    } else {
      // Il faut une présence continue : un passage éclair pendant un
      // défilement rapide n'est pas une lecture.
      _visibleFor = Duration.zero;
    }
    if (!_seen && _visibleFor >= widget.seenAfter) {
      _seen = true;
      widget.onSeen();
    }
    if (!_dwelled && _visibleFor >= widget.dwellAfter) {
      _dwelled = true;
      widget.onDwell?.call();
    }
    if (_seen && (_dwelled || widget.onDwell == null)) {
      _timer?.cancel();
      _timer = null;
    }
  }

  bool _isVisible() {
    // Écran recouvert (publication ouverte, autre page) : rien n'est vu.
    if (!TickerMode.valuesOf(context).enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final view = View.maybeOf(context);
    if (view == null) return false;
    final screenH = view.physicalSize.height / view.devicePixelRatio;
    final top = box.localToGlobal(Offset.zero).dy;
    final h = box.size.height;
    if (h <= 0) return false;
    final visible = (top + h).clamp(0.0, screenH) - top.clamp(0.0, screenH);
    final needed = (h < screenH ? h : screenH) * 0.5;
    return visible >= needed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
