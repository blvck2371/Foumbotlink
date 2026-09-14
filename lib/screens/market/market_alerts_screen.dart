import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/saved_search.dart';
import '../../services/auth_service.dart';
import '../../services/saved_search_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';

/// Mes alertes — les recherches enregistrées depuis le marché.
///
/// C'est ce qui remplace le passage quotidien dans la grille : on décrit
/// une fois ce qu'on cherche, et une notification arrive quand une
/// annonce correspondante est publiée.
class MarketAlertsScreen extends StatelessWidget {
  const MarketAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final auth = Get.find<AuthService>();
    final service = Get.find<SavedSearchService>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Mes alertes'),
        body: !auth.isSignedIn
            ? _Message(
                icon: Icons.lock_outline,
                text: 'Connectez-vous pour créer des alertes.',
                ink: ink,
                muted: muted,
              )
            : StreamBuilder<List<SavedSearch>>(
                stream: service.watch(auth.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: FoumbotLoader());
                  }
                  final alerts = snapshot.data ?? const <SavedSearch>[];
                  if (alerts.isEmpty) {
                    return _Message(
                      icon: Icons.notifications_none,
                      text: 'Aucune alerte pour l’instant.',
                      hint: 'Depuis le marché, réglez vos filtres puis '
                          'appuyez sur « Créer une alerte ».',
                      ink: ink,
                      muted: muted,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: alerts.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Vous recevez une notification dès qu’une annonce '
                            'correspond à l’un de ces critères.',
                            style: GoogleFonts.manrope(
                              fontSize: 13.5,
                              height: 1.45,
                              color: muted,
                            ),
                          ),
                        );
                      }
                      final alert = alerts[i - 1];
                      return _AlertTile(
                        alert: alert,
                        isDark: isDark,
                        onToggle: (value) => service.setActive(
                          uid: auth.uid,
                          id: alert.id,
                          active: value,
                        ),
                        onDelete: () async {
                          final ok = await _confirmDelete(alert.label);
                          if (ok) {
                            await service.delete(uid: auth.uid, id: alert.id);
                          }
                        },
                      );
                    },
                  );
                },
              ),
      );
    });
  }

  Future<bool> _confirmDelete(String label) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Supprimer l’alerte ?'),
        content: Text('« $label » ne vous préviendra plus.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.alert,
    required this.isDark,
    required this.onToggle,
    required this.onDelete,
  });

  final SavedSearch alert;
  final bool isDark;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  alert.criteriaLabel,
                  style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          Switch(
            value: alert.active,
            activeThumbColor: AppColors.orange,
            onChanged: onToggle,
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: muted),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.ink,
    required this.muted,
    this.hint,
  });

  final IconData icon;
  final String text;
  final String? hint;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: muted),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.45,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
