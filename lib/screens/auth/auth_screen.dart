import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../models/account_type.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/three_js_view.dart';

/// Parcours d'entrée dans l'application : choix de la méthode, saisie des
/// identifiants, puis configuration du compte.
///
/// La page tient en trois bandes : un bandeau incurvé qui porte la marque
/// et le titre, une carte flottante qui porte la saisie, puis l'action.
/// Quatre règles la gouvernent :
///
/// 1. **Le bandeau se rétracte dès que le clavier s'ouvre.** Il descend à
///    140 px : sur un petit téléphone, la place appartient alors au
///    formulaire, pas au décor.
/// 2. **La carte flottante isole la saisie.** Elle chevauche la courbe,
///    ce qui fixe le regard là où il y a quelque chose à faire.
/// 3. **Chaque erreur est posée sous le champ qui la provoque** — un
///    message unique en bas de page oblige à deviner lequel est en cause.
/// 4. **On sait toujours où l'on en est**, et on peut reculer d'une étape
///    sans quitter l'authentification.
class AuthScreen extends GetView<AuthController> {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      // Toutes les valeurs observées sont lues ici, dans la portée
      // synchrone du Obx : lues plus bas dans un builder différé, elles ne
      // seraient pas enregistrées comme dépendances et l'écran ne se
      // reconstruirait pas au changement d'étape.
      final step = controller.step.value;
      final emailMode = controller.emailMode.value;
      final palette = _AuthPalette.of(isDark);

      final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

      return Scaffold(
        backgroundColor: palette.background,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            _CurvedHeader(
              palette: palette,
              step: step,
              emailMode: emailMode,
              compact: keyboardUp,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chevauchement de la courbe : la carte paraît posée
                      // sur le bandeau, pas simplement dessous.
                      Transform.translate(
                        offset: const Offset(0, -26),
                        child: _StepBody(
                          palette: palette,
                          step: step,
                          emailMode: emailMode,
                        ),
                      ),
                      _FeedbackBanner(palette: palette),
                      const SizedBox(height: 16),
                      _LegalNote(palette: palette, step: step),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Bandeau incurvé
// ---------------------------------------------------------------------------

/// Bandeau de tête : dégradé orange, scène 3D en fond, titre de l'étape.
///
/// La scène three.js est **décorative**. Elle est posée derrière le
/// dégradé, avec un repli vide : si la WebView échoue ou tarde, il reste
/// un bandeau dégradé parfaitement présentable, et personne n'apprend
/// qu'une scène 3D existait.
class _CurvedHeader extends GetView<AuthController> {
  const _CurvedHeader({
    required this.palette,
    required this.step,
    required this.emailMode,
    required this.compact,
  });

  final _AuthPalette palette;
  final AuthStep step;
  final EmailMode emailMode;

  /// Clavier ouvert : le bandeau se rétracte pour rendre la hauteur au
  /// formulaire.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final height = (compact ? 140.0 : 300.0) + topInset;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: height,
      child: ClipPath(
        clipper: _HeaderClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(gradient: palette.headerGradient),
            ),
            // Scène 3D — reprise du montage déjà utilisé par l'onboarding
            // (`assets/web/onboarding.html`), avec une scène « auth »
            // dédiée : un anneau lent et des poussières, rien qui
            // distraie d'un formulaire.
            // Montée en permanence, y compris quand le bandeau se
            // rétracte : la retirer de l'arbre détruirait la WebView, et
            // refermer le clavier la rechargerait de zéro — une seconde
            // de clignotement à chaque aller-retour sur le clavier.
            const Opacity(
              opacity: 0.9,
              child: ThreeJsView(scene: 'auth', fallback: SizedBox.shrink()),
            ),
            // Voile sombre en bas : le titre blanc doit rester lisible
            // quelle que soit la position de l'anneau derrière lui.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.orangeDeep.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 46),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (controller.canGoBack)
                          _CircleButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: controller.back,
                          )
                        else
                          ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.asset(
                              'assets/branding/app_icon.png',
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                            ),
                          ),
                        const Spacer(),
                        _StepPill(step: step),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      _title(step, emailMode),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: compact ? 24 : 32,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColors.white,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 260,
                        child: Text(
                          _subtitle(step, emailMode),
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            height: 1.45,
                            color: AppColors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _title(AuthStep step, EmailMode mode) => switch (step) {
    AuthStep.choice => 'Bienvenue',
    AuthStep.emailForm =>
      mode == EmailMode.signIn ? 'Connexion' : 'Inscription',
    AuthStep.phoneForm => 'Votre numéro',
    AuthStep.phoneOtp => 'Vérification',
    AuthStep.accountSetup => 'Votre profil',
  };

  static String _subtitle(AuthStep step, EmailMode mode) => switch (step) {
    AuthStep.choice =>
      'L’actualité, le marché et les démarches de la commune, au même '
          'endroit.',
    AuthStep.emailForm =>
      mode == EmailMode.signIn
          ? 'Retrouvez votre fil et vos discussions.'
          : 'Une adresse e-mail et un mot de passe suffisent.',
    AuthStep.phoneForm => 'Un code par SMS, aucun mot de passe à retenir.',
    AuthStep.phoneOtp => 'Six chiffres, reçus à l’instant.',
    AuthStep.accountSetup =>
      'Ce nom apparaîtra sur vos publications et vos messages.',
  };
}

/// La courbe du bas du bandeau : une vague qui descend à gauche et remonte
/// à droite, reprise de la maquette.
class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 46)
      // Deux arcs successifs plutôt qu'un seul : un arc unique donne une
      // courbe symétrique, molle ; l'enchaînement creuse à gauche puis
      // relève franchement à droite.
      ..quadraticBezierTo(w * 0.30, h + 8, w * 0.58, h - 26)
      ..quadraticBezierTo(w * 0.82, h - 52, w, h - 92)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// « Étape 2 sur 3 » — un parcours de cinq écrans sans repère laissait
/// croire qu'il pouvait s'étirer indéfiniment.
class _StepPill extends StatelessWidget {
  const _StepPill({required this.step});

  final AuthStep step;

  @override
  Widget build(BuildContext context) {
    final position = switch (step) {
      AuthStep.choice => 1,
      AuthStep.emailForm || AuthStep.phoneForm || AuthStep.phoneOtp => 2,
      AuthStep.accountSetup => 3,
    };
    // Le chemin par téléphone compte une étape de plus, celle du code SMS.
    final total = step == AuthStep.phoneOtp ? 4 : 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= total; i++) ...[
            Container(
              width: i == position ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(
                  alpha: i <= position ? 1 : 0.4,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            if (i != total) const SizedBox(width: 4),
          ],
          const SizedBox(width: 9),
          Text(
            '$position/$total',
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corps de l'étape
// ---------------------------------------------------------------------------

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.palette,
    required this.step,
    required this.emailMode,
  });

  final _AuthPalette palette;
  final AuthStep step;
  final EmailMode emailMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Les deux étapes ne se superposent pas pendant la transition : la
      // sortante s'efface, l'entrante prend sa place, sinon deux
      // formulaires de hauteurs différentes se chevauchent.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(
          step == AuthStep.emailForm ? 'email-${emailMode.name}' : step.name,
        ),
        child: switch (step) {
          AuthStep.choice => _ChoiceStep(palette: palette),
          AuthStep.emailForm => _EmailStep(palette: palette),
          AuthStep.phoneForm => _PhoneStep(palette: palette),
          AuthStep.phoneOtp => _OtpStep(palette: palette),
          AuthStep.accountSetup => _AccountSetupStep(palette: palette),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Étape 1 — choix de la méthode
// ---------------------------------------------------------------------------

class _ChoiceStep extends GetView<AuthController> {
  const _ChoiceStep({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FloatingCard(
          palette: palette,
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // Le téléphone d'abord : c'est la méthode qui demande le
              // moins — pas d'adresse à posséder, pas de mot de passe à
              // retenir.
              _MethodRow(
                palette: palette,
                icon: Icons.sms_outlined,
                label: 'Continuer avec mon numéro',
                subtitle: 'Un code par SMS',
                onTap: () => controller.goTo(AuthStep.phoneForm),
              ),
              _CardDivider(palette: palette),
              _MethodRow(
                palette: palette,
                icon: Icons.mail_outline_rounded,
                label: 'Continuer avec un e-mail',
                subtitle: 'Adresse et mot de passe',
                onTap: () => controller.goTo(AuthStep.emailForm),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _PerksPanel(palette: palette),
      ],
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final _AuthPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.orange.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: AppColors.orange, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Ce qu'un compte débloque. Sous les méthodes, pas au-dessus : qui a
/// déjà décidé de se connecter n'a pas à le lire avant les boutons.
class _PerksPanel extends StatelessWidget {
  const _PerksPanel({required this.palette});

  final _AuthPalette palette;

  static const _perks = [
    (Icons.campaign_outlined, 'Publier et réagir sur le fil de la commune'),
    (Icons.storefront_outlined, 'Vendre, acheter et contacter les vendeurs'),
    (Icons.forum_outlined, 'Discuter en privé avec les autres habitants'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AVEC UN COMPTE',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: 12),
        for (final (icon, text) in _perks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.35,
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Étape 2 — e-mail
// ---------------------------------------------------------------------------

class _EmailStep extends StatefulWidget {
  const _EmailStep({required this.palette});

  final _AuthPalette palette;

  @override
  State<_EmailStep> createState() => _EmailStepState();
}

class _EmailStepState extends State<_EmailStep> {
  /// Détenu par l'état, pas recréé à chaque construction : un `FocusNode`
  /// né dans `build` fuit à chaque reconstruction et n'est jamais libéré.
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final controller = Get.find<AuthController>();
    final isSignUp = controller.emailMode.value == EmailMode.signUp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FloatingCard(
          palette: palette,
          child: Column(
            children: [
              _CardField(
                palette: palette,
                hint: 'Adresse e-mail',
                icon: Icons.mail_outline_rounded,
                controller: controller.emailCtrl,
                error: controller.emailError,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              _CardDivider(palette: palette),
              Obx(
                () => _CardField(
                  palette: palette,
                  hint: isSignUp
                      ? 'Mot de passe — 6 caractères minimum'
                      : 'Mot de passe',
                  icon: Icons.lock_outline_rounded,
                  controller: controller.passwordCtrl,
                  error: controller.passwordError,
                  focusNode: _passwordFocus,
                  obscure: controller.obscurePassword.value,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    isSignUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onSubmitted: (_) => controller.submitEmail(),
                  // Voir ce qu'on tape : sans cette bascule, la moindre
                  // faute de frappe se solde par un refus sans explication.
                  trailing: IconButton(
                    icon: Icon(
                      controller.obscurePassword.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: palette.muted,
                    ),
                    onPressed: controller.obscurePassword.toggle,
                    tooltip: controller.obscurePassword.value
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: isSignUp ? 'Créer mon compte' : 'Se connecter',
          isLoading: controller.isLoading.value,
          onPressed: controller.submitEmail,
        ),
        const SizedBox(height: 18),
        if (!isSignUp)
          Center(
            child: TextButton(
              onPressed: controller.isLoading.value
                  ? null
                  : controller.sendPasswordReset,
              style: TextButton.styleFrom(foregroundColor: AppColors.orange),
              child: Text(
                'Mot de passe oublié ?',
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Center(
          child: TextButton(
            onPressed: controller.toggleEmailMode,
            child: Text.rich(
              TextSpan(
                text: isSignUp
                    ? 'Vous avez déjà un compte ? '
                    : 'Pas encore de compte ? ',
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  color: palette.muted,
                ),
                children: [
                  TextSpan(
                    text: isSignUp ? 'Se connecter' : 'En créer un',
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.orange,
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

// ---------------------------------------------------------------------------
// Étape 2 bis — téléphone
// ---------------------------------------------------------------------------

class _PhoneStep extends GetView<AuthController> {
  const _PhoneStep({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FloatingCard(
          palette: palette,
          child: _CardField(
            palette: palette,
            hint: '+237 6XX XXX XXX',
            icon: Icons.phone_outlined,
            controller: controller.phoneCtrl,
            error: controller.phoneError,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            onSubmitted: (_) => controller.submitPhone(),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Avec l’indicatif du pays, +237 pour le Cameroun.',
            style: GoogleFonts.manrope(fontSize: 12, color: palette.muted),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Recevoir le code',
          isLoading: controller.isLoading.value,
          onPressed: controller.submitPhone,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Étape 3 — code SMS
// ---------------------------------------------------------------------------

class _OtpStep extends GetView<AuthController> {
  const _OtpStep({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FloatingCard(
          palette: palette,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.sms_outlined, size: 18, color: palette.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Envoyé au ${controller.phoneCtrl.text.trim()}',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: palette.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.goTo(AuthStep.phoneForm),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              _CardDivider(palette: palette),
              _CardField(
                palette: palette,
                hint: '– – – – – –',
                controller: controller.otpCtrl,
                error: controller.otpError,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                // Sur Android comme sur iOS, ce seul indice suffit à ce
                // que le système propose le code dès l'arrivée du SMS.
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                  color: palette.ink,
                ),
                onSubmitted: (_) => controller.submitOtp(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Vérifier',
          isLoading: controller.isLoading.value,
          onPressed: controller.submitOtp,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Étape finale — configuration du compte
// ---------------------------------------------------------------------------

class _AccountSetupStep extends GetView<AuthController> {
  const _AccountSetupStep({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final type = controller.accountType.value;
    final isStructure = type == AccountType.structure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le nom avant le type : c'est la question que tout le monde
        // remplit, quand le type reste « personnel » dans l'immense
        // majorité des cas.
        _FloatingCard(
          palette: palette,
          child: _CardField(
            palette: palette,
            hint: isStructure ? 'Nom de la structure' : 'Votre nom',
            icon: isStructure
                ? Icons.apartment_outlined
                : Icons.person_outline_rounded,
            controller: controller.nameCtrl,
            error: controller.nameError,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.name],
            onSubmitted: (_) => controller.submitAccountSetup(),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'TYPE DE COMPTE',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: 10),
        for (final t in AccountType.values) ...[
          _AccountTypeCard(
            palette: palette,
            type: t,
            selected: t == type,
            onTap: () => controller.accountType.value = t,
          ),
          if (t != AccountType.values.last) const SizedBox(height: 10),
        ],
        if (isStructure) ...[
          const SizedBox(height: 16),
          _Notice(
            palette: palette,
            color: AppColors.blue,
            icon: Icons.verified_outlined,
            title: 'Compte soumis à validation',
            body:
                'Un compte structure doit être vérifié par l’équipe Foumbot '
                'Link avant de publier des informations ou des annonces '
                'officielles. En attendant, vous pouvez consulter le fil, '
                'aimer et commenter.',
          ),
        ],
        const SizedBox(height: 26),
        _PrimaryButton(
          label: 'Terminer et entrer',
          isLoading: controller.isLoading.value,
          onPressed: controller.submitAccountSetup,
        ),
      ],
    );
  }
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.palette,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final _AuthPalette palette;
  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.orange.withValues(alpha: palette.isDark ? 0.15 : 0.07)
          : palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.orange
                  : palette.ink.withValues(alpha: 0.10),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 21,
                color: selected ? AppColors.orange : palette.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      type.description,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.35,
                        color: palette.muted,
                      ),
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

// ---------------------------------------------------------------------------
// Briques communes
// ---------------------------------------------------------------------------

/// La carte blanche qui porte la saisie, détachée du fond par son ombre.
class _FloatingCard extends StatelessWidget {
  const _FloatingCard({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
  });

  final _AuthPalette palette;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      // Ombre neutre et large : une ombre teintée sous une carte claire
      // salit la couleur au lieu de la détacher.
      shadowColor: AppColors.black.withValues(
        alpha: palette.isDark ? 0.6 : 0.16,
      ),
      elevation: 12,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: palette.ink.withValues(alpha: 0.07),
    );
  }
}

/// Champ posé dans la carte : pas de cadre, une simple ligne de saisie
/// séparée de la suivante par un filet — la structure de la maquette.
///
/// L'erreur s'affiche **sous le champ concerné**, et la ligne passe au
/// rouge : la couleur et le texte disent la même chose, pour qui
/// distingue mal l'un ou l'autre.
class _CardField extends StatelessWidget {
  const _CardField({
    required this.palette,
    required this.hint,
    required this.controller,
    required this.error,
    this.icon,
    this.trailing,
    this.focusNode,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textStyle,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
  });

  final _AuthPalette palette;
  final String hint;
  final TextEditingController controller;
  final RxnString error;
  final IconData? icon;
  final Widget? trailing;
  final FocusNode? focusNode;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(() {
      final message = error.value;
      final hasError = message != null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 19,
                    color: hasError ? AppColors.danger : palette.muted,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !auth.isLoading.value,
                    obscureText: obscure,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    inputFormatters: inputFormatters,
                    textAlign: textAlign,
                    textCapitalization: textCapitalization,
                    onSubmitted: onSubmitted,
                    // L'erreur s'efface dès la première correction :
                    // la laisser sous un champ qu'on reprend n'aide
                    // personne.
                    onChanged: (_) {
                      if (error.value != null) error.value = null;
                    },
                    style:
                        textStyle ??
                        GoogleFonts.manrope(fontSize: 15, color: palette.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      hintText: hint,
                      hintStyle:
                          (textStyle ??
                                  GoogleFonts.manrope(
                                    fontSize: 15,
                                    color: palette.ink,
                                  ))
                              .copyWith(color: palette.muted),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Bouton d'action principal — pilule en dégradé, même hauteur et même
/// poids sur toutes les étapes, pour qu'on sache toujours où appuyer.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isLoading ? 0.75 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.orangeDeep, AppColors.orange],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              // Transparent : le dégradé est peint par le conteneur, le
              // bouton n'apporte que la surface tactile et l'ondulation.
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: AppColors.white,
              disabledForegroundColor: AppColors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: GoogleFonts.manrope(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            // Fondu entre libellé et chargeur : le remplacement instantané
            // était facile à manquer, et on réappuyait.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isLoading
                  ? const FoumbotLoader.button(key: ValueKey('loading'))
                  : Text(label, key: const ValueKey('label')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retour d'exécution du serveur : refus en rouge, confirmation en vert.
/// Les deux partageaient l'orange de la marque, si bien qu'un « lien
/// envoyé » se lisait comme un échec.
class _FeedbackBanner extends GetView<AuthController> {
  const _FeedbackBanner({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final error = controller.errorMessage.value;
      final success = controller.successMessage.value;
      if (error == null && success == null) return const SizedBox.shrink();

      final isError = error != null;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _Notice(
          palette: palette,
          color: isError ? AppColors.danger : AppColors.success,
          icon: isError
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded,
          body: isError ? error : success!,
        ),
      );
    });
  }
}

/// Encadré d'information — sert au retour du serveur et à l'avis de
/// validation d'un compte structure.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.palette,
    required this.color,
    required this.icon,
    required this.body,
    this.title,
  });

  final _AuthPalette palette;
  final Color color;
  final IconData icon;
  final String body;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: palette.isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.4,
                    color: palette.muted,
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

/// Mention de fin de page, affichée seulement là où l'on s'engage —
/// inutile de la répéter sur le code SMS.
class _LegalNote extends StatelessWidget {
  const _LegalNote({required this.palette, required this.step});

  final _AuthPalette palette;
  final AuthStep step;

  @override
  Widget build(BuildContext context) {
    if (step != AuthStep.choice && step != AuthStep.emailForm) {
      return const SizedBox.shrink();
    }
    return Text(
      'En continuant, vous acceptez de respecter les règles de la '
      'communauté Foumbot Link.',
      textAlign: TextAlign.center,
      style: GoogleFonts.manrope(
        fontSize: 11.5,
        height: 1.4,
        color: palette.muted.withValues(alpha: 0.8),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.white),
        ),
      ),
    );
  }
}

/// Les couleurs de l'écran résolues une fois, puis passées aux
/// sous-widgets. Chacun les recalculait à partir de `isDark`, ce qui
/// dispersait la définition du thème dans une dizaine d'endroits.
class _AuthPalette {
  const _AuthPalette({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.card,
    required this.background,
    required this.headerGradient,
  });

  factory _AuthPalette.of(bool isDark) => _AuthPalette(
    isDark: isDark,
    ink: isDark ? AppColors.white : AppColors.black,
    muted: isDark ? AppColors.whiteMuted : AppColors.gray,
    card: isDark ? AppColors.blackElevated : AppColors.white,
    background: isDark ? AppColors.black : AppColors.white,
    headerGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.orangeDeep, AppColors.orange, AppColors.orangeSoft],
    ),
  );

  final bool isDark;
  final Color ink;
  final Color muted;
  final Color card;
  final Color background;
  final Gradient headerGradient;
}
