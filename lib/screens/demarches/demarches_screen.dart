import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/demarche.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';

class DemarchesScreen extends StatelessWidget {
  const DemarchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: 'Démarches',
          actions: [
            IconButton(
              tooltip: 'Thème',
              onPressed: theme.toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: AppColors.red,
              ),
            ),
          ],
        ),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Services et formalités',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Retrouvez toutes les démarches administratives de la commune de Foumbot : '
                'documents requis, lieux, coûts et étapes.',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.45,
                  color: muted,
                ),
              ),
              const SizedBox(height: 24),
              for (final cat in DemarcheCategory.values) ...[
                _CategorySection(
                  category: cat,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final DemarcheCategory category;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final items = Demarche.byCategory(category);
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(category.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(
              category.label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _DemarcheCard(
            demarche: items[i],
            isDark: isDark,
            ink: ink,
            muted: muted,
          ),
        ],
      ],
    );
  }
}

class _DemarcheCard extends StatelessWidget {
  const _DemarcheCard({
    required this.demarche,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final Demarche demarche;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Get.toNamed(
          AppRoutes.demarcheDetail,
          arguments: demarche,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppColors.red,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demarche.title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      demarche.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Text(
                          demarche.delai,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(Icons.payments_outlined, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            demarche.cout,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
