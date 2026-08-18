import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/compose_controller.dart';
import '../../models/feed_item.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/foumbot_loader.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/foumbot_app_bar.dart';

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

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Nouvelle publication'),
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
                      _SectionLabel('Publié en tant que', ink: ink),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.red.withValues(alpha: 0.15),
                            child: Text(
                              profile.displayName.isNotEmpty
                                  ? profile.displayName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700,
                                color: AppColors.red,
                              ),
                            ),
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
                                color: AppColors.red,
                                isDark: isDark,
                                onTap: () => controller
                                    .selectPostKind(FeedType.annonce),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      _SectionLabel('Titre', ink: ink),
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
                            hintText: 'De quoi s’agit-il ?',
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
                            hintText: 'Écrivez votre message…',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel('Photos (facultatif)', ink: ink),
                      const SizedBox(height: 10),
                      _ImagesPicker(isDark: isDark),
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
                          ? const FoumbotLoader.button()
                          : const Text('Publier'),
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
      final images = controller.images;
      return SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length + (images.length < 5 ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == images.length) {
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
            final path = images[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(path),
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: () => controller.removeImage(i),
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
          },
        ),
      );
    });
  }
}
