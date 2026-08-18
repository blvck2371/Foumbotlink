import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../models/account_type.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/foumbot_app_bar.dart';

class AuthScreen extends GetView<AuthController> {
  const AuthScreen({super.key});

  static const _titles = {
    AuthStep.choice: 'Se connecter',
    AuthStep.phoneForm: 'Téléphone',
    AuthStep.phoneOtp: 'Code de vérification',
    AuthStep.accountSetup: 'Configurer votre compte',
  };

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final step = controller.step.value;
      // Lu ici (dans la portée synchrone directe du Obx), pas seulement
      // à l'intérieur du LayoutBuilder/des widgets imbriqués plus bas :
      // ces derniers se construisent après la phase de build, donc un
      // Obx qui ne lirait `emailMode` que là-dedans ne le détecterait
      // pas comme dépendance et ne se redéclencherait pas au bascule
      // connexion ↔ inscription.
      final emailMode = controller.emailMode.value;

      final title = step == AuthStep.emailForm
          ? (emailMode == EmailMode.signIn ? 'Connexion' : 'Inscription')
          : _titles[step]!;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: title),
        body: Container(
          width: double.infinity,
          height: double.infinity,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AuthHero(isDark: isDark, ink: ink, muted: muted, step: step, emailMode: emailMode),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(
                              step == AuthStep.emailForm
                                  ? 'emailForm-$emailMode'
                                  : step.name,
                            ),
                            child: switch (step) {
                              AuthStep.choice =>
                                _ChoiceStep(isDark: isDark, ink: ink, muted: muted),
                              AuthStep.emailForm =>
                                _EmailStep(isDark: isDark, ink: ink, muted: muted),
                              AuthStep.phoneForm =>
                                _PhoneStep(isDark: isDark, ink: ink, muted: muted),
                              AuthStep.phoneOtp =>
                                _OtpStep(isDark: isDark, ink: ink, muted: muted),
                              AuthStep.accountSetup =>
                                _AccountSetupStep(isDark: isDark, ink: ink, muted: muted),
                            },
                          ),
                        ),
                        if (controller.errorMessage.value != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            controller.errorMessage.value!,
                            style: GoogleFonts.manrope(
                              color: AppColors.red,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// Bandeau de marque en haut de l'écran d'auth : carte de Foumbot en
/// filigrane, logo, eyebrow rouge — le même langage visuel que le fil et
/// l'onboarding, pour que la connexion se sente comme une pièce de
/// l'appli et pas un formulaire générique.
class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.step,
    this.emailMode,
  });

  final bool isDark;
  final Color ink;
  final Color muted;
  final AuthStep step;
  final EmailMode? emailMode;

  static const _subtitles = {
    AuthStep.choice: 'Un compte est nécessaire pour publier, aimer ou commenter.',
    AuthStep.phoneForm: 'Connexion par numéro de téléphone.',
    AuthStep.phoneOtp: 'Vérification du code reçu par SMS.',
    AuthStep.accountSetup: 'Dernière étape avant de rejoindre le fil.',
  };

  String get _subtitle {
    if (step == AuthStep.emailForm) {
      return emailMode == EmailMode.signIn
          ? 'Bon retour ! Connectez-vous pour retrouver votre fil.'
          : 'Créez votre compte et rejoignez la communauté.';
    }
    return _subtitles[step]!;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [AppColors.blackSoft, AppColors.blackElevated]
                : const [AppColors.whiteSoft, AppColors.white],
          ),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.18)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -60,
              top: -50,
              child: _GlowOrb(
                size: 180,
                color: AppColors.red.withValues(alpha: isDark ? 0.22 : 0.12),
              ),
            ),
            Positioned(
              left: -30,
              bottom: -60,
              child: _GlowOrb(
                size: 150,
                color: AppColors.blue.withValues(alpha: isDark ? 0.14 : 0.08),
              ),
            ),
            Positioned(
              right: -30,
              bottom: -30,
              child: Opacity(
                opacity: isDark ? 0.32 : 0.22,
                child: Image.asset(
                  isDark
                      ? 'assets/branding/map_transparent_dark.png'
                      : 'assets/branding/map_transparent_light.png',
                  height: 190,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'COMMUNE DE FOUMBOT',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Foumbot Link',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 230,
                    child: Text(
                      _subtitle,
                      style: GoogleFonts.manrope(fontSize: 13, color: muted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _ChoiceStep extends StatelessWidget {
  const _ChoiceStep({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MethodCard(
          icon: Icons.mail_outline,
          label: 'Continuer avec e-mail',
          subtitle: 'Avec une adresse e-mail et un mot de passe',
          isDark: isDark,
          onTap: () => controller.goTo(AuthStep.emailForm),
        ),
        const SizedBox(height: 12),
        _MethodCard(
          icon: Icons.phone_outlined,
          label: 'Continuer avec téléphone',
          subtitle: 'Un code reçu par SMS, sans mot de passe',
          isDark: isDark,
          onTap: () => controller.goTo(AuthStep.phoneForm),
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: AppColors.red),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(fontSize: 12, color: muted, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    final isSignUp = controller.emailMode.value == EmailMode.signUp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isSignUp)
          _SignUpPerks(isDark: isDark, ink: ink, muted: muted)
        else
          _WelcomeBackBanner(isDark: isDark),
        const SizedBox(height: 18),
        Text('E-mail', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        FormFieldBox(
          isDark: isDark,
          child: Row(
            children: [
              Icon(Icons.mail_outline, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller.emailCtrl,
                  enabled: !controller.isLoading.value,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.manrope(color: ink),
                  decoration: InputDecoration.collapsed(
                    hintText: 'vous@exemple.com',
                    hintStyle: GoogleFonts.manrope(color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Mot de passe', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        FormFieldBox(
          isDark: isDark,
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller.passwordCtrl,
                  enabled: !controller.isLoading.value,
                  obscureText: true,
                  style: GoogleFonts.manrope(color: ink),
                  decoration: InputDecoration.collapsed(
                    hintText: '6 caractères minimum',
                    hintStyle: GoogleFonts.manrope(color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isSignUp) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.sendPasswordReset,
              style: TextButton.styleFrom(foregroundColor: AppColors.blue),
              child: const Text('Mot de passe oublié ?'),
            ),
          ),
        ] else
          const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: controller.isLoading.value ? null : controller.submitEmail,
            style: isSignUp
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: AppColors.white,
                  )
                : null,
            child: _LoadingButtonLabel(
              isLoading: controller.isLoading.value,
              label: isSignUp ? 'Créer mon compte' : 'Se connecter',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: controller.toggleEmailMode,
            style: TextButton.styleFrom(foregroundColor: muted),
            child: Text.rich(
              TextSpan(
                text: isSignUp ? 'Vous avez déjà un compte ? ' : 'Pas de compte ? ',
                children: [
                  TextSpan(
                    text: isSignUp ? 'Connexion' : 'Créer un compte',
                    style: const TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bannière « Bon retour » affichée en mode connexion.
class _WelcomeBackBanner extends StatelessWidget {
  const _WelcomeBackBanner({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.white : AppColors.black).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.waving_hand_outlined, color: AppColors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bon retour !',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Connectez-vous pour retrouver votre fil.',
                  style: GoogleFonts.manrope(fontSize: 12, color: muted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d’avantages affichée en mode inscription : montre aux
/// nouveaux utilisateurs ce qu’ils pourront faire avec un compte.
class _SignUpPerks extends StatelessWidget {
  const _SignUpPerks({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: isDark ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pourquoi rejoindre ?',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          _PerkRow(icon: Icons.create_outlined, text: 'Publiez sur le fil d’actualité', muted: muted),
          const SizedBox(height: 6),
          _PerkRow(icon: Icons.favorite_border, text: 'Aimez et commentez les publications', muted: muted),
          const SizedBox(height: 6),
          _PerkRow(icon: Icons.storefront_outlined, text: 'Accédez au marché local', muted: muted),
        ],
      ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.icon, required this.text, required this.muted});

  final IconData icon;
  final String text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: GoogleFonts.manrope(fontSize: 12.5, color: muted, height: 1.3)),
        ),
      ],
    );
  }
}

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Numéro de téléphone',
          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
        ),
        const SizedBox(height: 8),
        FormFieldBox(
          isDark: isDark,
          child: Row(
            children: [
              Icon(Icons.phone_outlined, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller.phoneCtrl,
                  enabled: !controller.isLoading.value,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.manrope(color: ink),
                  decoration: InputDecoration.collapsed(
                    hintText: '+237 6XX XXX XXX',
                    hintStyle: GoogleFonts.manrope(color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Format international, ex. +237 6XX XXX XXX.',
          style: GoogleFonts.manrope(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: controller.isLoading.value ? null : controller.submitPhone,
            child: _LoadingButtonLabel(
              isLoading: controller.isLoading.value,
              label: 'Recevoir le code',
            ),
          ),
        ),
      ],
    );
  }
}

class _OtpStep extends StatelessWidget {
  const _OtpStep({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entrez le code reçu par SMS au ${controller.phoneCtrl.text.trim()}.',
          style: GoogleFonts.manrope(fontSize: 14, color: muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        FormFieldBox(
          isDark: isDark,
          child: TextField(
            controller: controller.otpCtrl,
            enabled: !controller.isLoading.value,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              color: ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
            ),
            decoration: InputDecoration.collapsed(
              hintText: '••••••',
              hintStyle: GoogleFonts.manrope(color: muted),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: controller.isLoading.value ? null : controller.submitOtp,
            child: _LoadingButtonLabel(
              isLoading: controller.isLoading.value,
              label: 'Vérifier',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => controller.goTo(AuthStep.phoneForm),
            style: TextButton.styleFrom(foregroundColor: AppColors.blue),
            child: const Text('Changer de numéro'),
          ),
        ),
      ],
    );
  }
}

class _AccountSetupStep extends StatelessWidget {
  const _AccountSetupStep({required this.isDark, required this.ink, required this.muted});

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    final type = controller.accountType.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Type de compte',
          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
        ),
        const SizedBox(height: 10),
        for (final t in AccountType.values) ...[
          _AccountTypeCard(
            type: t,
            selected: t == type,
            isDark: isDark,
            onTap: () => controller.accountType.value = t,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(
          type == AccountType.structure ? 'Nom de la structure' : 'Votre nom',
          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
        ),
        const SizedBox(height: 8),
        FormFieldBox(
          isDark: isDark,
          child: TextField(
            controller: controller.nameCtrl,
            enabled: !controller.isLoading.value,
            style: GoogleFonts.manrope(color: ink),
            decoration: InputDecoration.collapsed(
              hintText: type == AccountType.structure
                  ? 'Ex. Mairie de Foumbot, Association des Jeunes…'
                  : 'Ex. Amina N.',
              hintStyle: GoogleFonts.manrope(color: muted),
            ),
          ),
        ),
        if (type == AccountType.structure) ...[
          const SizedBox(height: 16),
          _StructureValidationNotice(isDark: isDark),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: controller.isLoading.value ? null : controller.submitAccountSetup,
            child: _LoadingButtonLabel(
              isLoading: controller.isLoading.value,
              label: 'Terminer',
            ),
          ),
        ),
      ],
    );
  }
}

/// Prévient qu'un compte structure devra être validé par l'équipe avant
/// de pouvoir publier des infos/annonces officielles — différencie
/// clairement ce parcours de celui d'un compte personnel.
class _StructureValidationNotice extends StatelessWidget {
  const _StructureValidationNotice({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_outlined, color: AppColors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compte soumis à validation',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Un compte structure doit être vérifié par l’équipe '
                  'Foumbot Link avant de pouvoir publier des informations '
                  'ou des annonces officielles. Vous pouvez déjà consulter '
                  'le fil, aimer et commenter en attendant.',
                  style: GoogleFonts.manrope(fontSize: 12, color: muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.type,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final AccountType type;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Material(
      color: selected
          ? AppColors.red.withValues(alpha: isDark ? 0.16 : 0.08)
          : (isDark ? AppColors.blackElevated : AppColors.whiteSoft),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.red : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.red : muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      type.description,
                      style: GoogleFonts.manrope(fontSize: 12, color: muted, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fondu croisé entre le libellé du bouton et un spinner pendant le
/// chargement, pour que l'action déclenchée soit visible immédiatement
/// (au lieu d'un remplacement instantané, facile à manquer).
class _LoadingButtonLabel extends StatelessWidget {
  const _LoadingButtonLabel({required this.isLoading, required this.label});

  final bool isLoading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: isLoading
          ? const FoumbotLoader.button(key: ValueKey('loading'))
          : Text(label, key: const ValueKey('label')),
    );
  }
}
