import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/notifications_controller.dart';
import '../../models/app_notification.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

class NotificationsScreen extends GetView<NotificationsController> {
  const NotificationsScreen({super.key});

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
          title: 'Notifications',
          actions: [
            if (controller.unreadCount > 0)
              TextButton(
                onPressed: controller.markAllRead,
                child: Text(
                  'Tout marquer lu',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
              ),
          ],
        ),
        body: controller.isLoading.value
            ? const Center(child: FoumbotLoader())
            : _NotificationList(isDark: isDark, ink: ink, muted: muted),
      );
    });
  }
}

class _NotificationList extends GetView<NotificationsController> {
  const _NotificationList({
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
      final list = controller.notifications;

      if (list.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 48,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Aucune notification',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Messages, likes, commentaires et\nabonnés apparaîtront ici.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 14, color: muted),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (_, i) => _NotificationTile(
          notif: list[i],
          isDark: isDark,
          ink: ink,
          muted: muted,
        ),
      );
    });
  }
}

class _NotificationTile extends GetView<NotificationsController> {
  const _NotificationTile({
    required this.notif,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final AppNotification notif;
  final bool isDark;
  final Color ink;
  final Color muted;

  ({IconData icon, Color color}) get _style => switch (notif.type) {
    AppNotificationType.message => (
      icon: Icons.chat_bubble_rounded,
      color: AppColors.blue,
    ),
    AppNotificationType.like => (
      icon: Icons.favorite_rounded,
      color: AppColors.orange,
    ),
    AppNotificationType.comment => (
      icon: Icons.mode_comment_rounded,
      color: AppColors.blue,
    ),
    AppNotificationType.follow => (
      icon: Icons.person_add_rounded,
      color: AppColors.orange,
    ),
    AppNotificationType.post => (
      icon: Icons.campaign_rounded,
      color: AppColors.orangeDeep,
    ),
    AppNotificationType.missedCall => (
      icon: Icons.call_missed_rounded,
      color: AppColors.orange,
    ),
    AppNotificationType.appUpdate => (
      icon: Icons.system_update_rounded,
      color: AppColors.blue,
    ),
    AppNotificationType.marketAlert => (
      icon: Icons.storefront_rounded,
      color: AppColors.orange,
    ),
    AppNotificationType.dossier => (
      icon: Icons.folder_open_rounded,
      color: AppColors.blue,
    ),
    AppNotificationType.moderation => (
      icon: Icons.shield_outlined,
      color: AppColors.danger,
    ),
    AppNotificationType.live => (
      icon: Icons.live_tv_rounded,
      color: AppColors.danger,
    ),
    AppNotificationType.certification => (
      icon: Icons.verified_rounded,
      color: AppColors.blue,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final s = _style;

    return Material(
      color: notif.read
          ? Colors.transparent
          : AppColors.orange.withValues(alpha: isDark ? 0.06 : 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => controller.open(notif),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(s.icon, size: 18, color: s.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif.title,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notif.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontSize: 13, color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeLabel(notif.createdAt),
                      style: GoogleFonts.manrope(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              if (!notif.read)
                Container(
                  margin: const EdgeInsets.only(top: 4, left: 6),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }
}
