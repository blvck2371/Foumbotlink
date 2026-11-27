import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../controllers/live_feed.dart';
import '../../models/live_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/user_avatar.dart';

/// Rouge « en direct » (voir [AppColors.live]).
const liveRed = AppColors.live;

/// Pastille « LIVE », avec la durée d'antenne si on la donne.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.elapsed, this.small = false});

  final Duration? elapsed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: liveRed,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        elapsed == null ? 'LIVE' : 'LIVE · ${LiveRules.elapsed(elapsed!)}',
        style: GoogleFonts.manrope(
          fontSize: small ? 10 : 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// Durée d'antenne qui avance d'elle-même, pour un spectateur.
class LiveElapsedBadge extends StatefulWidget {
  const LiveElapsedBadge({super.key, required this.startedAt});
  final DateTime startedAt;

  @override
  State<LiveElapsedBadge> createState() => _LiveElapsedBadgeState();
}

class _LiveElapsedBadgeState extends State<LiveElapsedBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.startedAt);
    return LiveBadge(elapsed: d.isNegative ? Duration.zero : d);
  }
}

/// Hauteur du fil de commentaires : un tiers de l'écran, moins quand le
/// clavier est ouvert pour que la barre du haut et le champ tiennent.
double liveFeedHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return MediaQuery.viewInsetsOf(context).bottom > 0 ? h * 0.18 : h * 0.34;
}

/// Fond translucide des éléments posés sur la vidéo : lisible sur une
/// image claire comme sombre.
BoxDecoration liveGlass([double radius = 20]) => BoxDecoration(
  color: Colors.black.withValues(alpha: 0.38),
  borderRadius: BorderRadius.circular(radius),
);

/// Nombre de spectateurs (œil + nombre).
class ViewersPill extends StatelessWidget {
  const ViewersPill({super.key, required this.count, this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count spectateurs',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: liveGlass(17),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.white,
              ),
              const SizedBox(width: 6),
              Text(
                LiveRules.compactCount(count),
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton rond translucide posé sur la vidéo.
class LiveRoundButton extends StatelessWidget {
  const LiveRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.size = 40,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color ?? Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.5, color: AppColors.white),
          ),
        ),
      ),
    );
  }
}

/// Hôte : photo, nom et titre du live, en haut à gauche.
class LiveHostChip extends StatelessWidget {
  const LiveHostChip({super.key, required this.live, this.trailing});

  final LiveSession live;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
      decoration: liveGlass(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(name: live.hostName, photoUrl: live.hostPhoto, radius: 17),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.hostName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
                Text(
                  live.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    color: AppColors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Les commentaires et arrivées qui défilent en bas à gauche, les plus
/// récents en bas, les plus anciens qui s'estompent en haut.
class LiveCommentsList extends StatelessWidget {
  const LiveCommentsList({
    super.key,
    required this.feed,
    required this.hostUid,
    this.onLongPress,
  });

  final LiveFeed feed;
  final String hostUid;
  final void Function(LiveComment comment)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black],
        stops: [0, 0.22, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: Obx(() {
        final items = feed.items.toList();
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.only(top: 40),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[items.length - 1 - i];
            return Padding(
              key: ValueKey(item.key),
              padding: const EdgeInsets.only(bottom: 6),
              child: switch (item) {
                LiveCommentItem(:final comment) => _CommentRow(
                  comment: comment,
                  isHost: comment.uid == hostUid,
                  onLongPress: onLongPress == null
                      ? null
                      : () => onLongPress!(comment),
                ),
                LiveJoinItem(:final name) => _JoinRow(text: '$name a rejoint'),
                LiveNoticeItem(:final text) => _JoinRow(text: text),
              },
            );
          },
        );
      }),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.isHost,
    this.onLongPress,
  });

  final LiveComment comment;
  final bool isHost;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onLongPress,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 5),
          decoration: liveGlass(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                name: comment.name,
                photoUrl: comment.photo,
                radius: 12,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: comment.name,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                            color: isHost
                                ? AppColors.orangeSoft
                                : AppColors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        if (isHost)
                          TextSpan(
                            text: ' · Hôte',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              color: AppColors.orangeSoft,
                            ),
                          ),
                        const TextSpan(text: '  '),
                        TextSpan(text: comment.text),
                      ],
                    ),
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      height: 1.3,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinRow extends StatelessWidget {
  const _JoinRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: liveGlass(14),
        child: Text(
          text,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Cœurs qui montent en ondulant au-dessus du bouton, comme sur TikTok.
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({super.key, required this.bursts});

  /// Chaque valeur : nombre de cœurs à faire monter.
  final Stream<int> bursts;

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _Heart {
  _Heart(this.controller, this.color, this.drift, this.size);
  final AnimationController controller;
  final Color color;
  final double drift;
  final double size;
}

class _FloatingHeartsState extends State<FloatingHearts>
    with TickerProviderStateMixin {
  static const _maxOnScreen = 24;
  static const _colors = [
    liveRed,
    Color(0xFFFF5C8A),
    AppColors.orangeSoft,
    Color(0xFFFF8A65),
  ];

  final _hearts = <_Heart>[];
  final _random = Random();
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.bursts.listen(_burst);
  }

  @override
  void didUpdateWidget(covariant FloatingHearts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bursts != widget.bursts) {
      _sub?.cancel();
      _sub = widget.bursts.listen(_burst);
    }
  }

  void _burst(int n) {
    for (var i = 0; i < n; i++) {
      Future<void>.delayed(Duration(milliseconds: 90 * i), _spawn);
    }
  }

  void _spawn() {
    if (!mounted || _hearts.length >= _maxOnScreen) return;
    final c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1700 + _random.nextInt(700)),
    );
    final heart = _Heart(
      c,
      _colors[_random.nextInt(_colors.length)],
      (_random.nextDouble() - 0.5) * 2,
      24 + _random.nextDouble() * 12,
    );
    setState(() => _hearts.add(heart));
    c.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _hearts.remove(heart));
      c.dispose();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final h in _hearts)
              AnimatedBuilder(
                animation: h.controller,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(h.controller.value);
                  final x =
                      box.maxWidth / 2 -
                      h.size / 2 +
                      sin(t * pi * 2.2) * 18 * h.drift;
                  final y =
                      box.maxHeight - h.size - t * (box.maxHeight - h.size);
                  final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
                  final scale = t < 0.15 ? 0.5 + t / 0.15 * 0.6 : 1.1;
                  return Positioned(
                    left: x,
                    top: y,
                    child: Opacity(
                      opacity: fade.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Icon(
                          Icons.favorite_rounded,
                          size: h.size,
                          color: h.color,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Barre du bas : champ de commentaire, puis les actions du rôle (cœur
/// pour le spectateur, micro et caméra pour l'hôte).
class LiveComposer extends StatefulWidget {
  const LiveComposer({super.key, required this.feed, required this.actions});

  final LiveFeed feed;
  final List<Widget> actions;

  @override
  State<LiveComposer> createState() => _LiveComposerState();
}

class _LiveComposerState extends State<LiveComposer> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text;
    if (LiveRules.cleanComment(text) == null) return;
    _ctrl.clear();
    final refusal = await widget.feed.sendComment(text);
    if (refusal != null && mounted) {
      _ctrl.text = text;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(refusal),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: liveGlass(22),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    maxLength: LiveRules.maxComment,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    cursorColor: AppColors.orangeSoft,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.white,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Dites quelque chose…',
                      hintStyle: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppColors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (context, v, _) => v.text.trim().isEmpty
                      ? const SizedBox(width: 8)
                      : IconButton(
                          tooltip: 'Envoyer',
                          onPressed: _send,
                          icon: const Icon(
                            Icons.send_rounded,
                            color: AppColors.orangeSoft,
                            size: 21,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        for (final a in widget.actions) ...[const SizedBox(width: 8), a],
      ],
    );
  }
}

/// Feuille d'options sur fond sombre (commentaire, live).
Future<T?> showLiveSheet<T>({
  required String title,
  required List<({IconData icon, String label, T value, bool danger})> options,
}) {
  return Get.bottomSheet<T>(
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.whiteMuted,
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(
                  o.icon,
                  color: o.danger ? const Color(0xFFFF6B6B) : AppColors.white,
                ),
                title: Text(
                  o.label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: o.danger ? const Color(0xFFFF6B6B) : AppColors.white,
                  ),
                ),
                onTap: () => Get.back<T>(result: o.value),
              ),
          ],
        ),
      ),
    ),
    backgroundColor: AppColors.blackElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
  );
}

/// Une place du panel telle qu'affichée : l'hôte, un invité, ou soi-même.
class LiveStageTile {
  const LiveStageTile({
    required this.uid,
    required this.name,
    this.photo,
    this.track,
    this.mirror = false,
    this.micOff = false,
    this.isHost = false,
  });

  final String uid;
  final String name;
  final String? photo;
  final VideoTrack? track;

  /// Sa propre caméra avant : affichée en miroir, comme un selfie.
  final bool mirror;
  final bool micOff;
  final bool isHost;
}

/// Le plateau d'un live : l'hôte seul en plein écran, ou, dès qu'un invité
/// monte, une grille comme le multi-invités de TikTok — deux côte à côte,
/// puis 2 × 2. Les places libres s'affichent ; un spectateur peut toucher
/// l'une d'elles pour demander à monter ([onTapSeat]).
class LiveStageGrid extends StatelessWidget {
  const LiveStageGrid({
    super.key,
    required this.tiles,
    this.onTapTile,
    this.onTapSeat,
    this.fallback,
  });

  /// L'hôte d'abord, puis les invités.
  final List<LiveStageTile> tiles;
  final void Function(LiveStageTile tile)? onTapTile;
  final VoidCallback? onTapSeat;

  /// Ce qui remplace l'image de l'hôte seul quand elle manque encore.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (tiles.length <= 1) {
      final t = tiles.isEmpty ? null : tiles.first;
      final track = t?.track;
      if (track == null) {
        return fallback ?? const ColoredBox(color: Colors.black);
      }
      return VideoTrackRenderer(
        track,
        fit: VideoViewFit.cover,
        mirrorMode: t!.mirror
            ? VideoViewMirrorMode.mirror
            : VideoViewMirrorMode.off,
      );
    }
    final cells = tiles.length == 2 ? 2 : 4;
    final top = MediaQuery.paddingOf(context).top + 96;
    return ColoredBox(
      color: const Color(0xFF141414),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / 2;
          final h = min(w * 4 / 3, (box.maxHeight - top - 120) / (cells / 2));
          Widget cell(int i) => SizedBox(
            width: w,
            height: h,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: i < tiles.length
                  ? _StageCell(
                      tile: tiles[i],
                      onTap: onTapTile == null
                          ? null
                          : () => onTapTile!(tiles[i]),
                    )
                  : _EmptySeat(onTap: onTapSeat),
            ),
          );
          return Column(
            children: [
              SizedBox(height: top),
              Row(children: [cell(0), cell(1)]),
              if (cells == 4) Row(children: [cell(2), cell(3)]),
            ],
          );
        },
      ),
    );
  }
}

class _StageCell extends StatelessWidget {
  const _StageCell({required this.tile, this.onTap});
  final LiveStageTile tile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final track = tile.track;
    return Semantics(
      label:
          '${tile.name}${tile.isHost ? ', hôte' : ''}'
          '${tile.micOff ? ', micro coupé' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null)
                VideoTrackRenderer(
                  track,
                  fit: VideoViewFit.cover,
                  mirrorMode: tile.mirror
                      ? VideoViewMirrorMode.mirror
                      : VideoViewMirrorMode.off,
                )
              else
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3A1C0A), Color(0xFF161616)],
                    ),
                  ),
                  child: Center(
                    child: UserAvatar(
                      name: tile.name,
                      photoUrl: tile.photo,
                      radius: 30,
                    ),
                  ),
                ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: liveGlass(10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tile.micOff) ...[
                          const Icon(
                            Icons.mic_off_rounded,
                            size: 13,
                            color: Color(0xFFFF8A80),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            tile.isHost ? '${tile.name} · Hôte' : tile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: tile.isHost
                                  ? AppColors.orangeSoft
                                  : AppColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              onTap == null ? Icons.event_seat_outlined : Icons.add_rounded,
              size: 28,
              color: AppColors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              onTap == null ? 'Place libre' : 'Rejoindre',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une pastille de nombre sur un bouton rond (demandes en attente…).
class LiveCountBadge extends StatelessWidget {
  const LiveCountBadge({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: liveRed,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// En haut à gauche d'un live, comme sur TikTok : la photo de l'hôte, son
/// nom, et les cœurs reçus qui montent en direct ; puis « Suivre » ou
/// toute autre action ([trailing]).
class LiveHostCapsule extends StatelessWidget {
  const LiveHostCapsule({
    super.key,
    required this.name,
    required this.likes,
    this.photo,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String? photo;
  final int likes;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
        decoration: liveGlass(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(name: name, photoUrl: photo, radius: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ),
                  Semantics(
                    label: '$likes cœurs',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 12,
                          color: Color(0xFFFF5C8A),
                        ),
                        const SizedBox(width: 3),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, a) =>
                              ScaleTransition(scale: a, child: child),
                          child: Text(
                            LiveRules.compactCount(likes),
                            key: ValueKey(likes),
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}

/// En haut à droite d'un live : les premiers spectateurs en pastilles,
/// puis leur nombre, en direct.
class LiveAudience extends StatelessWidget {
  const LiveAudience({
    super.key,
    required this.viewers,
    required this.count,
    this.onTap,
  });

  final List<LiveViewer> viewers;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = viewers.take(3).toList();
    return Semantics(
      label: '$count spectateurs',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shown.isNotEmpty)
              SizedBox(
                width: 26.0 + (shown.length - 1) * 18,
                height: 30,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * 18.0,
                        top: 2,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                          padding: const EdgeInsets.all(1),
                          child: UserAvatar(
                            name: shown[i].name,
                            photoUrl: shown[i].photo,
                            radius: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: liveGlass(15),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 15,
                    color: AppColors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    LiveRules.compactCount(count),
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fenêtre posée au-dessus du live (invitation à monter, demande à
/// rejoindre) : fond assombri, carte au centre.
class LivePrompt extends StatelessWidget {
  const LivePrompt({
    super.key,
    required this.name,
    required this.photo,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.cancelLabel,
    required this.onCancel,
    this.extra,
  });

  /// Sous le message (choix de la caméra…).
  final Widget? extra;

  final String name;
  final String? photo;
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String cancelLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.blackElevated,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [liveRed, Color(0xFFFF5C8A)],
                    ),
                  ),
                  child: UserAvatar(name: name, photoUrl: photo, radius: 34),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.whiteMuted,
                  ),
                ),
                if (extra != null) ...[const SizedBox(height: 14), extra!],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: liveRed,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.white,
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Monter avec ma caméra » : on peut rejoindre le panel au micro seul,
/// et allumer la caméra plus tard.
class LiveCameraChoice extends StatelessWidget {
  const LiveCameraChoice({super.key, required this.cameraOn});
  final RxBool cameraOn;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: SwitchListTile(
          value: cameraOn.value,
          onChanged: (v) => cameraOn.value = v,
          activeThumbColor: AppColors.white,
          activeTrackColor: liveRed,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          secondary: Icon(
            cameraOn.value
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            color: AppColors.white,
          ),
          title: Text(
            cameraOn.value ? 'Avec ma caméra' : 'Micro seulement',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          subtitle: Text(
            'Vous pourrez l’allumer ou l’éteindre pendant le live.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.whiteMuted,
            ),
          ),
        ),
      ),
    );
  }
}
