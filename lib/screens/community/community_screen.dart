import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/community_controller.dart';
import '../../models/conversation.dart';
import '../../models/user_profile.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/verified_badge.dart';

class CommunityScreen extends GetView<CommunityController> {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Communauté'),
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Membres de Foumbot',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Découvrez et suivez les habitants et structures de la commune.',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.4,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SearchBar(isDark: isDark, muted: muted),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller.isLoading.value
                    ? const Center(child: FoumbotLoader())
                    : RefreshIndicator(
                        color: AppColors.red,
                        backgroundColor:
                            isDark ? AppColors.blackElevated : AppColors.white,
                        onRefresh: controller.refresh,
                        child: _MemberList(isDark: isDark),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SearchBar extends GetView<CommunityController> {
  const _SearchBar({required this.isDark, required this.muted});

  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: muted.withValues(alpha: 0.2)),
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
                hintText: 'Rechercher un membre…',
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

class _MemberList extends GetView<CommunityController> {
  const _MemberList({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final members = controller.filteredMembers;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      if (members.isEmpty) {
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
                  Icon(Icons.people_outline, size: 48, color: muted),
                  const SizedBox(height: 14),
                  Text(
                    'Aucun membre trouvé.',
                    style: GoogleFonts.manrope(fontSize: 15, color: muted),
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
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _MemberCard(
          profile: members[i],
          isDark: isDark,
        ),
      );
    });
  }
}

class _MemberCard extends GetView<CommunityController> {
  const _MemberCard({
    required this.profile,
    required this.isDark,
  });

  final UserProfile profile;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      final isOwn = controller.isOwnProfile(profile.uid);
      final following = controller.isFollowing(profile.uid);
      final toggling = controller.togglingSet.contains(profile.uid);

      return Material(
        color: isDark ? AppColors.blackElevated : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => Get.toNamed(
            AppRoutes.userProfile,
            arguments: profile.uid,
            preventDuplicates: false,
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: profile.verified
                    ? AppColors.blue.withValues(alpha: 0.2)
                    : muted.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.red.withValues(alpha: 0.15),
                  child: Text(
                    profile.displayName.isNotEmpty
                        ? profile.displayName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                          ),
                          if (profile.verified) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge.small(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.authorSubtitle,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${_formatCount(profile.followersCount)} abonné${profile.followersCount > 1 ? 's' : ''}',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_formatCount(profile.followingCount)} abonnement${profile.followingCount > 1 ? 's' : ''}',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isOwn) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.chat_outlined,
                        size: 18,
                        color: AppColors.blue,
                      ),
                      onPressed: () {
                        final auth = Get.find<AuthService>();
                        if (!auth.isSignedIn) return;
                        Get.toNamed(AppRoutes.chat, arguments: {
                          'conversationId': Conversation.buildId(
                            auth.uid,
                            profile.uid,
                          ),
                          'otherUid': profile.uid,
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    height: 34,
                    child: toggling
                        ? const SizedBox(
                            width: 34,
                            child: FoumbotLoader.button(),
                          )
                        : OutlinedButton(
                            onPressed: () =>
                                controller.toggleFollow(profile.uid),
                            style: OutlinedButton.styleFrom(
                              backgroundColor:
                                  following ? Colors.transparent : AppColors.red,
                              foregroundColor:
                                  following ? AppColors.red : AppColors.white,
                              side: BorderSide(
                                color: AppColors.red,
                                width: following ? 1.5 : 0,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              following ? 'Abonné' : 'Suivre',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
