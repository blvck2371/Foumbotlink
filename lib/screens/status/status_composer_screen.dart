
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../models/user_status.dart';
import '../../theme/app_colors.dart';
import '../../utils/local_media.dart';

/// Ce que la composition renvoie à l'appelant, qui se charge de publier —
/// l'écran ne connaît ni Firestore ni Storage.
class StatusDraft {
  const StatusDraft({
    this.imagePath,
    this.videoPath,
    this.text = '',
    this.backgroundColor = UserStatus.defaultBackgroundColor,
  });

  final String? imagePath;
  final String? videoPath;
  final String text;
  final int backgroundColor;

  bool get hasMedia =>
      (imagePath != null && imagePath!.isNotEmpty) ||
      (videoPath != null && videoPath!.isNotEmpty);

  bool get isEmpty => !hasMedia && text.trim().isEmpty;
}

/// Composition d'un statut : une photo ou une vidéo qu'on légende, ou du
/// texte sur un fond coloré. Renvoie un [StatusDraft] via
/// `Get.back(result:)`.
class StatusComposerScreen extends StatefulWidget {
  const StatusComposerScreen({super.key, this.imagePath, this.videoPath});

  /// Photo déjà choisie et compressée par l'appelant.
  final String? imagePath;

  /// Vidéo déjà choisie et bornée en durée par l'appelant.
  final String? videoPath;

  @override
  State<StatusComposerScreen> createState() => _StatusComposerScreenState();
}

class _StatusComposerScreenState extends State<StatusComposerScreen> {
  /// Fonds proposés pour un statut texte — la palette de l'app, plus
  /// quelques teintes sombres qui laissent le texte blanc lisible.
  static const _backgrounds = <int>[
    UserStatus.defaultBackgroundColor,
    0xFFC65100,
    0xFF1E88E5,
    0xFF2E7D32,
    0xFF6A1B9A,
    0xFF1F1F1F,
  ];

  /// Un statut texte doit tenir à l'écran d'un coup d'œil.
  static const _maxTextLength = 280;

  final _textCtrl = TextEditingController();
  int _background = _backgrounds.first;

  bool get _isPhoto => widget.imagePath != null && widget.imagePath!.isNotEmpty;

  bool get _isVideo => widget.videoPath != null && widget.videoPath!.isNotEmpty;

  /// Photo comme vidéo se publient sans légende ; un statut texte, lui, a
  /// besoin de son texte.
  bool get _hasMedia => _isPhoto || _isVideo;

  bool get _canPublish => _hasMedia || _textCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _publish() {
    if (!_canPublish) return;
    Get.back(
      result: StatusDraft(
        imagePath: widget.imagePath,
        videoPath: widget.videoPath,
        text: _textCtrl.text.trim(),
        backgroundColor: _background,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hasMedia ? AppColors.black : Color(_background),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isPhoto)
            Center(
              child: Image(
                image: LocalMedia.image(widget.imagePath!),
                fit: BoxFit.contain,
              ),
            ),
          if (_isVideo) _VideoPreview(path: widget.videoPath!),

          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Annuler',
                      onPressed: Get.back<void>,
                      icon: const Icon(Icons.close, color: AppColors.white),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Visible 24 h',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child: TextField(
                        controller: _textCtrl,
                        maxLength: _maxTextLength,
                        maxLines: _hasMedia ? 3 : 8,
                        minLines: 1,
                        textAlign: TextAlign.center,
                        cursorColor: AppColors.white,
                        style: _hasMedia
                            ? GoogleFonts.manrope(
                                fontSize: 16,
                                height: 1.4,
                                color: AppColors.white,
                              )
                            : GoogleFonts.spaceGrotesk(
                                fontSize: 26,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: _hasMedia
                              ? 'Ajouter une légende (facultatif)'
                              : 'Qu’avez-vous à dire ?',
                          hintStyle: GoogleFonts.manrope(
                            fontSize: _hasMedia ? 16 : 22,
                            color: AppColors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (!_hasMedia)
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _backgrounds.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final color = _backgrounds[i];
                        final selected = color == _background;
                        return GestureDetector(
                          onTap: () => setState(() => _background = color),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? AppColors.white
                                    : AppColors.white.withValues(alpha: 0.35),
                                width: selected ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _canPublish ? _publish : null,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Publier le statut'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu de la vidéo choisie, en boucle : on vérifie ce qu'on s'apprête à
/// publier avant de l'envoyer.
class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.path});

  final String path;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = LocalMedia.video(widget.path);
    _controller.initialize().then((_) {
      if (!mounted) return;
      _controller
        ..setLooping(true)
        ..play();
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
