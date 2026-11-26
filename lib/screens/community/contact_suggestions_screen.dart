import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/contacts_controller.dart';
import '../../routes/app_routes.dart';
import '../../services/contact_match_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/verified_badge.dart';

/// Retrouver, parmi les contacts de son téléphone, ceux qui sont déjà sur
/// Foumbot Link.
///
/// L'écran dit d'abord **ce qui part et ce qui ne part pas**, avant de
/// demander quoi que ce soit : on s'apprête à lire le répertoire de
/// quelqu'un, la moindre des choses est d'expliquer ce qu'on en fait.
class ContactSuggestionsScreen extends GetView<ContactsController> {
  const ContactSuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Contacts sur l’app'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _PrivacyPanel(isDark: isDark, ink: ink, muted: muted),
            const SizedBox(height: 20),
            _PhoneSection(isDark: isDark, ink: ink, muted: muted),
            const SizedBox(height: 22),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: controller.isSearching.value
                    ? null
                    : controller.findFriends,
                icon: controller.isSearching.value
                    ? const SizedBox.shrink()
                    : const Icon(Icons.contacts_outlined, size: 20),
                label: controller.isSearching.value
                    ? const FoumbotLoader.button()
                    : Text(
                        controller.hasSearched.value
                            ? 'Relancer la recherche'
                            : 'Parcourir mon répertoire',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            _Results(isDark: isDark, ink: ink, muted: muted),
          ],
        ),
      );
    });
  }
}

/// Ce qui part et ce qui ne part pas. En tête d'écran, avant le bouton —
/// pas en petits caractères après coup.
class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppColors.blue),
              const SizedBox(width: 10),
              Text(
                'Vos numéros restent sur votre téléphone',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Chaque numéro de votre répertoire est transformé en une '
            'empreinte illisible avant d’être comparé. Aucun numéro, aucun '
            'nom de votre répertoire n’est envoyé ni conservé — et ceux de '
            'vos contacts qui n’ont pas l’application ne laissent aucune '
            'trace.',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.5,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le numéro du compte : sans lui, on retrouve les autres, mais eux ne
/// nous retrouvent pas. L'écran le dit franchement.
class _PhoneSection extends GetView<ContactsController> {
  const _PhoneSection({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoadingPhone.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: FoumbotLoader()),
      );
    }

    final phone = controller.phoneNumber.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mon numéro',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          if (phone.isEmpty) ...[
            Text(
              'Ajoutez votre numéro pour que les habitants qui vous ont '
              'dans leur répertoire puissent vous retrouver. Il n’apparaît '
              'sur aucun profil.',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.45,
                color: muted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showPhoneNumberSheet(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter mon numéro'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: BorderSide(
                  color: AppColors.orange.withValues(alpha: 0.5),
                ),
              ),
            ),
          ] else
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    phone,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => showPhoneNumberSheet(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orange,
                  ),
                  child: Text(
                    'Modifier',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Saisie ou modification du numéro du compte.
///
/// Extraite dans une feuille appelable depuis le profil comme depuis cet
/// écran : c'est le même geste, il ne doit pas exister en deux versions.
Future<void> showPhoneNumberSheet(BuildContext context) async {
  final controller = Get.find<ContactsController>();
  final isDark = Get.find<ThemeController>().isDarkMode;
  final ink = isDark ? AppColors.white : AppColors.black;
  final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
  final field = TextEditingController(text: controller.phoneNumber.value);

  controller.phoneError.value = null;

  await Get.bottomSheet<void>(
    isScrollControlled: true,
    Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.blackElevated : AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Votre numéro de téléphone',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Il n’apparaît sur aucun profil et n’est jamais montré à '
                  'personne. Il sert uniquement à ce que vos connaissances '
                  'vous retrouvent.',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.45,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 16),
                FormFieldBox(
                  isDark: isDark,
                  child: Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 18, color: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: field,
                          autofocus: true,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(20),
                          ],
                          style: GoogleFonts.manrope(fontSize: 16, color: ink),
                          decoration: InputDecoration.collapsed(
                            hintText: '690 00 00 00',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (controller.phoneError.value case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: controller.isSavingPhone.value
                        ? null
                        : () async {
                            if (await controller.savePhone(field.text)) {
                              Get.back();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: AppColors.white,
                    ),
                    child: controller.isSavingPhone.value
                        ? const FoumbotLoader.button()
                        : const Text('Enregistrer'),
                  ),
                ),
                if (controller.hasPhone) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () async {
                      await controller.removePhone();
                      Get.back();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    child: const Text('Retirer mon numéro'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  field.dispose();
}

class _Results extends GetView<ContactsController> {
  const _Results({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (controller.failure.value case final failure?) {
      return _FailureNotice(failure: failure, ink: ink, muted: muted);
    }
    if (!controller.hasSearched.value) return const SizedBox.shrink();

    if (controller.matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          '${controller.scanned.value} numéro(s) parcouru(s). Aucune de vos '
          'connaissances n’est encore sur Foumbot Link — ou vous les '
          'suivez déjà toutes.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 13, height: 1.45, color: muted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.matches.length == 1
              ? '1 personne de votre répertoire'
              : '${controller.matches.length} personnes de votre répertoire',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        for (final match in controller.matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MatchTile(
              match: match,
              isDark: isDark,
              ink: ink,
              muted: muted,
            ),
          ),
      ],
    );
  }
}

class _MatchTile extends GetView<ContactsController> {
  const _MatchTile({
    required this.match,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final ContactMatch match;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final followed = controller.isFollowed(match.uid);
    final busy = controller.isBusy(match.uid);

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Get.toNamed(
          AppRoutes.userProfile,
          arguments: match.uid,
          preventDuplicates: false,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(
                name: match.displayName,
                photoUrl: match.photoUrl,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        match.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    if (match.verified) ...[
                      const SizedBox(width: 5),
                      const VerifiedBadge(size: 14),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 36,
                child: followed
                    ? OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          disabledForegroundColor: muted,
                          side: BorderSide(color: muted.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Abonné',
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: busy
                            ? null
                            : () => controller.followContact(match),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: busy
                            ? const FoumbotLoader.button()
                            : Text(
                                'S’abonner',
                                style: GoogleFonts.manrope(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({
    required this.failure,
    required this.ink,
    required this.muted,
  });

  final ContactMatchFailure failure;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (failure) {
      ContactMatchFailure.permissionRefusee => (
        'Accès au répertoire refusé',
        'Sans cette autorisation, l’application ne peut pas comparer vos '
            'contacts. Vous pouvez l’accorder dans les réglages de votre '
            'téléphone, et rien d’autre n’en dépend.',
      ),
      ContactMatchFailure.repertoireVide => (
        'Aucun numéro exploitable',
        'Votre répertoire ne contient aucun numéro reconnaissable.',
      ),
      ContactMatchFailure.erreurReseau => (
        'Recherche impossible',
        'Vérifiez votre connexion puis réessayez.',
      ),
      ContactMatchFailure.quotaAtteint => (
        'Limite du jour atteinte',
        'Vous avez fait beaucoup de recherches aujourd’hui. Elles '
            'reprennent demain — inutile de réessayer d’ici là.',
      ),
      ContactMatchFailure.indisponibleSurLeWeb => (
        'Disponible sur l’application mobile',
        'Un navigateur n’a pas accès au répertoire de votre téléphone. '
            'Ouvrez Foumbot Link sur votre téléphone pour retrouver vos '
            'contacts.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.45,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
