import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/profile_controller.dart';
import '../../models/conversation.dart';
import '../../models/feed_item.dart';
import '../../models/user_status.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/status_ring.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';
import '../status/status_composer_screen.dart';
import '../status/status_viewer_screen.dart';
import '../../services/profile_gate.dart';
import '../../widgets/live_ring.dart';

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
                    child: _StatusesSection(
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
                              color: AppColors.orange,
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
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
      final uploadingPhoto = controller.isUploadingPhoto.value;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Avatar — entouré de l'anneau des statuts quand il y en a.
            // Un appui ouvre alors la visionneuse ; la pastille appareil
            // photo garde, elle, l'accès aux réglages de la photo de
            // profil, sans quoi les deux gestes se marcheraient dessus.
            Hero(
              tag: 'avatar_${profile.uid}',
              child: LiveRing(
                uid: profile.uid,
                radius: 46,
                thickness: 3,
                orElse: (avatar) => StatusRing(
                  radius: 46,
                  hasStatuses: controller.hasStatuses,
                  hasUnseen: controller.hasUnseenStatuses,
                  backgroundColor: isDark ? AppColors.black : AppColors.white,
                  onTap: controller.hasStatuses
                      ? () => _openStatuses(context, controller)
                      : (isOwn
                            ? () => _showPhotoOptions(
                                context,
                                profile.photoUrl != null,
                              )
                            : null),
                  child: avatar,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.orange.withValues(alpha: 0.2),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: UserAvatar(
                        name: profile.displayName,
                        photoUrl: profile.photoUrl,
                        radius: 46,
                        fontSize: 36,
                      ),
                    ),
                    if (uploadingPhoto)
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: AppColors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                    if (isOwn && !uploadingPhoto)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => _showPhotoOptions(
                            context,
                            profile.photoUrl != null,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                  horizontal: 10,
                  vertical: 4,
                ),
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

            // Sur son propre profil : son numéro et les contacts à
            // retrouver. Le profil personnel n'avait jusqu'ici aucune
            // zone d'action — les boutons ci-dessous ne concernent que
            // les profils d'autrui.
            if (isOwn) ...[
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.editProfile),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    'Modifier mon profil',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: BorderSide(color: muted.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _OwnProfileContacts(),
            ],

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
                          backgroundColor: following
                              ? Colors.transparent
                              : AppColors.orange,
                          foregroundColor: following ? ink : AppColors.white,
                          side: following
                              ? BorderSide(
                                  color: muted.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                          elevation: following ? 0 : 3,
                          shadowColor: AppColors.orange.withValues(alpha: 0.3),
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
                        onTap: controller.shareProfile,
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(Icons.share_outlined, color: ink, size: 20),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Signalement / blocage — exigés par l'App Store dès
                  // qu'une app diffuse du contenu d'utilisateurs.
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Material(
                      color: isDark
                          ? AppColors.blackElevated
                          : AppColors.whiteSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: _ProfileModerationMenu(isDark: isDark, ink: ink),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }

  void _showPhotoOptions(BuildContext context, bool hasPhoto) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Photo de profil',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Choisir dans la galerie',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () {
                  Get.back();
                  controller.pickProfilePhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Prendre une photo',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () {
                  Get.back();
                  controller.pickProfilePhoto(ImageSource.camera);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.orange,
                  ),
                  title: Text(
                    'Supprimer la photo',
                    style: GoogleFonts.manrope(color: ink),
                  ),
                  onTap: () {
                    Get.back();
                    controller.removeProfilePhoto();
                  },
                ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _openChat(String otherUid) async {
    if (!await ProfileGate.ensure(reason: 'Pour écrire ou appeler')) return;
    Get.toNamed(
      AppRoutes.chat,
      arguments: {
        'conversationId': Conversation.buildId(
          Get.find<AuthService>().uid,
          otherUid,
        ),
        'otherUid': otherUid,
      },
    );
  }
}

enum _ProfileAction { report, block }

/// Bloc « mes contacts » du profil personnel : le numéro du compte, et
/// l'accès au rapprochement du répertoire.
///
/// Les deux vont de pair. Enregistrer son numéro ne sert pas à
/// l'afficher — il n'apparaît sur aucun profil — mais à ce que les
/// habitants qui vous ont déjà dans leur téléphone puissent vous
/// retrouver. La formulation le dit, sans quoi personne ne comprendrait
/// pourquoi l'app réclame un numéro qu'elle ne montre pas.
class _OwnProfileContacts extends StatelessWidget {
  const _OwnProfileContacts();

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Get.toNamed(AppRoutes.contactSuggestions),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange.withValues(alpha: 0.12),
                  ),
                  child: const Icon(
                    Icons.contacts_outlined,
                    color: AppColors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mon numéro et mes contacts',
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Retrouvez les habitants de votre répertoire',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileModerationMenu extends StatelessWidget {
  const _ProfileModerationMenu({required this.isDark, required this.ink});

  final bool isDark;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ProfileController>();

    return Obx(() {
      final blocked = controller.isBlocked.value;

      return PopupMenuButton<_ProfileAction>(
        tooltip: 'Options',
        icon: Icon(Icons.more_horiz, color: ink, size: 20),
        color: isDark ? AppColors.blackElevated : AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        position: PopupMenuPosition.under,
        onSelected: (action) => switch (action) {
          _ProfileAction.report => controller.reportProfile(),
          _ProfileAction.block => controller.toggleBlock(),
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ProfileAction.report,
            height: 44,
            child: _menuRow(
              Icons.flag_outlined,
              'Signaler ce profil',
              AppColors.orange,
            ),
          ),
          PopupMenuItem(
            value: _ProfileAction.block,
            height: 44,
            child: _menuRow(
              blocked ? Icons.lock_open_rounded : Icons.block,
              blocked ? 'Débloquer' : 'Bloquer',
              blocked ? ink : AppColors.orange,
            ),
          ),
        ],
      );
    });
  }

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
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
        Text(label, style: GoogleFonts.manrope(fontSize: 12, color: muted)),
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
                  Icon(
                    Icons.grid_view_rounded,
                    size: 40,
                    color: muted.withValues(alpha: 0.4),
                  ),
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
              onTap: () =>
                  Get.toNamed(AppRoutes.feedPost, arguments: posts[i].id),
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
      FeedType.annonce => AppColors.orange,
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
                    const Icon(
                      Icons.favorite,
                      size: 12,
                      color: AppColors.white,
                    ),
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
                    const Icon(
                      Icons.chat_bubble,
                      size: 11,
                      color: AppColors.white,
                    ),
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
              item.summaryLine,
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

/// Ouvre les statuts en plein écran, puis recale l'anneau : la
/// visionneuse enregistre les vues au fur et à mesure, l'anneau doit en
/// tenir compte au retour.
Future<void> _openStatuses(
  BuildContext context,
  ProfileController controller, {
  int index = 0,
}) async {
  final list = List<UserStatus>.from(controller.statuses);
  if (list.isEmpty) return;
  await openStatusViewer(
    context,
    statuses: list,
    initialIndex: index,
    canDelete: controller.isOwnProfile,
    onDelete: controller.deleteStatus,
  );
  await controller.refreshSeenStatuses();
}

/// Choix du type de statut, puis composition, puis publication.
Future<void> _addStatus(
  BuildContext context,
  ProfileController controller,
) async {
  final source = await _askStatusKind();
  if (source == null) return;

  String? imagePath;
  String? videoPath;
  switch (source) {
    case _StatusKind.photoGallery:
      imagePath = await controller.pickStatusPhoto(ImageSource.gallery);
    case _StatusKind.photoCamera:
      imagePath = await controller.pickStatusPhoto(ImageSource.camera);
    case _StatusKind.videoGallery:
      videoPath = await controller.pickStatusVideo(ImageSource.gallery);
    case _StatusKind.videoCamera:
      videoPath = await controller.pickStatusVideo(ImageSource.camera);
    case _StatusKind.text:
      break;
  }
  // Sélecteur refermé sans rien choisir : on n'ouvre pas la composition
  // sur un média absent.
  if (source != _StatusKind.text && imagePath == null && videoPath == null) {
    return;
  }

  final draft = await Get.to<StatusDraft>(
    () => StatusComposerScreen(imagePath: imagePath, videoPath: videoPath),
  );
  if (draft == null) return;
  await controller.publishStatus(draft);
}

Future<_StatusKind?> _askStatusKind() {
  final isDark = Get.find<ThemeController>().isDarkMode;
  final ink = isDark ? AppColors.white : AppColors.black;
  final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

  return Get.bottomSheet<_StatusKind>(
    Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Nouveau statut',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Visible 24 heures, puis il disparaît.',
                style: GoogleFonts.manrope(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Choisir une photo',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () => Get.back(result: _StatusKind.photoGallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.video_library_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Choisir une vidéo',
                  style: GoogleFonts.manrope(color: ink),
                ),
                subtitle: Text(
                  '30 secondes maximum',
                  style: GoogleFonts.manrope(fontSize: 12, color: muted),
                ),
                onTap: () => Get.back(result: _StatusKind.videoGallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Prendre une photo',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () => Get.back(result: _StatusKind.photoCamera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_outlined,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Filmer une vidéo',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () => Get.back(result: _StatusKind.videoCamera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.text_fields_rounded,
                  color: AppColors.orange,
                ),
                title: Text(
                  'Écrire un texte',
                  style: GoogleFonts.manrope(color: ink),
                ),
                onTap: () => Get.back(result: _StatusKind.text),
              ),
            ],
          ),
        ),
      ),
    ),
    isScrollControlled: true,
  );
}

/// Les cinq portes d'entrée d'un statut. Photo et vidéo sont distinguées
/// dès le choix : les deux sélecteurs système ne sont pas les mêmes, et la
/// durée d'une vidéo se borne à la prise de vue.
enum _StatusKind { photoGallery, photoCamera, videoGallery, videoCamera, text }

/// Bande des statuts, sous l'en-tête du profil.
///
/// Chez soi, elle s'ouvre sur une tuile « Ajouter » et chaque statut
/// affiche son nombre de vues — c'est là qu'on vient voir qui a regardé.
/// Chez les autres, elle disparaît complètement s'il n'y a rien à montrer,
/// plutôt que de laisser un titre suivi du vide.
class _StatusesSection extends GetView<ProfileController> {
  const _StatusesSection({
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
      final statuses = controller.statuses;
      final isOwn = controller.isOwnProfile;
      if (statuses.isEmpty && !isOwn) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Statuts',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '24 h',
                  style: GoogleFonts.manrope(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: statuses.length + (isOwn ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                if (isOwn && i == 0) {
                  return _AddStatusTile(
                    isDark: isDark,
                    muted: muted,
                    ink: ink,
                    onTap: () => _addStatus(context, controller),
                  );
                }
                final index = isOwn ? i - 1 : i;
                return _StatusTile(
                  status: statuses[index],
                  isOwn: isOwn,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  onTap: () => _openStatuses(context, controller, index: index),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _AddStatusTile extends StatelessWidget {
  const _AddStatusTile({
    required this.isDark,
    required this.muted,
    required this.ink,
    required this.onTap,
  });

  final bool isDark;
  final Color muted;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 92,
                height: 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: muted.withValues(alpha: 0.35),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: AppColors.orange,
                  size: 30,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajouter',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.isOwn,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.onTap,
  });

  final UserStatus status;
  final bool isOwn;
  final bool isDark;
  final Color ink;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 92,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: status.viewedByMe || isOwn
                      ? muted.withValues(alpha: 0.3)
                      : AppColors.orange,
                  width: status.viewedByMe || isOwn ? 1 : 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: status.hasVideo
                    // Pas de vignette pour une vidéo : en extraire une
                    // demanderait de la télécharger et de la décoder pour
                    // une image de 92 pixels. Une pastille de lecture dit
                    // l'essentiel — que c'est une vidéo.
                    ? ColoredBox(
                        color: AppColors.blackElevated,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.white,
                              size: 34,
                            ),
                            if (status.hasText)
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: Text(
                                  status.text,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : status.hasImage
                    ? FeedNetworkImage(
                        url: status.imageUrl!,
                        isDark: isDark,
                        decodeWidth: 320,
                      )
                    : ColoredBox(
                        color: Color(status.backgroundColor),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text(
                              status.text,
                              maxLines: 4,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Le compteur de vues ne s'affiche qu'à l'auteur : savoir qui
          // regarde ses statuts le concerne, lui seul.
          Row(
            children: [
              Icon(
                isOwn ? Icons.visibility_outlined : Icons.schedule,
                size: 13,
                color: muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isOwn ? '${status.viewsCount}' : status.ageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOwn ? ink : muted,
                  ),
                ),
              ),
            ],
          ),
          if (isOwn)
            Text(
              status.remainingLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 11, color: muted),
            ),
        ],
      ),
    );
  }
}
