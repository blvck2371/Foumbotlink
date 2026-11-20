import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../routes/app_routes.dart';
import '../../services/moderation_service.dart';
import '../../services/push_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';

/// Préférences de l'application.
///
/// Chaque réglage ici pilote un état réel et persistant — pas de bascule
/// décorative : le thème passe par [ThemeController] (SharedPreferences),
/// les notifications par [PushService] (préférence locale + token FCM
/// retiré du compte).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final push = Get.find<PushService>();
    final moderation = Get.find<ModerationService>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Paramètres'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionTitle(label: 'Apparence', muted: muted),
            _SettingCard(
              isDark: isDark,
              child: _SettingSwitch(
                icon: Icons.dark_mode_outlined,
                title: 'Thème sombre',
                subtitle: isDark
                    ? 'L’application s’affiche en sombre.'
                    : 'L’application s’affiche en clair.',
                value: isDark,
                onChanged: themeController.setDark,
                ink: ink,
                muted: muted,
              ),
            ),
            const SizedBox(height: 22),
            _SectionTitle(label: 'Notifications', muted: muted),
            _SettingCard(
              isDark: isDark,
              child: _SettingSwitch(
                icon: Icons.notifications_active_outlined,
                title: 'Notifications push',
                // Formulation volontairement explicite : couper retire le
                // token FCM, donc les appels entrants ne sonnent plus non
                // plus. L'utilisateur doit le savoir avant de basculer.
                subtitle: push.pushEnabled.value
                    ? 'Cet appareil reçoit les messages et les appels.'
                    : 'Cet appareil ne reçoit plus ni message ni appel.',
                value: push.pushEnabled.value,
                onChanged: push.setPushEnabled,
                ink: ink,
                muted: muted,
              ),
            ),
            // Réservé aux administrateurs (`admins/{uid}`) : la file de
            // modération. Invisible pour tous les autres comptes.
            if (moderation.isAdmin.value) ...[
              const SizedBox(height: 22),
              _SectionTitle(label: 'Administration', muted: muted),
              _SettingCard(
                isDark: isDark,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.shield_outlined,
                    color: AppColors.orange,
                  ),
                  title: Text(
                    'Modération',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  subtitle: Text(
                    'Signalements à traiter',
                    style: GoogleFonts.manrope(fontSize: 12, color: muted),
                  ),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => Get.toNamed(AppRoutes.moderation),
                ),
              ),
            ],
            const SizedBox(height: 22),
            _SectionTitle(label: 'À propos', muted: muted),
            _SettingCard(
              isDark: isDark,
              child: _VersionTile(ink: ink, muted: muted),
            ),
          ],
        ),
      );
    });
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.muted});

  final String label;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: muted,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.ink,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.orange,
      secondary: Icon(icon, color: AppColors.orange),
      title: Text(
        title,
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.manrope(fontSize: 12, height: 1.35, color: muted),
      ),
    );
  }
}

/// Version installée, lue à l'exécution — jamais une chaîne recopiée à la
/// main, qui se désynchronise du `pubspec.yaml` au premier oubli.
class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.ink, required this.muted});

  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final subtitle = switch (snapshot.connectionState) {
          ConnectionState.done when info != null =>
            'Version ${info.version} (${info.buildNumber})',
          ConnectionState.done => 'Version indisponible',
          _ => 'Lecture…',
        };
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline, color: AppColors.orange),
          title: Text(
            'Foumbot Link',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.manrope(fontSize: 12, color: muted),
          ),
        );
      },
    );
  }
}
