import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../models/feed_item.dart';
import '../theme/app_colors.dart';
import 'chat_video_viewer.dart';
import 'feed_image.dart';

/// Vidéo d'une publication dans le fil.
///
/// Rien n'est téléchargé tant qu'on ne touche pas : la carte n'affiche
/// que la vignette. Un toucher lance la lecture sur place ; une seule
/// vidéo joue à la fois dans toute l'app (en lancer une met la précédente
/// en pause), et quitter l'écran libère le décodeur — un téléphone
/// d'entrée de gamme ne tient pas plusieurs lecteurs ouverts en défilant.
class PostVideo extends StatefulWidget {
  const PostVideo({
    super.key,
    required this.url,
    required this.isDark,
    required this.heroTag,
    this.thumbUrl,
    this.aspectRatio,
    this.durationLabel = '',
    this.borderRadius = 12,
  });

  final String url;
  final String? thumbUrl;
  final double? aspectRatio;
  final String durationLabel;
  final bool isDark;
  final String heroTag;
  final double borderRadius;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  /// Le lecteur actif, s'il y en a un — pour mettre en pause l'ancien.
  static _PostVideoState? _active;

  VideoPlayerController? _player;
  bool _loading = false;
  bool _failed = false;

  /// Format affiché : celui de la vidéo, borné pour qu'une vidéo très
  /// verticale n'occupe pas tout l'écran du fil.
  double get _ratio => (widget.aspectRatio ?? 16 / 9).clamp(4 / 5, 16 / 9);

  @override
  void didUpdateWidget(covariant PostVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _release();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    if (_active == this) _active = null;
    final p = _player;
    _player = null;
    p?.removeListener(_onTick);
    unawaited(p?.dispose());
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p != null && p.value.isInitialized) {
      if (p.value.isPlaying) {
        await p.pause();
      } else {
        _takeOver();
        if (p.value.position >= p.value.duration) await p.seekTo(Duration.zero);
        await p.play();
      }
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final player = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      _takeOver();
      player.addListener(_onTick);
      setState(() {
        _player = player;
        _loading = false;
      });
      await player.play();
    } on Object catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _takeOver() {
    final previous = _active;
    if (previous != null && previous != this) {
      unawaited(previous._player?.pause());
    }
    _active = this;
  }

  Future<void> _fullscreen() async {
    await _player?.pause();
    if (!mounted) return;
    await openChatVideoViewer(
      context,
      source: widget.url,
      heroTag: widget.heroTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final ready = p != null && p.value.isInitialized;
    final playing = ready && p.value.isPlaying;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: _ratio,
        child: GestureDetector(
          onTap: _toggle,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.black),
              if (ready)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: p.value.size.width,
                    height: p.value.size.height,
                    child: VideoPlayer(p),
                  ),
                )
              else if (widget.thumbUrl != null)
                FeedNetworkImage(url: widget.thumbUrl!, isDark: true),
              if (!playing)
                Center(
                  child: _loading
                      ? const SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _failed ? Icons.refresh : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                ),
              if (_failed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Text(
                    'Lecture impossible — touchez pour réessayer',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    p,
                    allowScrubbing: true,
                    padding: const EdgeInsets.only(top: 6),
                    colors: VideoProgressColors(
                      playedColor: AppColors.orange,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              if (!ready && widget.durationLabel.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _Badge(widget.durationLabel),
                ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  tooltip: 'Plein écran',
                  onPressed: _fullscreen,
                  icon: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
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

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Les vidéos d'une publication : une seule s'affiche telle quelle ;
/// plusieurs défilent d'un glissement, avec un compteur « 2/3 ».
///
/// Quitter une vidéo en glissant la libère (la page sort de l'écran) :
/// jamais deux lecteurs ouverts pour une même publication.
class PostVideos extends StatefulWidget {
  const PostVideos({
    super.key,
    required this.videos,
    required this.isDark,
    required this.heroPrefix,
    this.borderRadius = 12,
  });

  final List<PostVideoItem> videos;
  final bool isDark;
  final String heroPrefix;
  final double borderRadius;

  @override
  State<PostVideos> createState() => _PostVideosState();
}

class _PostVideosState extends State<PostVideos> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Widget _video(int i) {
    final v = widget.videos[i];
    return PostVideo(
      url: v.url,
      thumbUrl: v.thumbUrl,
      aspectRatio: v.aspectRatio,
      durationLabel: v.durationLabel,
      isDark: widget.isDark,
      heroTag: '${widget.heroPrefix}_$i',
      borderRadius: widget.borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    if (videos.isEmpty) return const SizedBox.shrink();
    if (videos.length == 1) return _video(0);

    // Hauteur commune : celle de la première vidéo, bornée comme dans
    // PostVideo. Les autres s'y inscrivent sur fond noir.
    final ratio = (videos.first.aspectRatio ?? 16 / 9).clamp(4 / 5, 16 / 9);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: ratio,
          child: PageView.builder(
            controller: _page,
            itemCount: videos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _video(i),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < videos.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _index
                      ? AppColors.orange
                      : AppColors.gray.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            const SizedBox(width: 8),
            Text(
              '${_index + 1}/${videos.length}',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: widget.isDark ? AppColors.whiteMuted : AppColors.gray,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
