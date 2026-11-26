
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import 'capture_shield.dart';
import 'foumbot_loader.dart';
import '../utils/local_media.dart';

/// Ouvre une vidéo de discussion en plein écran.
///
/// [source] est soit une URL Storage, soit le chemin du fichier local
/// quand le message n'est pas encore parti : une vidéo doit être
/// regardable tout de suite après l'avoir choisie, sans attendre la fin de
/// l'envoi.
///
/// [heroTag] doit être propre au message (`chat_video_<id>`), pour que la
/// vignette de la bulle s'agrandisse jusqu'au lecteur au lieu d'un fondu.
///
/// [sealed] marque une vidéo à vue unique : l'image est alors retirée dès
/// qu'un enregistrement d'écran commence (voir [CaptureShield]).
///
/// C'est la **seule** chose qui décode une vidéo dans la discussion : les
/// bulles, elles, n'affichent qu'une tuile. Un décodeur par bulle
/// s'installerait autant de fois qu'il y a de vidéos à l'écran, ce qu'un
/// téléphone d'entrée de gamme ne tient pas en défilant.
Future<void> openChatVideoViewer(
  BuildContext context, {
  required String source,
  required String heroTag,
  bool sealed = false,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          _ChatVideoViewer(source: source, heroTag: heroTag, sealed: sealed),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ChatVideoViewer extends StatefulWidget {
  const _ChatVideoViewer({
    required this.source,
    required this.heroTag,
    required this.sealed,
  });

  final String source;
  final String heroTag;
  final bool sealed;

  @override
  State<_ChatVideoViewer> createState() => _ChatVideoViewerState();
}

class _ChatVideoViewerState extends State<_ChatVideoViewer> {
  VideoPlayerController? _controller;

  /// Message d'erreur à afficher, quand la vidéo n'a pas pu s'ouvrir.
  /// Distinct de « en cours de chargement » : sans ça, une vidéo illisible
  /// laisse tourner la roue indéfiniment.
  String? _error;

  /// La barre de contrôle s'efface pendant la lecture et revient au
  /// premier appui — comme la visionneuse photo, qui masque son chrome.
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final source = widget.source;
    final controller = source.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(source))
        : LocalMedia.video(source);
    try {
      await controller.initialize();
    } on Exception {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = 'Cette vidéo n’a pas pu être ouverte.');
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // `setState` avant `play()` : la première image doit apparaître même
    // si la lecture démarre une fraction de seconde plus tard.
    setState(() => _controller = controller);
    await controller.setLooping(false);
    await controller.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
      } else {
        // Rejouer depuis le début quand la vidéo est allée au bout :
        // appuyer sur lecture sur la dernière image ne faisait rien.
        if (controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
        }
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.black.withValues(alpha: 0.96),
        body: Stack(
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: _error != null
                    ? _ErrorNotice(message: _error!)
                    : controller == null
                    ? const FoumbotLoader()
                    : GestureDetector(
                        onTap: () => setState(
                          () => _showControls = !_showControls,
                        ),
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: widget.sealed
                              ? CaptureShield(child: VideoPlayer(controller))
                              : VideoPlayer(controller),
                        ),
                      ),
              ),
            ),
            if (controller != null && _showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Controls(
                  controller: controller,
                  onTogglePlay: _togglePlay,
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close_rounded, color: AppColors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: AppColors.whiteMuted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.whiteMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre de lecture : bouton, position, durée et ligne de progression.
class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onTogglePlay});

  final VideoPlayerController controller;
  final VoidCallback onTogglePlay;

  static String _clock(Duration d) {
    final secs = d.inSeconds;
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.black.withValues(alpha: 0.75),
            AppColors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 16, 8),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) => Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Lecture',
                  iconSize: 34,
                  color: AppColors.white,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: onTogglePlay,
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    colors: const VideoProgressColors(
                      playedColor: AppColors.orange,
                      bufferedColor: AppColors.gray,
                      backgroundColor: AppColors.blackElevated,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_clock(value.position)} / ${_clock(value.duration)}',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
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
