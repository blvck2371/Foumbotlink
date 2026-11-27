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
import '../../widgets/chat_video_viewer.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/post_image_viewer.dart';
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
                      _SectionLabel('Photos et vidéo (facultatif)', ink: ink),
                      const SizedBox(height: 10),
                      _MediaPicker(isDark: isDark),
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


/// Photos et vidéo de la publication, choisies ensemble.
///
/// Un seul « + » ouvre la galerie sur les photos et les vidéos, avec
/// sélection multiple. Chaque média choisi se touche pour être vu en grand
/// — photo dans la visionneuse, vidéo dans le lecteur — avant de publier.
class _MediaPicker extends StatelessWidget {
  const _MediaPicker({required this.isDark});

  final bool isDark;

  static const _tile = 96.0;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ComposeController>();
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      final busy = controller.isPublishing.value;
      final keptVideos = controller.existingVideos.toList();
      final addedVideos = controller.newVideos.toList();
      // En édition, deux sources de photos cohabitent : celles déjà en
      // ligne et celles ajoutées dans cette session. `FeedNetworkImage`
      // affiche indifféremment une URL ou un chemin local.
      final existing = controller.existingImageUrls.toList();
      final added = controller.images.toList();
      final photos = [...existing, ...added];

      final tiles = <Widget>[
        for (var i = 0; i < keptVideos.length; i++)
          _VideoTile(
            isDark: isDark,
            remoteThumb: keptVideos[i].thumbUrl,
            label: keptVideos[i].durationLabel,
            onRemove: busy ? null : () => controller.removeExistingVideo(i),
            onTap: () => openChatVideoViewer(
              context,
              source: keptVideos[i].url,
              heroTag: 'compose_video_kept_$i',
            ),
          ),
        for (var i = 0; i < addedVideos.length; i++)
          _VideoTile(
            isDark: isDark,
            localThumb: addedVideos[i].thumbPath,
            label: addedVideos[i].durationLabel,
            onRemove: busy ? null : () => controller.removeNewVideo(i),
            onTap: () => openChatVideoViewer(
              context,
              source: addedVideos[i].path,
              heroTag: 'compose_video_new_$i',
            ),
          ),
        for (var i = 0; i < photos.length; i++)
          _MediaTile(
            isDark: isDark,
            onRemove: busy
                ? null
                : () => i < existing.length
                    ? controller.removeExistingImage(i)
                    : controller.removeImage(i - existing.length),
            onTap: () => openPostImageViewer(
              context,
              imageUrls: photos,
              initialIndex: i,
              heroPrefix: 'compose',
            ),
            child: FeedNetworkImage(
              url: photos[i],
              isDark: isDark,
              decodeWidth: 300,
            ),
          ),
        if (controller.canAddMedia && !busy)
          InkWell(
            onTap: controller.pickMedia,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: _tile,
              height: _tile,
              decoration: BoxDecoration(
                color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: muted.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.perm_media_outlined, color: muted),
                  const SizedBox(height: 6),
                  Text(
                    'Ajouter',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ];

      final count = photos.length + keptVideos.length + addedVideos.length;
      final toReduce = controller.videosToReduce;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _tile,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => tiles[i],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            count == 0
                ? 'Jusqu’à ${ComposeController.maxImages} photos et '
                    '${ComposeController.maxVideos} vidéos, choisies ensemble '
                    'dans la galerie.'
                : 'Touchez un média pour le voir en grand avant de publier.',
            style: GoogleFonts.manrope(fontSize: 12, color: muted),
          ),
          if (toReduce > 0) ...[
            const SizedBox(height: 4),
            Text(
              toReduce == 1 && addedVideos.length == 1
                  ? 'Vidéo de plus de 8 Mo : sa qualité sera réduite pour un '
                      'envoi plus rapide.'
                  : '$toReduce vidéo${toReduce > 1 ? 's' : ''} de plus de '
                      '8 Mo : leur qualité sera réduite pour un envoi plus '
                      'rapide.',
              style: GoogleFonts.manrope(fontSize: 12, color: muted),
            ),
          ],
          if (busy && controller.videoStage.value != VideoStage.none) ...[
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

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.isDark,
    required this.child,
    required this.onTap,
    required this.onRemove,
  });

  final bool isDark;
  final Widget child;
  final VoidCallback onTap;

  /// `null` pendant la publication : on ne retire rien en cours d'envoi.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _MediaPicker._tile,
      height: _MediaPicker._tile,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: Semantics(
                button: true,
                label: 'Retirer',
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.isDark,
    required this.label,
    required this.onTap,
    required this.onRemove,
    this.localThumb,
    this.remoteThumb,
  });

  final bool isDark;
  final String label;
  final String? localThumb;
  final String? remoteThumb;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _MediaTile(
      isDark: isDark,
      onRemove: onRemove,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.black),
          if (localThumb != null)
            Image(image: LocalMedia.image(localThumb!), fit: BoxFit.cover)
          else if (remoteThumb != null)
            FeedNetworkImage(url: remoteThumb!, isDark: true),
          const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white,
              size: 34,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: _TileBadge(label.isEmpty ? 'Vidéo' : label),
          ),
        ],
      ),
    );
  }
}
