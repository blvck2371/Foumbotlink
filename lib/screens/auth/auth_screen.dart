import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/home_controller.dart';
import '../../models/account_type.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';

/// Parcours d'entrée dans l'application.
///
/// Trois écrans, toujours dans le même ordre logique :
///
/// 1. **Identifiants** — un seul écran. En haut, l'intention : « Créer un
///    compte » ou « Se connecter ». Dessous, le formulaire de la méthode
///    retenue (numéro par défaut), puis le bouton. Changer de méthode se
///    fait par un bouton secondaire sous l'action principale.
/// 2. **Code SMS** — uniquement par le chemin téléphone.
/// 3. **Profil** — uniquement pour un compte qui n'en a pas encore.
///
/// Chaque écran a la même ossature, sur un fond uni à peine réchauffé
/// d'un halo orange : un pictogramme, le titre, une phrase, les champs,
/// l'action principale. L'ancien bandeau orange incurvé (avec sa scène
/// 3D en WebView) prenait le tiers de l'écran, écrasait le texte blanc à
/// un contraste insuffisant et se rétractait brusquement à l'ouverture du
/// clavier : il est remplacé par cette mise en page plus calme.
class AuthScreen extends GetView<AuthController> {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      // Toutes les valeurs observées sont lues ici, dans la portée
      // synchrone du Obx, puis transmises : lues dans le `build` d'un
      // sous-widget, elles ne seraient pas suivies.
      final palette = _AuthPalette.of(themeController.isDarkMode);
      final state = _AuthState(
        step: controller.step.value,
        mode: controller.mode.value,
        method: controller.method.value,
        accountType: controller.accountType.value,
      );
      final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: palette.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
        child: Scaffold(
          backgroundColor: palette.background,
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              // Le halo : la seule touche de couleur de fond. Assez discret
              // pour ne jamais gêner la lecture, assez présent pour qu'on
              // reconnaisse l'app.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.6, -1.15),
                        radius: 1.1,
                        colors: [
                          AppColors.orange.withValues(
                            alpha: palette.isDark ? 0.20 : 0.14,
                          ),
                          AppColors.orange.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(palette: palette, state: state),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                        child: Center(
                          // Sur tablette, un formulaire étiré sur toute la
                          // largeur se lit mal.
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: AutofillGroup(
                              child: _StepBody(
                                palette: palette,
                                state: state,
                                compact: keyboardUp,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Instantané de l'état observé, passé tel quel aux sous-widgets.
class _AuthState {
  const _AuthState({
    required this.step,
    required this.mode,
    required this.method,
    required this.accountType,
  });

  final AuthStep step;
  final AuthMode mode;
  final AuthMethod method;
  final AccountType accountType;

  bool get isSignUp => mode == AuthMode.signUp;
  bool get isPhone => method == AuthMethod.phone;

  /// Clé de l'écran courant pour l'animation de transition. Le mode et la
  /// méthode n'en font pas partie : basculer d'onglet ne doit pas faire
  /// clignoter tout l'écran.
  String get key => step.name;

  /// Progression, affichée seulement là où elle a un sens : pendant une
  /// inscription. Une connexion se fait en un écran (deux par SMS) —
  /// « 1/3 » y laissait croire à un long parcours.
  (int, int)? get progress {
    final total = isPhone ? 3 : 2;
    return switch (step) {
      AuthStep.credentials => isSignUp ? (1, total) : null,
      AuthStep.phoneOtp => isSignUp ? (2, 3) : null,
      AuthStep.accountSetup => (total, total),
    };
  }

  String get title => switch (step) {
    AuthStep.credentials => isSignUp ? 'Bienvenue à Foumbot' : 'Bon retour',
    AuthStep.phoneOtp => 'Vérifiez votre numéro',
    AuthStep.accountSetup => 'Votre profil',
  };

  String get subtitle => switch (step) {
    AuthStep.credentials =>
      isSignUp
          ? 'L’actualité, le marché et les démarches de la ville, au même '
                'endroit.'
          : 'Connectez-vous pour retrouver votre fil et vos discussions.',
    AuthStep.phoneOtp => 'Saisissez les six chiffres reçus par SMS.',
    AuthStep.accountSetup =>
      'Dernière étape : comment doit-on vous présenter ?',
  };
}

// ---------------------------------------------------------------------------
// Barre du haut
// ---------------------------------------------------------------------------

/// En haut à gauche, toujours le geste attendu à cet endroit : fermer sur
/// le premier écran, revenir sur le code SMS. Le profil n'a ni l'un ni
/// l'autre (le compte est déjà créé). À droite, la progression.
class _TopBar extends GetView<AuthController> {
  const _TopBar({required this.palette, required this.state});

  final _AuthPalette palette;
  final _AuthState state;

  @override
  Widget build(BuildContext context) {
    final leading = switch (state.step) {
      AuthStep.credentials => _CircleButton(
        palette: palette,
        icon: Icons.close_rounded,
        tooltip: 'Fermer',
        onTap: Get.back,
      ),
      AuthStep.phoneOtp => _CircleButton(
        palette: palette,
        icon: Icons.arrow_back_rounded,
        tooltip: 'Retour',
        onTap: controller.back,
      ),
      AuthStep.accountSetup => const SizedBox(width: 40, height: 40),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
      child: Row(
        children: [
          leading,
          const Spacer(),
          if (state.progress case (final position, final total))
            _StepDots(palette: palette, position: position, total: total),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({
    required this.palette,
    required this.position,
    required this.total,
  });

  final _AuthPalette palette;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Étape $position sur $total',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= total; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: i == position ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i <= position
                    ? palette.accent
                    : palette.ink.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (i != total) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corps de l'écran
// ---------------------------------------------------------------------------

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.palette,
    required this.state,
    required this.compact,
  });

  final _AuthPalette palette;
  final _AuthState state;

  /// Clavier ouvert : le pictogramme et la phrase d'accroche s'effacent
  /// pour laisser la place au champ en cours de saisie.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(state.key),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(palette: palette, state: state, compact: compact),
          SizedBox(height: compact ? 18 : 28),
          switch (state.step) {
            AuthStep.credentials => _CredentialsStep(
              palette: palette,
              state: state,
            ),
            AuthStep.phoneOtp => _OtpStep(palette: palette),
            AuthStep.accountSetup => _AccountSetupStep(
              palette: palette,
              state: state,
            ),
          },
          _LegalNote(palette: palette, state: state),
        ],
      ),
    );
  }
}

/// Pictogramme, titre, phrase d'accroche.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.palette,
    required this.state,
    required this.compact,
  });

  final _AuthPalette palette;
  final _AuthState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: compact
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 22),
                  child: _badge(),
                ),
        ),
        Text(
          state.title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: compact ? 24 : 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.6,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.subtitle,
          style: GoogleFonts.manrope(
            fontSize: 15,
            height: 1.45,
            color: palette.muted,
          ),
        ),
      ],
    );
  }

  /// Le logo pour entrer, un pictogramme pour les étapes suivantes : on
  /// voit d'un coup d'œil ce que l'écran demande.
  Widget _badge() {
    if (state.step == AuthStep.credentials) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          'assets/branding/app_icon.png',
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: palette.accentTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        state.step == AuthStep.phoneOtp
            ? Icons.sms_outlined
            : Icons.person_outline_rounded,
        size: 28,
        color: palette.accent,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 1 — identifiants
// ---------------------------------------------------------------------------

class _CredentialsStep extends StatefulWidget {
  const _CredentialsStep({required this.palette, required this.state});

  final _AuthPalette palette;
  final _AuthState state;

  @override
  State<_CredentialsStep> createState() => _CredentialsStepState();
}

class _CredentialsStepState extends State<_CredentialsStep> {
  /// Détenu par l'état : un `FocusNode` né dans `build` fuit à chaque
  /// reconstruction.
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final state = widget.state;
    final controller = Get.find<AuthController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. L'intention, d'abord.
        _SegmentedTabs<AuthMode>(
          palette: palette,
          value: state.mode,
          onChanged: controller.setMode,
          options: const [
            (AuthMode.signUp, 'Créer un compte'),
            (AuthMode.signIn, 'Se connecter'),
          ],
        ),
        const SizedBox(height: 24),

        // 2. Le formulaire de la méthode choisie.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: state.isPhone
              ? _phoneFields(palette, controller)
              : _emailFields(palette, controller, state.isSignUp),
        ),
        const SizedBox(height: 24),

        // 3. L'action, avec la réponse du serveur juste au-dessus : on la
        // lit là où l'on regarde.
        _FeedbackBanner(palette: palette),
        _PrimaryButton(
          palette: palette,
          label: switch ((state.method, state.mode)) {
            (AuthMethod.phone, _) => 'Recevoir le code',
            (AuthMethod.email, AuthMode.signUp) => 'Créer mon compte',
            (AuthMethod.email, AuthMode.signIn) => 'Se connecter',
          },
          onPressed: controller.submitCredentials,
        ),

        // 4. L'autre méthode, en retrait.
        const SizedBox(height: 20),
        _OrDivider(palette: palette),
        const SizedBox(height: 20),
        _SecondaryButton(
          palette: palette,
          icon: state.isPhone
              ? Icons.mail_outline_rounded
              : Icons.phone_iphone_rounded,
          label: state.isPhone
              ? 'Continuer avec un e-mail'
              : 'Continuer avec mon numéro',
          onPressed: () => controller.setMethod(
            state.isPhone ? AuthMethod.email : AuthMethod.phone,
          ),
        ),
      ],
    );
  }

  Widget _phoneFields(_AuthPalette palette, AuthController controller) {
    return _LabeledField(
      key: const ValueKey('phone'),
      palette: palette,
      label: 'Numéro de téléphone',
      helper: 'Vous recevrez un code par SMS. Aucun mot de passe à retenir.',
      hint: '+237 6XX XXX XXX',
      icon: Icons.phone_iphone_rounded,
      controller: controller.phoneCtrl,
      error: controller.phoneError,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumber],
      onSubmitted: (_) => controller.submitPhone(),
    );
  }

  Widget _emailFields(
    _AuthPalette palette,
    AuthController controller,
    bool isSignUp,
  ) {
    return Column(
      key: const ValueKey('email'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledField(
          palette: palette,
          label: 'Adresse e-mail',
          hint: 'nom@exemple.com',
          icon: Icons.mail_outline_rounded,
          controller: controller.emailCtrl,
          error: controller.emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email, AutofillHints.username],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 18),
        Obx(
          () => _LabeledField(
            palette: palette,
            label: 'Mot de passe',
            // Le « mot de passe oublié » vit à côté du champ concerné,
            // pas perdu entre deux liens sous le bouton.
            labelAction: isSignUp
                ? null
                : _InlineLink(
                    palette: palette,
                    label: 'Oublié ?',
                    onTap: controller.sendPasswordReset,
                  ),
            helper: isSignUp ? 'Six caractères minimum.' : null,
            hint: isSignUp
                ? 'Choisissez un mot de passe'
                : 'Votre mot de passe',
            icon: Icons.lock_outline_rounded,
            controller: controller.passwordCtrl,
            error: controller.passwordError,
            focusNode: _passwordFocus,
            obscure: controller.obscurePassword.value,
            textInputAction: TextInputAction.done,
            autofillHints: [
              isSignUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onSubmitted: (_) => controller.submitEmail(),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 2 — code SMS
// ---------------------------------------------------------------------------

class _OtpStep extends GetView<AuthController> {
  const _OtpStep({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // À qui le code a été envoyé, et comment corriger le numéro.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: palette.fieldFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_iphone_rounded, size: 18, color: palette.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  controller.phoneCtrl.text.trim(),
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
              _InlineLink(
                palette: palette,
                label: 'Modifier',
                onTap: () => controller.goTo(AuthStep.credentials),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _OtpBoxes(palette: palette),
        const SizedBox(height: 24),
        _FeedbackBanner(palette: palette),
        _PrimaryButton(
          palette: palette,
          label: 'Vérifier',
          onPressed: controller.submitOtp,
        ),
        const SizedBox(height: 12),
        Center(
          child: _InlineLink(
            palette: palette,
            label: 'Je n’ai rien reçu — renvoyer le code',
            onTap: controller.submitPhone,
          ),
        ),
      ],
    );
  }
}

/// Six cases, une par chiffre — on voit combien il en reste à taper.
///
/// Un seul vrai champ, invisible, posé sur les cases : il garde le
/// clavier numérique, le collage et surtout la suggestion automatique du
/// code à l'arrivée du SMS, que six champs séparés casseraient.
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({required this.palette});

  final _AuthPalette palette;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  static const _length = 6;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final auth = Get.find<AuthController>();

    return Obx(() {
      final error = auth.otpError.value;
      final enabled = !auth.isLoading.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Code à 6 chiffres',
            textField: true,
            child: SizedBox(
              height: 58,
              child: Stack(
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: auth.otpCtrl,
                    builder: (context, value, _) {
                      final code = value.text;
                      return Row(
                        children: [
                          for (var i = 0; i < _length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _OtpCell(
                                palette: palette,
                                digit: i < code.length ? code[i] : null,
                                active:
                                    _focus.hasFocus &&
                                    (i == code.length ||
                                        (code.length == _length &&
                                            i == _length - 1)),
                                hasError: error != null,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: auth.otpCtrl,
                        focusNode: _focus,
                        // En lecture seule plutôt que désactivé : le
                        // clavier reste ouvert si le code est refusé.
                        readOnly: !enabled,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        // Ce seul indice suffit à ce que le système propose
                        // le code dès l'arrivée du SMS.
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_length),
                        ],
                        showCursor: false,
                        enableInteractiveSelection: false,
                        onChanged: (v) {
                          if (auth.otpError.value != null) {
                            auth.otpError.value = null;
                          }
                          // Six chiffres : on vérifie sans attendre le
                          // bouton.
                          if (v.length == _length) auth.submitOtp();
                        },
                        onSubmitted: (_) => auth.submitOtp(),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) _FieldError(message: error),
        ],
      );
    });
  }
}

class _OtpCell extends StatelessWidget {
  const _OtpCell({
    required this.palette,
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final _AuthPalette palette;
  final String? digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.danger
        : active
        ? palette.accent
        : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? palette.accentTint : palette.fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.6),
      ),
      child: Text(
        digit ?? '',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 3 — profil
// ---------------------------------------------------------------------------

class _AccountSetupStep extends GetView<AuthController> {
  const _AccountSetupStep({required this.palette, required this.state});

  final _AuthPalette palette;
  final _AuthState state;

  @override
  Widget build(BuildContext context) {
    final isStructure = state.accountType == AccountType.structure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le type avant le nom : c'est lui qui décide de ce qu'on demande
        // (« votre nom » ou « nom de la structure »). Dans l'autre ordre,
        // le champ changeait de sens après qu'on l'avait rempli.
        _FieldLabel(palette: palette, text: 'Vous êtes'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ChoiceTile(
                palette: palette,
                icon: Icons.person_outline_rounded,
                label: 'Un habitant',
                selected: !isStructure,
                onTap: () =>
                    controller.accountType.value = AccountType.personal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceTile(
                palette: palette,
                icon: Icons.apartment_outlined,
                label: 'Une structure',
                selected: isStructure,
                onTap: () =>
                    controller.accountType.value = AccountType.structure,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          state.accountType.description,
          style: GoogleFonts.manrope(
            fontSize: 13,
            height: 1.45,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: 22),
        _LabeledField(
          palette: palette,
          label: isStructure ? 'Nom de la structure' : 'Votre nom',
          helper: 'Il apparaîtra sur vos publications et vos messages.',
          hint: isStructure ? 'Ex. Mairie de Foumbot' : 'Prénom et nom',
          icon: isStructure
              ? Icons.apartment_outlined
              : Icons.person_outline_rounded,
          controller: controller.nameCtrl,
          error: controller.nameError,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: isStructure
              ? const [AutofillHints.organizationName]
              : const [AutofillHints.name],
          onSubmitted: (_) => controller.submitAccountSetup(),
        ),
        if (isStructure) ...[
          const SizedBox(height: 16),
          _Notice(
            palette: palette,
            color: AppColors.blue,
            icon: Icons.verified_outlined,
            title: 'Compte soumis à validation',
            body:
                'L’équipe Foumbot Link vérifie chaque structure avant ses '
                'premières annonces officielles. En attendant, vous pouvez '
                'consulter le fil, aimer et commenter.',
          ),
        ],
        const SizedBox(height: 24),
        _FeedbackBanner(palette: palette),
        _PrimaryButton(
          palette: palette,
          label: 'Terminer',
          onPressed: controller.submitAccountSetup,
        ),
      ],
    );
  }
}

/// Une carte à choisir parmi deux : l'icône dit la différence avant même
/// qu'on lise le libellé.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final _AuthPalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? palette.accentTint : palette.fieldFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? palette.accent : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      color: selected ? palette.accent : palette.muted,
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Briques communes
// ---------------------------------------------------------------------------

/// Sélecteur à deux onglets : une pastille claire glisse sous l'onglet
/// actif. L'ancien aplat orange criait plus fort que le bouton principal,
/// alors que ce n'est qu'un réglage.
class _SegmentedTabs<T> extends StatelessWidget {
  const _SegmentedTabs({
    required this.palette,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final _AuthPalette palette;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.$1 == value);
    final n = options.length;

    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.thumb,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(
                        alpha: palette.isDark ? 0.4 : 0.08,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (option, label) in options)
                Expanded(
                  child: Semantics(
                    selected: option == value,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(option),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: option == value
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: option == value
                                ? palette.ink
                                : palette.muted,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.palette, required this.text});

  final _AuthPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
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
    );
  }
}

/// Champ avec son libellé **au-dessus** : un simple texte d'aide disparaît
/// dès qu'on commence à taper, et l'on ne sait plus ce que le champ
/// attendait.
///
/// Au repos, un aplat doux sans bordure ; en saisie, un liseré orange qui
/// dit où l'on écrit ; en erreur, un liseré rouge et le message dessous —
/// la couleur et le texte disent la même chose.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    super.key,
    required this.palette,
    required this.label,
    required this.hint,
    required this.controller,
    required this.error,
    this.labelAction,
    this.helper,
    this.icon,
    this.trailing,
    this.focusNode,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
  });

  final _AuthPalette palette;
  final String label;
  final Widget? labelAction;
  final String? helper;
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
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final style = GoogleFonts.manrope(
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
      color: palette.ink,
    );

    OutlineInputBorder border(Color color, [double width = 1.6]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return Obx(() {
      final message = error.value;
      final hasError = message != null;
      final idle = hasError ? AppColors.danger : Colors.transparent;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: _FieldLabel(palette: palette, text: label),
                ),
                ?labelAction,
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !auth.isLoading.value,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            textCapitalization: textCapitalization,
            onSubmitted: onSubmitted,
            // L'erreur s'efface dès la première correction.
            onChanged: (_) {
              if (error.value != null) error.value = null;
            },
            style: style,
            cursorColor: palette.accent,
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.fieldFill,
              hoverColor: Colors.transparent,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(
                icon == null ? 16 : 0,
                17,
                trailing == null ? 16 : 0,
                17,
              ),
              prefixIcon: icon == null
                  ? null
                  : Icon(
                      icon,
                      size: 20,
                      color: hasError ? AppColors.danger : palette.muted,
                    ),
              suffixIcon: trailing,
              hintText: hint,
              hintStyle: style.copyWith(
                fontWeight: FontWeight.w500,
                color: palette.muted.withValues(alpha: 0.65),
              ),
              border: border(idle),
              enabledBorder: border(idle),
              disabledBorder: border(idle),
              focusedBorder: border(
                hasError ? AppColors.danger : palette.accent,
              ),
            ),
          ),
          if (hasError)
            _FieldError(message: message)
          else if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Text(
                helper!,
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  height: 1.4,
                  color: palette.muted,
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Bouton d'action principal — même hauteur et même place sur tous les
/// écrans, pour qu'on sache toujours où appuyer. Aplat orange profond :
/// le blanc y reste lisible (4,6:1), là où l'orange vif tombait à 3:1.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final _AuthPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(() {
      final isLoading = auth.isLoading.value;
      return SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.orangeDeep,
            disabledBackgroundColor: AppColors.orangeDeep.withValues(
              alpha: 0.75,
            ),
            foregroundColor: AppColors.white,
            disabledForegroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? const FoumbotLoader.button(key: ValueKey('loading'))
                : Row(
                    key: ValueKey(label),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

/// Bouton secondaire, contour fin : visible, mais sans concurrencer
/// l'action principale.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final _AuthPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(
      () => SizedBox(
        height: 54,
        child: OutlinedButton.icon(
          onPressed: auth.isLoading.value ? null : onPressed,
          icon: Icon(icon, size: 19),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.ink,
            side: BorderSide(color: palette.ink.withValues(alpha: 0.12)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(
        height: 1,
        thickness: 1,
        color: palette.ink.withValues(alpha: 0.08),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ou',
            style: GoogleFonts.manrope(fontSize: 13, color: palette.muted),
          ),
        ),
        line,
      ],
    );
  }
}

/// Lien texte dans la couleur d'accent lisible, cible tactile confortable.
class _InlineLink extends StatelessWidget {
  const _InlineLink({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final _AuthPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(
      () => TextButton(
        onPressed: auth.isLoading.value ? null : onTap,
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Retour du serveur : refus en rouge, confirmation en vert. Posé juste
/// au-dessus du bouton qui l'a provoqué.
class _FeedbackBanner extends GetView<AuthController> {
  const _FeedbackBanner({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final error = controller.errorMessage.value;
      final success = controller.successMessage.value;
      final isError = error != null;
      final text = error ?? success;

      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: text == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _Notice(
                  palette: palette,
                  color: isError ? AppColors.danger : AppColors.success,
                  icon: isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  body: text,
                ),
              ),
      );
    });
  }
}

/// Encadré d'information — retour du serveur, avis de validation d'un
/// compte structure.
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
        color: color.withValues(alpha: palette.isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.isDark ? palette.muted : palette.ink,
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

/// Mention de fin de page, affichée seulement là où l'on s'engage : à la
/// création du compte. La politique de confidentialité est à un geste.
class _LegalNote extends StatelessWidget {
  const _LegalNote({required this.palette, required this.state});

  final _AuthPalette palette;
  final _AuthState state;

  @override
  Widget build(BuildContext context) {
    if (state.step != AuthStep.credentials || !state.isSignUp) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Text(
            'En créant un compte, vous acceptez de respecter les règles de '
            'la communauté Foumbot Link.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.45,
              color: palette.muted,
            ),
          ),
          _InlineLink(
            palette: palette,
            label: 'Politique de confidentialité',
            onTap: () => launchUrl(
              HomeController.privacyPolicyUrl,
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.palette,
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final _AuthPalette palette;
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.fieldFill,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: palette.ink),
          ),
        ),
      ),
    );
  }
}

/// Les couleurs de l'écran résolues une fois, puis passées aux sous-widgets.
class _AuthPalette {
  const _AuthPalette({
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.fieldFill,
    required this.thumb,
    required this.background,
    required this.accent,
    required this.accentTint,
  });

  factory _AuthPalette.of(bool isDark) => isDark
      ? _AuthPalette(
          isDark: true,
          ink: AppColors.white,
          muted: AppColors.whiteMuted,
          fieldFill: AppColors.blackSoft,
          thumb: AppColors.blackElevated,
          background: AppColors.black,
          // L'orange clair se lit très bien sur fond noir (plus de 9:1).
          accent: AppColors.orangeSoft,
          accentTint: AppColors.orange.withValues(alpha: 0.14),
        )
      : _AuthPalette(
          isDark: false,
          ink: AppColors.black,
          muted: AppColors.gray,
          fieldFill: const Color(0xFFF3F1EF),
          thumb: AppColors.white,
          // Blanc cassé chaud : moins dur que le blanc pur, plus doux à
          // l'œil, et les champs s'en détachent sans bordure.
          background: const Color(0xFFFCFAF8),
          // Sur fond clair, seul l'orange profond se lit (5:1).
          accent: AppColors.orangeReadable,
          accentTint: AppColors.orange.withValues(alpha: 0.08),
        );

  final bool isDark;
  final Color ink;
  final Color muted;
  final Color fieldFill;

  /// La pastille glissante du sélecteur d'onglets.
  final Color thumb;
  final Color background;

  /// Liens, focus, cases actives — jamais du texte blanc posé dessus.
  final Color accent;

  /// Fond teinté des éléments sélectionnés.
  final Color accentTint;
}
