import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/chat_controller.dart';
import '../../models/chat_message.dart';
import '../../routes/app_routes.dart';
import '../../services/chat_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/verified_badge.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final profile = controller.otherProfile.value;
      final name = profile?.displayName ?? 'Chat';

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _ChatAppBar(
            isDark: isDark,
            ink: ink,
            muted: muted,
            name: name,
            verified: profile?.verified ?? false,
            profileUid: profile?.uid,
            onMenu: _onMenuAction,
          ),
        ),
        body: Stack(
          children: [
            // Subtle background pattern
            _ChatBackground(isDark: isDark),

            Column(
              children: [
                // Ephemeral indicator
                _EphemeralBanner(isDark: isDark),

                // Messages
                Expanded(
                  child: controller.isLoading.value
                      ? const Center(child: FoumbotLoader())
                      : _MessageList(isDark: isDark, muted: muted),
                ),

                // Sticker panel
                _AnimatedStickerPanel(isDark: isDark),

                // Input bar
                _InputBar(isDark: isDark, ink: ink, muted: muted),
              ],
            ),
          ],
        ),
      );
    });
  }

  void _onMenuAction(String action) {
    if (action == 'ephemeral') {
      _showEphemeralSheet();
    } else if (action == 'profile') {
      final profile = controller.otherProfile.value;
      if (profile != null) {
        Get.toNamed(
          AppRoutes.userProfile,
          arguments: profile.uid,
          preventDuplicates: false,
        );
      }
    }
  }

  void _showEphemeralSheet() {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(Icons.timer_outlined, size: 32, color: AppColors.blue),
              const SizedBox(height: 10),
              Text(
                'Messages éphémères',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Les messages disparaîtront automatiquement',
                style: GoogleFonts.manrope(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 20),
              Obx(() {
                final current = controller.ephemeralSeconds.value;
                return Column(
                  children: [
                    for (final opt in _ephOptions)
                      _EphemeralOption(
                        label: opt.$2,
                        icon: opt.$3,
                        selected: opt.$1 == current,
                        isDark: isDark,
                        ink: ink,
                        onTap: () {
                          controller.setEphemeral(opt.$1);
                          Get.back();
                        },
                      ),
                  ],
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static const _ephOptions = [
    (null, 'Désactivé', Icons.block),
    (30, '30 secondes', Icons.flash_on),
    (300, '5 minutes', Icons.timer),
    (3600, '1 heure', Icons.hourglass_bottom),
    (86400, '24 heures', Icons.today),
    (604800, '7 jours', Icons.date_range),
  ];
}

class _EphemeralOption extends StatelessWidget {
  const _EphemeralOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.blue.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: selected ? AppColors.blue : ink),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.blue : ink,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.blue, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.name,
    required this.verified,
    this.profileUid,
    required this.onMenu,
  });

  final bool isDark;
  final Color ink;
  final Color muted;
  final String name;
  final bool verified;
  final String? profileUid;
  final void Function(String) onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: ink, size: 20),
              onPressed: Get.back,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: profileUid == null
                  ? null
                  : () => Get.toNamed(
                        AppRoutes.userProfile,
                        arguments: profileUid,
                        preventDuplicates: false,
                      ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: 'avatar_$profileUid',
                    child: CircleAvatar(
                      radius: 19,
                      backgroundColor: AppColors.red.withValues(alpha: 0.15),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge.small(),
                          ],
                        ],
                      ),
                      Text(
                        'en ligne',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: const Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: ink),
              color: isDark ? AppColors.blackElevated : AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ephemeral',
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, color: AppColors.blue, size: 20),
                      const SizedBox(width: 10),
                      Text('Messages éphémères',
                          style: GoogleFonts.manrope(color: ink)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, color: AppColors.red, size: 20),
                      const SizedBox(width: 10),
                      Text('Voir le profil',
                          style: GoogleFonts.manrope(color: ink)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _ChatPatternPainter(isDark: isDark),
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  _ChatPatternPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? AppColors.white : AppColors.black)
          .withValues(alpha: 0.02)
      ..style = PaintingStyle.fill;

    final rng = Random(42);
    for (var i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 2.0 + rng.nextDouble() * 4;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ChatPatternPainter old) => isDark != old.isDark;
}

class _EphemeralBanner extends GetView<ChatController> {
  const _EphemeralBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final eph = controller.ephemeralSeconds.value;
      if (eph == null || eph <= 0) return const SizedBox.shrink();

      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.blue.withValues(alpha: 0.08),
              AppColors.blue.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, size: 14, color: AppColors.blue),
            const SizedBox(width: 6),
            Text(
              'Messages éphémères : ${_ephLabel(eph)}',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.blue,
              ),
            ),
          ],
        ),
      );
    });
  }

  String _ephLabel(int s) {
    if (s <= 30) return '30s';
    if (s <= 300) return '5 min';
    if (s <= 3600) return '1h';
    if (s <= 86400) return '24h';
    return '7j';
  }
}

class _MessageList extends GetView<ChatController> {
  const _MessageList({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final msgs = controller.messages;

      if (msgs.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    size: 40, color: AppColors.red),
              ),
              const SizedBox(height: 16),
              Text(
                'Commencez la conversation !',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.white : AppColors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Envoyez un message, un vocal ou un sticker',
                style: GoogleFonts.manrope(fontSize: 13, color: muted),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        controller: controller.scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: msgs.length,
        itemBuilder: (_, i) {
          final msg = msgs[i];
          final isMine = msg.senderUid == controller.myUid;
          final showDate = i == 0 ||
              !_sameDay(msgs[i - 1].createdAt, msg.createdAt);

          return Column(
            children: [
              if (showDate)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.white : AppColors.black)
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _dateLabel(msg.createdAt),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ),
              _AnimatedBubble(
                index: i,
                child: _MessageBubble(
                  message: msg,
                  isMine: isMine,
                  isDark: isDark,
                ),
              ),
            ],
          );
        },
      );
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Aujourd’hui';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Hier';
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }
}

class _AnimatedBubble extends StatefulWidget {
  const _AnimatedBubble({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isDark;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _playerInit = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isMine = widget.isMine;
    final isDark = widget.isDark;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final time = DateFormat('HH:mm').format(msg.createdAt);

    final bgColor = isMine
        ? AppColors.red
        : (isDark ? AppColors.blackElevated : AppColors.whiteSoft);
    final textColor =
        isMine ? AppColors.white : (isDark ? AppColors.white : AppColors.black);
    final timeColor =
        isMine ? AppColors.white.withValues(alpha: 0.7) : muted;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: PhysicalModel(
          color: bgColor,
          elevation: isMine ? 2 : 1,
          shadowColor: (isMine ? AppColors.red : AppColors.black)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMine ? 20 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 20),
          ),
          child: Container(
            padding: msg.type == MessageType.image
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _buildContent(msg, textColor, isDark),
                const SizedBox(height: 4),
                Padding(
                  padding: msg.type == MessageType.image
                      ? const EdgeInsets.only(right: 8, bottom: 4)
                      : EdgeInsets.zero,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (msg.expiresAt != null) ...[
                        Icon(Icons.timer_outlined,
                            size: 10, color: timeColor),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        time,
                        style: GoogleFonts.manrope(
                            fontSize: 10, color: timeColor),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.isRead ? Icons.done_all : Icons.done,
                          size: 14,
                          color: msg.isRead ? AppColors.blue : timeColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ChatMessage msg, Color textColor, bool isDark) {
    return switch (msg.type) {
      MessageType.text => Text(
          msg.content,
          style: GoogleFonts.manrope(
            fontSize: 15,
            height: 1.4,
            color: textColor,
          ),
        ),
      MessageType.sticker => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(msg.content, style: const TextStyle(fontSize: 56)),
        ),
      MessageType.voice => _buildVoice(msg, textColor),
      MessageType.image => _buildImage(msg),
      MessageType.document => _buildDocument(msg, textColor),
    };
  }

  Widget _buildVoice(ChatMessage msg, Color textColor) {
    return GestureDetector(
      onTap: _togglePlayVoice,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: _playing ? 0.2 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: textColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                height: 28,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    color: textColor.withValues(alpha: _playing ? 0.8 : 0.4),
                    playing: _playing,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                msg.voiceDurationLabel,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayVoice() async {
    if (_playing) {
      await _player?.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }

    if (!_playerInit) {
      _player = AudioPlayer();
      _player!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      _playerInit = true;
    }

    await _player!.play(UrlSource(widget.message.content));
    if (mounted) setState(() => _playing = true);
  }

  Widget _buildImage(ChatMessage msg) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CachedNetworkImage(
        imageUrl: msg.content,
        width: 220,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          width: 220,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(child: FoumbotLoader()),
        ),
        errorWidget: (_, _, _) => Container(
          width: 220,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(Icons.broken_image_outlined, size: 32, color: AppColors.gray),
          ),
        ),
      ),
    );
  }

  Widget _buildDocument(ChatMessage msg, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.description_outlined, color: textColor, size: 22),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.fileName ?? 'Document',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              Text(
                'Appuyer pour ouvrir',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const barCount = 24;
    final gap = size.width / barCount;
    final heights = [
      0.3, 0.5, 0.8, 0.4, 1.0, 0.6, 0.9, 0.3, 0.7, 0.5, 0.4, 0.8,
      0.6, 0.9, 0.4, 1.0, 0.5, 0.7, 0.3, 0.6, 0.8, 0.4, 0.7, 0.5,
    ];

    for (var i = 0; i < barCount; i++) {
      final x = i * gap + gap / 2;
      final scale = playing ? 1.0 : 0.5;
      final h = size.height * heights[i % heights.length] * scale;
      final y1 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y1), Offset(x, y1 + h), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      playing != old.playing || color != old.color;
}

class _InputBar extends GetView<ChatController> {
  const _InputBar({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        6, 8, 6, 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Obx(() {
        final recording = controller.isRecording.value;
        final sending = controller.isSending.value;

        if (recording) return _RecordingBar(isDark: isDark);

        return Row(
          children: [
            _CircleAction(
              icon: Icons.add,
              color: AppColors.red,
              isDark: isDark,
              onTap: sending ? null : () => _showAttachMenu(context),
            ),
            _CircleAction(
              icon: Icons.emoji_emotions_outlined,
              color: muted,
              isDark: isDark,
              onTap: controller.toggleStickers,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: muted.withValues(alpha: 0.1),
                  ),
                ),
                child: TextField(
                  controller: controller.textController,
                  style: GoogleFonts.manrope(fontSize: 15, color: ink),
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    hintStyle: GoogleFonts.manrope(fontSize: 15, color: muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (sending)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: FoumbotLoader.button(),
                ),
              )
            else ...[
              GestureDetector(
                onTap: controller.startRecording,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic_rounded,
                      color: AppColors.red, size: 22),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: controller.sendText,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: AppColors.white, size: 20),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Photo',
                      color: Colors.purple,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        controller.pickAndSendImage();
                      },
                    ),
                    _AttachOption(
                      icon: Icons.description_rounded,
                      label: 'Document',
                      color: AppColors.blue,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        controller.pickAndSendDocument();
                      },
                    ),
                    _AttachOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Caméra',
                      color: AppColors.red,
                      isDark: isDark,
                      onTap: () {
                        Get.back();
                        _takePhoto();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _takePhoto() async {
    final controller = Get.find<ChatController>();
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (xfile == null) return;
    controller.isSending.value = true;
    try {
      final chatService = Get.find<ChatService>();
      final url = await chatService.uploadImage(
        xfile.path,
        controller.conversation.value?.id ?? '',
      );
      await chatService.sendMessage(
        conversationId: controller.conversation.value?.id ?? '',
        senderUid: controller.myUid,
        type: MessageType.image,
        content: url,
        ephemeralSeconds: controller.ephemeralSeconds.value,
      );
    } on Exception catch (_) {
    } finally {
      controller.isSending.value = false;
    }
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.color,
    required this.isDark,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends GetView<ChatController> {
  const _RecordingBar({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final secs = controller.recordDuration.value;
      final m = secs ~/ 60;
      final s = secs % 60;
      final label = '$m:${s.toString().padLeft(2, '0')}';

      return Row(
        children: [
          GestureDetector(
            onTap: () => controller.stopRecording(cancel: true),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline,
                  color: AppColors.red, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          _PulsingDot(),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              'Enregistrement…',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.red,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => controller.stopRecording(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: AppColors.white, size: 20),
            ),
          ),
        ],
      );
    });
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.5 + _ctrl.value * 0.5),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: _ctrl.value * 0.4),
              blurRadius: 6 + _ctrl.value * 4,
              spreadRadius: _ctrl.value * 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedStickerPanel extends GetView<ChatController> {
  const _AnimatedStickerPanel({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final show = controller.showStickers.value;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        height: show ? 200 : 0,
        child: show ? _StickerGrid(isDark: isDark) : null,
      );
    });
  }
}

class _StickerGrid extends GetView<ChatController> {
  const _StickerGrid({required this.isDark});
  final bool isDark;

  static const _categories = {
    'Émotions': ['😀', '😂', '🥰', '😎', '😢', '😡', '🤔', '🙏', '😱', '🤩'],
    'Gestes': ['👍', '👎', '👋', '✌️', '🤝', '💪', '🫶', '👏', '🙌', '✊'],
    'Symboles': ['❤️', '🔥', '💯', '🎉', '✨', '⭐', '💫', '🌈', '☀️', '🌙'],
    'Cameroun': ['🇨🇲', '🌍', '🌴', '🏠', '⚽', '🍕', '☕', '🎵', '📸', '✈️'],
  };

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        border: Border(top: BorderSide(color: muted.withValues(alpha: 0.1))),
      ),
      child: DefaultTabController(
        length: _categories.length,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              indicatorColor: AppColors.red,
              labelColor: AppColors.red,
              unselectedLabelColor: muted,
              labelStyle: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final cat in _categories.keys) Tab(text: cat),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final stickers in _categories.values)
                    GridView.count(
                      crossAxisCount: 5,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final s in stickers)
                          GestureDetector(
                            onTap: () => controller.sendSticker(s),
                            child: Center(
                              child: Text(s,
                                  style: const TextStyle(fontSize: 30)),
                            ),
                          ),
                      ],
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
