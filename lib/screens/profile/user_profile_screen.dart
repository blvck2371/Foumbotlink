import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/profile_controller.dart';
import '../../models/conversation.dart';
import '../../models/feed_item.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/verified_badge.dart';

class UserProfileScreen extends GetView<ProfileController> {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final profile = controller.profile.value;
      final loadingProfile = controller.isLoadingProfile.value;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        body: loadingProfile
            ? const Center(child: FoumbotLoader())
            : profile == null
                ? _EmptyState(isDark: isDark, muted: muted)
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      _ProfileAppBar(isDark: isDark, ink: ink),
                      SliverToBoxAdapter(
                        child: _ProfileHeader(
                          isDark: isDark,
                          ink: ink,
                          muted: muted,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Publications',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _PostsGrid(isDark: isDark, muted: muted),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 32),
                      ),
                    ],
                  ),
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark, required this.muted});
  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? AppColors.black : AppColors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? AppColors.white : AppColors.black,
      ),
      body: Center(
        child: Text(
          'Utilisateur introuvable',
          style: GoogleFonts.manrope(color: muted),
        ),
      ),
    );
  }
}

class _ProfileAppBar extends GetView<ProfileController> {
  const _ProfileAppBar({required this.isDark, required this.ink});
  final bool isDark;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: isDark ? AppColors.black : AppColors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      floating: true,
      snap: true,
      title: Obx(() {
        final name = controller.profile.value?.displayName ?? '';
        return Text(
          name,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        );
      }),
    );
  }
}

class _ProfileHeader extends GetView<ProfileController> {
  const _ProfileHeader({
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
      final profile = controller.profile.value;
      if (profile == null) return const SizedBox.shrink();
      final isOwn = controller.isOwnProfile;
      final following = controller.isFollowing.value;
      final toggling = controller.isToggling.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Avatar
            Hero(
              tag: 'avatar_${profile.uid}',
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.2),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: AppColors.red.withValues(alpha: 0.12),
                  child: Text(
                    profile.displayName.isNotEmpty
                        ? profile.displayName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Name + verified
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    profile.displayName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (profile.verified) ...[
                  const SizedBox(width: 6),
                  const VerifiedBadge(size: 20),
                ],
              ],
            ),

            const SizedBox(height: 4),

            // Subtitle
            Text(
              profile.authorSubtitle,
              style: GoogleFonts.manrope(fontSize: 14, color: muted),
            ),

            if (profile.verified) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.blue, Color(0xFF00BCD4)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Compte certifié',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Stats row — TikTok style
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatColumn(
                  count: profile.followingCount,
                  label: 'Abonnements',
                  ink: ink,
                  muted: muted,
                ),
                _StatDivider(muted: muted),
                _StatColumn(
                  count: profile.followersCount,
                  label: 'Abonnés',
                  ink: ink,
                  muted: muted,
                ),
                _StatDivider(muted: muted),
                _StatColumn(
                  count: controller.posts.length,
                  label: 'Posts',
                  ink: ink,
                  muted: muted,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Action buttons — TikTok style
            if (!isOwn)
              Row(
                children: [
                  // Follow button — wide
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: toggling ? null : controller.toggleFollow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              following ? Colors.transparent : AppColors.red,
                          foregroundColor:
                              following ? ink : AppColors.white,
                          side: following
                              ? BorderSide(
                                  color: muted.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                          elevation: following ? 0 : 3,
                          shadowColor: AppColors.red.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: toggling
                            ? const FoumbotLoader.button()
                            : Text(
                                following ? 'Abonné' : 'S’abonner',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Message button — icon circle (TikTok style)
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Material(
                      color: isDark
                          ? AppColors.blackElevated
                          : AppColors.whiteSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _openChat(profile.uid),
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: ink,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Share button — icon circle
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Material(
                      color: isDark
                          ? AppColors.blackElevated
                          : AppColors.whiteSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(
                          Icons.share_outlined,
                          color: ink,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }

  void _openChat(String otherUid) {
    final auth = Get.find<AuthService>();
    if (!auth.isSignedIn) {
      Get.toNamed(AppRoutes.auth);
      return;
    }
    Get.toNamed(AppRoutes.chat, arguments: {
      'conversationId': Conversation.buildId(auth.uid, otherUid),
      'otherUid': otherUid,
    });
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.muted});
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: muted.withValues(alpha: 0.2),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.count,
    required this.label,
    required this.ink,
    required this.muted,
  });

  final int count;
  final String label;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _fmt(count),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: muted,
          ),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _PostsGrid extends GetView<ProfileController> {
  const _PostsGrid({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loading = controller.isLoadingPosts.value;
      final posts = controller.posts;

      if (loading) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: FoumbotLoader()),
          ),
        );
      }

      if (posts.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.grid_view_rounded, size: 40,
                      color: muted.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    'Aucune publication',
                    style: GoogleFonts.manrope(fontSize: 15, color: muted),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 0.85,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _PostThumbnail(
              item: posts[i],
              isDark: isDark,
              onTap: () => Get.toNamed(
                AppRoutes.feedPost,
                arguments: posts[i].id,
              ),
            ),
            childCount: posts.length,
          ),
        ),
      );
    });
  }
}

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final FeedItem item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badgeColor = switch (item.type) {
      FeedType.annonce => AppColors.red,
      FeedType.info => AppColors.blue,
      FeedType.post => AppColors.gray,
    };

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background — image or colored card
            if (item.hasImages)
              CachedNetworkImage(
                imageUrl: item.imageUrls.first,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                  child: const Center(child: FoumbotLoader()),
                ),
                errorWidget: (_, _, _) => _TextThumbnail(
                  item: item,
                  badgeColor: badgeColor,
                  isDark: isDark,
                ),
              )
            else
              _TextThumbnail(
                item: item,
                badgeColor: badgeColor,
                isDark: isDark,
              ),

            // Bottom gradient overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite,
                        size: 12, color: AppColors.white),
                    const SizedBox(width: 3),
                    Text(
                      '${item.likesCount}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.chat_bubble,
                        size: 11, color: AppColors.white),
                    const SizedBox(width: 3),
                    Text(
                      '${item.commentsCount}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Type badge — top left
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.typeLabel.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextThumbnail extends StatelessWidget {
  const _TextThumbnail({
    required this.item,
    required this.badgeColor,
    required this.isDark,
  });

  final FeedItem item;
  final Color badgeColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            badgeColor.withValues(alpha: 0.15),
            badgeColor.withValues(alpha: 0.05),
          ],
        ),
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Text(
              item.title.isNotEmpty ? item.title : item.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: isDark ? AppColors.white : AppColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
