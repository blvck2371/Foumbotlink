import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/conversations_controller.dart';
import '../../models/conversation.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/verified_badge.dart';

class ConversationsScreen extends GetView<ConversationsController> {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Messages'),
        floatingActionButton: _AnimatedFab(onTap: controller.startNewChat),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      AppColors.black,
                      AppColors.blackSoft,
                      AppColors.blackElevated,
                    ]
                  : const [
                      AppColors.white,
                      AppColors.whiteSoft,
                      AppColors.white,
                    ],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _SearchBar(isDark: isDark, muted: muted),
              ),
              Expanded(
                child: controller.isLoading.value
                    ? const Center(child: FoumbotLoader())
                    : _ConversationList(isDark: isDark, ink: ink, muted: muted),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _AnimatedFab extends StatefulWidget {
  const _AnimatedFab({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AnimatedFab> createState() => _AnimatedFabState();
}

class _AnimatedFabState extends State<_AnimatedFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FloatingActionButton(
        onPressed: widget.onTap,
        backgroundColor: AppColors.red,
        elevation: 6,
        child: const Icon(Icons.chat_outlined, color: AppColors.white),
      ),
    );
  }
}

class _SearchBar extends GetView<ConversationsController> {
  const _SearchBar({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: muted.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => controller.searchQuery.value = v,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: isDark ? AppColors.white : AppColors.black,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher une conversation…',
                hintStyle: GoogleFonts.manrope(fontSize: 14, color: muted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationList extends GetView<ConversationsController> {
  const _ConversationList({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final convs = controller.filtered;

      if (convs.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble_outline,
                        size: 48, color: AppColors.red),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Aucune conversation',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Commencez à discuter avec\nles membres de Foumbot !',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(fontSize: 14, color: muted),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: convs.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 68,
          color: muted.withValues(alpha: 0.1),
        ),
        itemBuilder: (_, i) => _AnimatedTile(
          index: i,
          child: _ConversationTile(
            conv: convs[i],
            isDark: isDark,
            ink: ink,
            muted: muted,
          ),
        ),
      );
    });
  }
}

class _AnimatedTile extends StatefulWidget {
  const _AnimatedTile({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_AnimatedTile> createState() => _AnimatedTileState();
}

class _AnimatedTileState extends State<_AnimatedTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
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

class _ConversationTile extends GetView<ConversationsController> {
  const _ConversationTile({
    required this.conv,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final Conversation conv;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final name = conv.otherUserName ?? 'Utilisateur';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final time = controller.timeLabel(conv.lastMessageAt);
    final hasMessage = conv.lastMessagePreview.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => controller.openChat(conv),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.15),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.red.withValues(alpha: 0.12),
                  child: Text(
                    initial,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                        ),
                        if (conv.otherUserVerified) ...[
                          const SizedBox(width: 5),
                          const VerifiedBadge.small(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasMessage
                          ? conv.lastMessagePreview
                          : 'Nouvelle conversation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: GoogleFonts.manrope(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
