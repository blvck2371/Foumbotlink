import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/compose_controller.dart';
import '../../models/feed_item.dart';
import '../../services/mention_service.dart';
import '../../utils/local_media.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/foumbot_loader.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/user_avatar.dart';

class ComposeScreen extends GetView<ComposeController> {
  const ComposeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final profile = Get.find<UserProfileService>().profile.value!;

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final official = controller.canPublishOfficialContent;
      final isEditing = controller.isEditing;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: controller.screenTitle),
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
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      _SectionLabel(
                        isEditing ? 'Publication de' : 'Publié en tant que',
                        ink: ink,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          UserAvatar(
                            name: profile.displayName,
                            photoUrl: profile.photoUrl,
                            radius: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              profile.displayName,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (official) ...[
                        const SizedBox(height: 22),
                        _SectionLabel('Type de publication', ink: ink),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _KindOption(
                                title: 'Information',
                                subtitle: 'Une info pratique pour la population',
                                selected:
                                    controller.postKind.value == FeedType.info,
                                color: AppColors.blue,
                                isDark: isDark,
                                onTap: () =>
                                    controller.selectPostKind(FeedType.info),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _KindOption(
                                title: 'Annonce officielle',
                                subtitle: 'Mise en avant, plus visible',
                                selected: controller.postKind.value ==
                                    FeedType.annonce,
                                color: AppColors.orange,
                                isDark: isDark,
                                onTap: () => controller
                                    .selectPostKind(FeedType.annonce),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      _SectionLabel('Titre (facultatif)', ink: ink),
                      const SizedBox(height: 8),
                      FormFieldBox(
                        isDark: isDark,
                        child: TextField(
                          controller: controller.titleCtrl,
                          style: GoogleFonts.manrope(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Donnez un titre, ou laissez vide',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel('Message', ink: ink),
                      const SizedBox(height: 8),
                      FormFieldBox(
                        isDark: isDark,
                        child: TextField(
                          controller: controller.bodyCtrl,
                          minLines: 4,
                          maxLines: 8,
                          style: GoogleFonts.manrope(color: ink, height: 1.4),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Écrivez votre message… @ pour '
                                'mentionner, # pour un hashtag',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),
                      _MentionSuggestions(isDark: isDark),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _InsertChip(
                            label: '@ Mentionner',
                            isDark: isDark,
                            onTap: () => controller.insertAt('@'),
                          ),
                          const SizedBox(width: 8),
                          _InsertChip(
                            label: '# Hashtag',
                            isDark: isDark,
                            onTap: () => controller.insertAt('#'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel('Photos (facultatif)', ink: ink),
                      const SizedBox(height: 10),
                      _ImagesPicker(isDark: isDark),
                      const SizedBox(height: 22),
                      _SectionLabel('Vidéo (facultatif)', ink: ink),
                      const SizedBox(height: 10),
                      _VideoPicker(isDark: isDark),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: controller.canSubmit
                          ? () async {
                              final item = await controller.submit();
                              if (item != null) Get.back(result: item);
                            }
                          : null,
                      child: controller.isPublishing.value
                          ? (controller.videoStage.value == VideoStage.none
                              ? const FoumbotLoader.button()
                              : Text(controller.progressLabel))
                          : Text(controller.submitLabel),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Material(
      color: selected
          ? color.withValues(alpha: isDark ? 0.18 : 0.1)
          : (isDark ? AppColors.blackElevated : AppColors.whiteSoft),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? color : ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.manrope(fontSize: 11, color: muted, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagesPicker extends StatelessWidget {
  const _ImagesPicker({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ComposeController>();
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      // En édition, deux sources cohabitent : les images déjà en ligne
      // (retirées de Storage à l'enregistrement si l'auteur les supprime) et
      // les fichiers ajoutés dans cette session, pas encore uploadés.
      // `FeedNetworkImage` affiche indifféremment une URL ou un chemin local,
      // ce qui permet de les rendre avec la même tuile.
      final existing = controller.existingImageUrls;
      final added = controller.images;
      final total = existing.length + added.length;
      final canAdd = controller.canAddImages;

      return SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: total + (canAdd ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == total) {
              return InkWell(
                onTap: controller.pickImages,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: muted.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.add_photo_alternate_outlined, color: muted),
                ),
              );
            }

            final isExisting = i < existing.length;
            final source = isExisting ? existing[i] : added[i - existing.length];

            return _ImageTile(
              source: source,
              isDark: isDark,
              onRemove: () => isExisting
                  ? controller.removeExistingImage(i)
                  : controller.removeImage(i - existing.length),
            );
          },
        ),
      );
    });
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.source,
    required this.isDark,
    required this.onRemove,
  });

  /// URL distante (image déjà publiée) ou chemin de fichier local.
  final String source;
  final bool isDark;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 88,
            height: 88,
            child: FeedNetworkImage(url: source, isDark: isDark),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsertChip extends StatelessWidget {
  const _InsertChip({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.orangeSoft : AppColors.orangeReadable,
            ),
          ),
        ),
      ),
    );
  }
}

/// Comptes, structures et pros proposés pendant qu'on tape « @… ».
class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ComposeController>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Obx(() {
      final list = controller.mentionSuggestions;
      if (list.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: muted.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            for (final MentionSuggestion s in list)
              ListTile(
                dense: true,
                onTap: () => controller.pickMention(s),
                leading: UserAvatar(
                  name: s.mention.name,
                  photoUrl: s.photoUrl,
                  radius: 16,
                ),
                title: Text(
                  s.mention.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                subtitle: Text(
                  s.subtitle,
                  style: GoogleFonts.manrope(fontSize: 12, color: muted),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _VideoPicker extends StatelessWidget {
  const _VideoPicker({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ComposeController>();
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      final local = controller.videoPath.value;
      final thumb = controller.videoThumbPath.value;
      final existing = controller.editing;
      final showExisting = local == null &&
          controller.keepExistingVideo.value &&
          (existing?.hasVideo ?? false);

      if (local == null && !showExisting) {
        return InkWell(
          onTap: controller.isPublishing.value ? null : controller.pickVideo,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: muted.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library_outlined, color: muted),
                const SizedBox(width: 10),
                Text(
                  'Ajouter une vidéo',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final preview = showExisting
          ? (existing!.videoThumbUrl != null
              ? FeedNetworkImage(url: existing.videoThumbUrl!, isDark: isDark)
              : null)
          : (thumb != null
              ? Image(image: LocalMedia.image(thumb), fit: BoxFit.cover)
              : null);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  color: AppColors.black,
                  child: preview ??
                      const Icon(
                        Icons.movie_outlined,
                        color: AppColors.whiteMuted,
                        size: 42,
                      ),
                ),
              ),
              const Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white70,
                    size: 52,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: InkWell(
                  onTap: controller.isPublishing.value
                      ? null
                      : controller.removeVideo,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (local != null) ...[
            const SizedBox(height: 6),
            Text(
              controller.videoWillBeReduced
                  ? 'Vidéo de ${controller.videoSizeLabel} : sa qualité sera '
                      'réduite pour un envoi plus rapide.'
                  : 'Vidéo de ${controller.videoSizeLabel}, envoyée telle '
                      'quelle.',
              style: GoogleFonts.manrope(fontSize: 12, color: muted),
            ),
          ],
          if (controller.isPublishing.value &&
              controller.videoStage.value != VideoStage.none) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: controller.videoProgress.value,
                minHeight: 6,
                color: AppColors.orange,
                backgroundColor: muted.withValues(alpha: 0.2),
              ),
            ),
          ],
        ],
      );
    });
  }
}
