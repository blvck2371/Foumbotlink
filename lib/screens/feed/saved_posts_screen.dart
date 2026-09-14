import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/saved_posts_controller.dart';
import '../../models/feed_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_skeleton.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/post_media.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';

class SavedPostsScreen extends GetView<SavedPostsController> {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Scaffold(
      backgroundColor: isDark ? AppColors.black : AppColors.whiteSoft,
      appBar: FoumbotAppBar(isDark: isDark, title: 'Enregistrés'),
      body: RefreshIndicator(
        color: AppColors.orange,
        backgroundColor: isDark ? AppColors.blackElevated : AppColors.white,
        onRefresh: controller.load,
        child: Obx(() {
          if (controller.isLoading.value) {
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, _) => FeedCardSkeleton(isDark: isDark),
            );
          }

          final items = controller.items;
          if (items.isEmpty) {
            // `ListView` et non `Center` : sans zone défilable, le
            // tirer-pour-rafraîchir ne fonctionnerait pas sur l'état vide.
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                Icon(Icons.bookmark_border, size: 52, color: muted),
                const SizedBox(height: 16),
                Text(
                  'Aucune publication enregistrée',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Touchez le signet d’une publication pour la retrouver ici.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.4,
                      color: muted,
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final post = items[i];
              return _SavedCard(
                key: ValueKey(post.id),
                post: post,
                isDark: isDark,
                ink: ink,
                muted: muted,
                timeLabel: controller.timeAgo(post.publishedAt),
                onOpen: () => controller.open(post),
                onUnsave: () => controller.unsave(post),
              );
            },
          );
        }),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    super.key,
    required this.post,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.timeLabel,
    required this.onOpen,
    required this.onUnsave,
  });

  final FeedItem post;
  final bool isDark;
  final Color ink;
  final Color muted;
  final String timeLabel;
  final VoidCallback onOpen;
  final VoidCallback onUnsave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.orange.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    name: post.authorName,
                    photoUrl: post.authorPhotoUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                            ),
                            if (post.authorVerified) ...[
                              const SizedBox(width: 5),
                              const VerifiedBadge.small(),
                            ],
                          ],
                        ),
                        Text(
                          timeLabel,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer des enregistrements',
                    icon: const Icon(
                      Icons.bookmark,
                      color: AppColors.orange,
                    ),
                    onPressed: onUnsave,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Titre et message facultatifs — voir `FeedItem.hasTitle`.
              if (post.hasTitle) ...[
                Text(
                  post.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: ink,
                  ),
                ),
                if (post.hasBody) const SizedBox(height: 6),
              ],
              if (post.hasBody)
                Text(
                  post.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.4,
                    color: muted,
                  ),
                ),
              if (!post.hasTitle && !post.hasBody && post.hasImages)
                Text(
                  post.summaryLine,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.4,
                    color: muted,
                  ),
                ),
              if (post.hasImages) ...[
                const SizedBox(height: 10),
                PostMedia(
                  imageUrls: post.imageUrls,
                  isDark: isDark,
                  heroPrefix: 'saved_${post.id}',
                  borderRadius: 12,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
