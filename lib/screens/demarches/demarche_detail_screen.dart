import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/demarche.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';

class DemarcheDetailScreen extends StatelessWidget {
  const DemarcheDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final demarche = Get.arguments as Demarche;
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: demarche.title),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      demarche.category.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            demarche.title,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            demarche.category.label,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                demarche.description,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.5,
                  color: muted,
                ),
              ),
              const SizedBox(height: 24),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Lieu',
                value: demarche.lieu,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.payments_outlined,
                label: 'Coût',
                value: demarche.cout,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.access_time,
                label: 'Délai',
                value: demarche.delai,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                icon: Icons.folder_outlined,
                title: 'Documents requis',
                ink: ink,
              ),
              const SizedBox(height: 12),
              ...demarche.documents.map(
                (doc) => _BulletItem(text: doc, muted: muted, isDark: isDark),
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                icon: Icons.format_list_numbered,
                title: 'Étapes à suivre',
                ink: ink,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < demarche.etapes.length; i++)
                _StepItem(
                  index: i + 1,
                  text: demarche.etapes[i],
                  isLast: i == demarche.etapes.length - 1,
                  ink: ink,
                  muted: muted,
                  isDark: isDark,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ink,
    required this.muted,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color ink;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.ink,
  });

  final IconData icon;
  final String title;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: AppColors.red),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({
    required this.text,
    required this.muted,
    required this.isDark,
  });

  final String text;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.45,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.index,
    required this.text,
    required this.isLast,
    required this.ink,
    required this.muted,
    required this.isDark,
  });

  final int index;
  final String text;
  final bool isLast;
  final Color ink;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.red.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
