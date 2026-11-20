import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../models/report.dart';
import '../../models/user_status.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';
import '../../services/status_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/user_avatar.dart';

/// Ouvre les statuts d'une personne en plein écran, à partir de [initialIndex].
///
/// Poussé directement plutôt que par route nommée, comme la visionneuse de
/// photos du fil : c'est un écran de passage, sans état à retrouver, et la
/// liste des statuts vient de l'appelant, qui l'écoute déjà.
Future<void> openStatusViewer(
  BuildContext context, {
  required List<UserStatus> statuses,
  int initialIndex = 0,
  bool canDelete = false,
  Future<void> Function(UserStatus status)? onDelete,
  void Function(String statusId, bool liked)? onLikeChanged,
}) {
  if (statuses.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => StatusViewerScreen(
        statuses: statuses,
        initialIndex: initialIndex.clamp(0, statuses.length - 1),
        canDelete: canDelete,
        onDelete: onDelete,
        onLikeChanged: onLikeChanged,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.statuses,
    this.initialIndex = 0,
    this.canDelete = false,
    this.onDelete,
    this.onLikeChanged,
  });

  final List<UserStatus> statuses;
  final int initialIndex;

  /// L'auteur peut retirer un statut avant son expiration.
  final bool canDelete;
  final Future<void> Function(UserStatus status)? onDelete;

  /// Remonte un « j'aime » posé ici, pour que l'écran d'origine garde le
  /// bon état une fois la visionneuse refermée.
  final void Function(String statusId, bool liked)? onLikeChanged;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  /// Durée d'affichage d'un statut photo ou texte avant de passer au
  /// suivant. Assez pour lire une légende, assez court pour ne pas retenir
  /// prisonnier. Une vidéo, elle, dure ce qu'elle dure.
  static const _perStatus = Duration(seconds: 6);

  /// Plafond de lecture d'une vidéo : au-delà, on passe au statut suivant.
  /// Sert de garde-fou si une vidéo plus longue que la limite de prise de
  /// vue arrive un jour dans la base.
  static const _maxVideo = Duration(seconds: 60);

  late final AnimationController _progress;
  late final PageController _pages;
  late final List<UserStatus> _statuses;
  late int _index;

  /// Vues déjà comptées pendant cette session d'affichage — inutile de
  /// redemander au serveur si l'on revient en arrière.
  final _counted = <String>{};

  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();

  /// Un envoi est en cours : on évite le double appui sur le cœur ou sur
  /// « envoyer », qui posterait deux messages.
  bool _sending = false;

  /// Lecteur du statut vidéo affiché, `null` pour une photo ou du texte.
  VideoPlayerController? _video;

  /// Jeton d'ouverture : passer au statut suivant pendant qu'une vidéo se
  /// charge doit annuler ce chargement, sinon une vidéo abandonnée
  /// s'installerait par-dessus le statut désormais affiché.
  int _mediaToken = 0;

  StatusService get _service => Get.find<StatusService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  @override
  void initState() {
    super.initState();
    _statuses = List<UserStatus>.from(widget.statuses);
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
    _progress = AnimationController(vsync: this, duration: _perStatus)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    // Écrire une réponse doit figer la série : sans ça, le statut auquel
    // on répond a changé avant qu'on ait fini sa phrase.
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pause();
      } else if (mounted) {
        _resume();
      }
    });
    unawaited(_startCurrent());
  }

  @override
  void dispose() {
    _mediaToken++;
    _video?.dispose();
    _progress.dispose();
    _pages.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _startCurrent() async {
    final token = ++_mediaToken;
    final status = _statuses[_index];
    unawaited(_countView(status));

    final previous = _video;
    if (previous != null) {
      _video = null;
      await previous.dispose();
      if (!mounted || token != _mediaToken) return;
    }

    if (!status.hasVideo) {
      _progress
        ..duration = _perStatus
        ..forward(from: 0);
      return;
    }

    // La barre attend l'ouverture de la vidéo : la laisser courir pendant
    // le chargement ferait passer au statut suivant avant la première
    // image.
    _progress
      ..stop()
      ..value = 0;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(status.videoUrl!),
    );
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      if (!mounted || token != _mediaToken) return;
      // Vidéo illisible : on ne bloque pas la série pour autant, elle
      // défile comme un statut ordinaire.
      _progress
        ..duration = _perStatus
        ..forward(from: 0);
      setState(() {});
      return;
    }

    if (!mounted || token != _mediaToken) {
      await controller.dispose();
      return;
    }

    final length = controller.value.duration;
    _video = controller;
    _progress.duration =
        length > Duration.zero && length < _maxVideo ? length : _maxVideo;
    await controller.play();
    if (!mounted || token != _mediaToken) return;
    _progress.forward(from: 0);
    setState(() {});
  }

  /// Met la série en pause — barre **et** vidéo, sans quoi le son
  /// continuerait sous une image figée.
  void _pause() {
    _progress.stop();
    _video?.pause();
  }

  void _resume() {
    _progress.forward();
    _video?.play();
  }

  /// Compte la vue une seule fois par statut et par personne — le service
  /// s'en assure côté base, on évite ici l'aller-retour inutile.
  Future<void> _countView(UserStatus status) async {
    if (!_auth.isSignedIn) return;
    if (status.authorUid == _auth.uid) return;
    if (!_counted.add(status.id)) return;

    final profile = _profiles.profile.value;
    try {
      final views = await _service.markViewed(
        status: status,
        viewerUid: _auth.uid,
        viewerName: profile?.displayName ?? 'Quelqu’un',
        viewerPhotoUrl: profile?.photoUrl,
      );
      if (views == null || !mounted) return;
      setState(() {
        final i = _statuses.indexWhere((s) => s.id == status.id);
        if (i != -1) {
          _statuses[i] = _statuses[i].copyWith(
            viewsCount: views,
            viewedByMe: true,
          );
        }
      });
    } catch (_) {
      // Une vue non comptée ne doit jamais empêcher de regarder.
      _counted.remove(status.id);
    }
  }

  // -----------------------------------------------------------------------
  // Réagir — tout part dans la discussion avec l'auteur
  // -----------------------------------------------------------------------

  /// Aime / retire son « j'aime ».
  ///
  /// L'affichage réagit tout de suite et revient en arrière si l'écriture
  /// échoue : sur un réseau lent, attendre la confirmation pour colorer un
  /// cœur donne l'impression que l'appui n'a pas été pris.
  Future<void> _toggleLike() async {
    if (_sending || !_auth.isSignedIn) return;
    final status = _statuses[_index];
    if (status.authorUid == _auth.uid) return;

    final liked = !status.likedByMe;
    final before = status;
    setState(() {
      _sending = true;
      _statuses[_index] = status.copyWith(
        likedByMe: liked,
        likesCount: (status.likesCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
      );
    });

    try {
      final count = await _service.likeAndNotify(
        status: before,
        uid: _auth.uid,
        liked: liked,
      );
      widget.onLikeChanged?.call(status.id, liked);
      if (!mounted) return;
      setState(() {
        _statuses[_index] =
            _statuses[_index].copyWith(likesCount: count, likedByMe: liked);
      });
      if (liked) _toast('Envoyé à ${status.authorName}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statuses[_index] = before);
      _toast('Action impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Envoie un commentaire — il arrive dans la discussion avec l'auteur,
  /// avec le statut en citation.
  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending || !_auth.isSignedIn) return;
    final status = _statuses[_index];
    if (status.authorUid == _auth.uid) return;

    setState(() => _sending = true);
    try {
      await _service.commentStatus(
        status: status,
        uid: _auth.uid,
        text: text,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      _replyFocus.unfocus();
      _toast('Réponse envoyée à ${status.authorName}');
    } catch (e) {
      if (mounted) _toast('Envoi impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Repartage le statut dans les siens.
  ///
  /// On demande confirmation : republier ce que quelqu'un d'autre a
  /// publié n'est pas un geste anodin, et le raccourci se trouve juste à
  /// côté du champ de réponse.
  Future<void> _repost() async {
    if (_sending || !_auth.isSignedIn) return;
    final status = _statuses[_index];
    _pause();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repartager ce statut ?'),
        content: Text(
          'Il apparaîtra dans vos statuts pendant 24 heures, avec la '
          'mention « repartagé de ${status.authorName} ».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Repartager'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) {
      _resume();
      return;
    }

    setState(() => _sending = true);
    try {
      final profile = _profiles.profile.value;
      await _service.repostStatus(
        original: status,
        authorUid: _auth.uid,
        authorName: profile?.displayName ?? 'Vous',
        authorPhotoUrl: profile?.photoUrl,
      );
      // La notification à l'auteur ne doit pas faire échouer le
      // repartage, qui, lui, est déjà publié.
      unawaited(
        _service
            .notifyRepost(status: status, uid: _auth.uid)
            .catchError((_) {}),
      );
      if (mounted) _toast('Ajouté à vos statuts');
    } catch (e) {
      if (mounted) _toast('Repartage impossible. Réessayez.');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _resume();
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.manrope()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _next() {
    if (_index >= _statuses.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    if (_index == 0) {
      // Rejoue le statut courant depuis le début — la vidéo aussi, sans
      // quoi la barre repartirait sur une image restée à la fin.
      _video?.seekTo(Duration.zero);
      _progress.forward(from: 0);
      return;
    }
    _pages.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    unawaited(_startCurrent());
  }

  Future<void> _confirmDelete() async {
    _pause();
    final status = _statuses[_index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce statut ?'),
        content: const Text(
          'Il disparaîtra immédiatement, avant la fin des 24 heures.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _resume();
      return;
    }

    await widget.onDelete?.call(status);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  /// Signale le statut affiché, puis propose de bloquer son auteur. La
  /// lecture est en pause pendant toute l'opération.
  Future<void> _report() async {
    _pause();
    final status = _statuses[_index];
    final moderation = Get.find<ModerationService>();
    try {
      final choice = await showReportSheet(targetLabel: 'ce statut');
      if (choice == null) return;
      await moderation.report(
        ContentReport(
          targetType: ReportTargetType.status,
          targetId: status.id,
          targetPath: 'statuses/${status.id}',
          targetOwnerUid: status.authorUid,
          reporterUid: _auth.uid,
          reason: choice.reason,
          details: choice.details,
          excerpt: [
            status.text,
            status.imageUrl ?? '',
            status.videoUrl ?? '',
          ].where((e) => e.trim().isNotEmpty).join('\n'),
        ),
      );
      if (moderation.isBlocked(status.authorUid)) {
        Get.snackbar('Signalement envoyé', 'Merci. Notre équipe va l\'examiner.');
        return;
      }
      final block = await confirmAction(
        title: 'Signalement envoyé',
        message:
            'Merci. Notre équipe va l\'examiner.\n\nVoulez-vous aussi '
            'bloquer ${status.authorName} ? Vous ne verrez plus ses '
            'statuts, et cette personne ne pourra plus vous écrire.',
        confirmLabel: 'Bloquer',
        cancelLabel: 'Plus tard',
      );
      if (!block) return;
      await moderation.blockUser(
        myUid: _auth.uid,
        targetUid: status.authorUid,
        targetName: status.authorName,
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      Get.snackbar('Signalement impossible', '$e');
    } finally {
      if (mounted) _resume();
    }
  }

  void _showViewers() {
    _pause();
    final status = _statuses[_index];
    Get.bottomSheet(
      _ViewersSheet(status: status),
      isScrollControlled: true,
    ).whenComplete(() {
      if (mounted) _resume();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _statuses[_index];
    final isMine = _auth.isSignedIn && status.authorUid == _auth.uid;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AppColors.black,
      // Le champ de réponse doit remonter avec le clavier ; sans ça il
      // reste caché dessous et on écrit à l'aveugle.
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        // Un appui maintenu met en pause : on garde une photo sous les yeux
        // le temps qu'on veut, comme partout ailleurs.
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onTapUp: (details) {
          if (details.globalPosition.dx < width * 0.3) {
            _previous();
          } else {
            _next();
          }
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 250) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pages,
              // Le défilement se fait aux appuis latéraux : laisser aussi
              // le balayage libre ferait sauter la barre de progression
              // d'un statut à l'autre sans la relancer.
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _statuses.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) => _StatusPage(
                status: _statuses[i],
                // Seul le statut affiché a un lecteur : les pages voisines
                // que le PageView construit d'avance ne doivent rien jouer.
                video: i == _index ? _video : null,
              ),
            ),
            _Header(
              statuses: _statuses,
              index: _index,
              progress: _progress,
              canDelete: widget.canDelete && isMine,
              onDelete: _confirmDelete,
              onReport: isMine || !_auth.isSignedIn ? null : _report,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: isMine
                    // Sur son propre statut, ce qui compte est de savoir
                    // qui l'a vu — pas de se répondre à soi-même.
                    ? _ViewsButton(status: status, onTap: _showViewers)
                    : _ReplyBar(
                        status: status,
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        busy: _sending,
                        onSend: _sendReply,
                        onLike: _toggleLike,
                        onRepost: _repost,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre du bas sur le statut de quelqu'un d'autre : répondre, aimer,
/// repartager.
///
/// Les trois gestes aboutissent au même endroit — la discussion avec
/// l'auteur —, comme sur WhatsApp : il n'y a pas d'écran de commentaires
/// à part, et l'auteur retrouve les réactions là où il lit déjà ses
/// messages.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.status,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
    required this.onLike,
    required this.onRepost,
  });

  final UserStatus status;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onLike;
  final VoidCallback onRepost;

  @override
  Widget build(BuildContext context) {
    // Absorbe les appuis : sans ça, viser le champ de saisie ferait aussi
    // passer au statut suivant, la zone d'appui de la visionneuse
    // couvrant tout l'écran.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        minLines: 1,
                        maxLines: 3,
                        style: GoogleFonts.manrope(color: Colors.white),
                        cursorColor: AppColors.orange,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          hintText: 'Répondre à ${status.authorName}…',
                          hintStyle: GoogleFonts.manrope(
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        if (value.text.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          onPressed: busy ? null : onSend,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.send_rounded,
                              size: 20, color: AppColors.orange),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundAction(
              icon: status.likedByMe
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: status.likedByMe ? AppColors.orange : Colors.white,
              tooltip: status.likedByMe ? 'Je n’aime plus' : 'J’aime',
              onTap: busy ? null : onLike,
            ),
            const SizedBox(width: 6),
            _RoundAction(
              icon: Icons.repeat_rounded,
              color: Colors.white,
              tooltip: 'Repartager dans mes statuts',
              onTap: busy ? null : onRepost,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

/// Le contenu d'un statut : la photo si elle existe, sinon le texte sur son
/// fond coloré.
class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.status, this.video});

  final UserStatus status;

  /// Lecteur déjà initialisé, ou `null` tant que la vidéo s'ouvre.
  final VideoPlayerController? video;

  @override
  Widget build(BuildContext context) {
    if (status.hasVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (video != null && video!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: video!.value.aspectRatio,
                child: VideoPlayer(video!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppColors.white),
            ),
          if (status.hasText) _Caption(text: status.text),
          if (status.isRepost) _RepostBadge(status: status),
        ],
      );
    }

    if (!status.hasImage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Color(status.backgroundColor),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  status.text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 26,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
          if (status.isRepost) _RepostBadge(status: status),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FeedNetworkImage(
          url: status.imageUrl!,
          isDark: true,
          fit: BoxFit.contain,
          fullResolution: true,
        ),
        if (status.hasText) _Caption(text: status.text),
        if (status.isRepost) _RepostBadge(status: status),
      ],
    );
  }
}

/// Mention « repartagé de … ».
///
/// Republier le contenu de quelqu'un sans le nommer serait le lui prendre.
/// La mention remonte toujours à l'auteur d'origine, même quand on
/// repartage un repartage.
class _RepostBadge extends StatelessWidget {
  const _RepostBadge({required this.status});

  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 92,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.repeat_rounded, size: 13, color: AppColors.white),
            const SizedBox(width: 6),
            Text(
              'Repartagé de ${status.repostOfAuthorName ?? 'quelqu’un'}',
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Légende d'un statut photo ou vidéo, posée sur un dégradé pour rester
/// lisible quelle que soit l'image dessous.
class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 96),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.black.withValues(alpha: 0.75),
            ],
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 16,
            height: 1.4,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

/// Barres de progression, auteur, âge du statut, fermeture et menu.
class _Header extends StatelessWidget {
  const _Header({
    required this.statuses,
    required this.index,
    required this.progress,
    required this.canDelete,
    required this.onDelete,
    this.onReport,
  });

  final List<UserStatus> statuses;
  final int index;
  final Animation<double> progress;
  final bool canDelete;
  final VoidCallback onDelete;

  /// Signaler le statut affiché — absent sur ses propres statuts.
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final status = statuses[index];

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < statuses.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: progress,
                        builder: (context, _) => _ProgressBar(
                          // Plein à gauche du statut courant, vide à
                          // droite : la barre dit où l'on en est dans la
                          // série, pas seulement dans l'image affichée.
                          value: i < index
                              ? 1.0
                              : i == index
                                  ? progress.value
                                  : 0.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                UserAvatar(
                  name: status.authorName,
                  photoUrl: status.authorPhotoUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                      Text(
                        // L'auteur veut savoir quand ça disparaît, les
                        // autres depuis quand c'est là.
                        canDelete ? status.remainingLabel : status.ageLabel,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.white,
                    ),
                  ),
                if (onReport != null)
                  IconButton(
                    tooltip: 'Signaler',
                    onPressed: onReport,
                    icon: const Icon(
                      Icons.flag_outlined,
                      color: AppColors.white,
                    ),
                  ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Icons.close, color: AppColors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: AppColors.white.withValues(alpha: 0.3),
        valueColor: const AlwaysStoppedAnimation(AppColors.white),
      ),
    );
  }
}

/// « 12 vues » — visible du seul auteur, et cliquable pour savoir qui.
class _ViewsButton extends StatelessWidget {
  const _ViewsButton({required this.status, required this.onTap});

  final UserStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Material(
          color: AppColors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status.viewsLabel,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Qui a vu le statut. Les règles Firestore réservent cette liste à
/// l'auteur : personne d'autre ne peut la demander.
class _ViewersSheet extends StatefulWidget {
  const _ViewersSheet({required this.status});

  final UserStatus status;

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  StreamSubscription? _sub;
  List<StatusViewer>? _viewers;

  @override
  void initState() {
    super.initState();
    _sub = Get.find<StatusService>().watchViewers(
      statusId: widget.status.id,
      onData: (list) {
        if (mounted) setState(() => _viewers = list);
      },
      onError: (_) {
        if (mounted) setState(() => _viewers = const []);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewers = _viewers;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: AppColors.blackElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.whiteMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.status.viewsLabel,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: viewers == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: AppColors.orange,
                      ),
                    )
                  : viewers.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            'Personne ne l’a encore vu.',
                            style: GoogleFonts.manrope(
                              color: AppColors.whiteMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: viewers.length,
                          itemBuilder: (context, i) {
                            final viewer = viewers[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: UserAvatar(
                                name: viewer.name,
                                photoUrl: viewer.photoUrl,
                                radius: 18,
                              ),
                              title: Text(
                                viewer.name,
                                style: GoogleFonts.manrope(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
