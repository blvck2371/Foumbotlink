import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/edit_profile_controller.dart';
import '../../controllers/home_controller.dart';
import '../../models/account_type.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';

/// « Modifier mon profil » : tout ce que le compte affiche, pré-rempli —
/// photo, nom, type de compte, coordonnées — et la certification.
class EditProfileScreen extends GetView<EditProfileController> {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final card = isDark ? AppColors.blackElevated : AppColors.whiteSoft;
      final profile = controller.profile.value;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Modifier mon profil'),
        body: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  Center(child: _PhotoEditor(isDark: isDark)),
                  const SizedBox(height: 28),
                  _Label('Nom affiché', muted),
                  const SizedBox(height: 8),
                  Obx(
                    () => TextField(
                      controller: controller.nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      style: GoogleFonts.manrope(color: ink, fontSize: 16),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: card,
                        counterText: '',
                        errorText: controller.nameError.value,
                        hintText: profile.accountType == AccountType.structure
                            ? 'Nom de la structure'
                            : 'Votre nom',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Label('Type de compte', muted),
                  const SizedBox(height: 8),
                  _InfoTile(
                    card: card,
                    ink: ink,
                    muted: muted,
                    icon: profile.accountType == AccountType.structure
                        ? Icons.apartment_rounded
                        : Icons.person_outline_rounded,
                    title: profile.authorSubtitle,
                    subtitle: 'Le type de compte ne peut pas être changé.',
                  ),
                  const SizedBox(height: 20),
                  _Label('Coordonnées (visibles par vous seul·e)', muted),
                  const SizedBox(height: 8),
                  Obx(
                    () => _InfoTile(
                      card: card,
                      ink: ink,
                      muted: muted,
                      icon: Icons.phone_outlined,
                      title: controller.phone.value ?? 'Aucun numéro',
                      subtitle: 'Gérer mon numéro et mes contacts',
                      onTap: () async {
                        await Get.toNamed(AppRoutes.contactSuggestions);
                        await controller.refreshContact();
                      },
                    ),
                  ),
                  Obx(() {
                    final mail = controller.email.value;
                    if (mail == null || mail.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _InfoTile(
                        card: card,
                        ink: ink,
                        muted: muted,
                        icon: Icons.alternate_email_rounded,
                        title: mail,
                        subtitle: 'Adresse de connexion',
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  Obx(
                    () => SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            controller.dirty.value && !controller.saving.value
                            ? controller.save
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: controller.saving.value
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.white,
                                ),
                              )
                            : Text(
                                'Enregistrer',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _CertificationCard(card: card, ink: ink, muted: muted),
                  const SizedBox(height: 32),
                  const _DeleteAccountButton(),
                ],
              ),
      );
    });
  }
}

/// Suppression définitive du compte (exigence du Play Store). Elle était
/// dans le tiroir, où elle débordait sur Android ; ici, elle se trouve à
/// côté de tout ce qui concerne le compte. La confirmation et le travail
/// serveur restent dans [HomeController.deleteAccount].
class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton();

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    return Obx(() {
      final deleting = home.isDeletingAccount.value;
      return SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: deleting ? null : home.deleteAccount,
          icon: deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.danger,
                  ),
                )
              : const Icon(
                  Icons.delete_forever_outlined,
                  size: 20,
                  color: AppColors.danger,
                ),
          label: Text(
            deleting ? 'Suppression…' : 'Supprimer mon compte',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    });
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.manrope(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.card,
    required this.ink,
    required this.muted,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Color card;
  final Color ink;
  final Color muted;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.orange, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoEditor extends GetView<EditProfileController> {
  const _PhotoEditor({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = controller.profile.value!;
      final busy = controller.uploadingPhoto.value;
      return GestureDetector(
        onTap: busy ? null : () => _showOptions(p.photoUrl != null),
        child: Stack(
          alignment: Alignment.center,
          children: [
            UserAvatar(
              name: p.displayName,
              photoUrl: p.photoUrl,
              radius: 48,
              fontSize: 36,
            ),
            if (busy)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: AppColors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 18,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showOptions(bool hasPhoto) {
    Get.bottomSheet(
      SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.blackElevated : AppColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () {
                  Get.back();
                  controller.pickPhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Get.back();
                  controller.pickPhoto(ImageSource.camera);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    'Retirer la photo',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  onTap: () {
                    Get.back();
                    controller.removePhoto();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Certification : progression vers les seuils (lus côté serveur dans
/// `config/certification`), puis demande.
class _CertificationCard extends GetView<EditProfileController> {
  const _CertificationCard({
    required this.card,
    required this.ink,
    required this.muted,
  });

  final Color card;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Obx(() {
        final s = controller.certification.value;
        final children = <Widget>[
          Row(
            children: [
              const VerifiedBadge(size: 22),
              const SizedBox(width: 8),
              Text(
                'Certification du compte',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ];

        if (controller.certificationLoading.value && s == null) {
          children.add(
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
          );
        } else if (s == null) {
          children.addAll([
            _text(controller.certificationError.value ?? 'Indisponible.'),
            TextButton(
              onPressed: controller.loadCertification,
              child: const Text('Réessayer'),
            ),
          ]);
        } else if (s.verified) {
          children.add(
            _text(
              'Votre compte est certifié : le badge apparaît à côté de '
              'votre nom.',
            ),
          );
        } else if (!s.enabled) {
          children.addAll([
            _chip('Bientôt disponible'),
            const SizedBox(height: 8),
            _text(
              s.isStructure
                  ? 'Les structures pourront bientôt demander la '
                        'certification de leur compte.'
                  : 'La certification des comptes arrive bientôt.',
            ),
          ]);
        } else {
          children.addAll([
            _text(
              'Le badge distingue les comptes reconnus de la commune. Il '
              'peut être demandé à partir de ${s.minFollowers} abonnés et '
              '${s.minLikes} J’aime reçus.',
            ),
            const SizedBox(height: 14),
            if (s.minFollowers > 0)
              _Progress(
                label: 'Abonnés',
                value: s.followers,
                goal: s.minFollowers,
                ink: ink,
                muted: muted,
              ),
            if (s.minLikes > 0) ...[
              const SizedBox(height: 10),
              _Progress(
                label: 'J’aime reçus',
                value: s.likes,
                goal: s.minLikes,
                ink: ink,
                muted: muted,
              ),
            ],
            const SizedBox(height: 16),
            if (s.pending)
              _chip('Demande en cours d’examen')
            else ...[
              if (s.rejected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _text(
                    'Votre précédente demande n’a pas été retenue. Vous '
                    'pouvez en refaire une.',
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: s.eligible && !controller.requesting.value
                      ? controller.requestCertification
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: BorderSide(
                      color: s.eligible
                          ? AppColors.blue
                          : muted.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    s.eligible
                        ? 'Demander la certification'
                        : 'Conditions pas encore atteintes',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      }),
    );
  }

  Widget _text(String t) => Text(
    t,
    style: GoogleFonts.manrope(fontSize: 13, height: 1.45, color: muted),
  );

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.blue.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      t,
      style: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.blue,
      ),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.value,
    required this.goal,
    required this.ink,
    required this.muted,
  });

  final String label;
  final int value;
  final int goal;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final ratio = goal <= 0 ? 1.0 : (value / goal).clamp(0.0, 1.0);
    final done = value >= goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const Spacer(),
            Text(
              '$value / $goal',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done ? AppColors.blue : muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: muted.withValues(alpha: 0.15),
            color: done ? AppColors.blue : AppColors.orange,
          ),
        ),
      ],
    );
  }
}
