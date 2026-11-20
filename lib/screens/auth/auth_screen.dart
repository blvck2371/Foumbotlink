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

/// Parcours d'entrée dans l'application.
///
/// Trois écrans, toujours dans le même ordre logique :
///
/// 1. **Identifiants** — un seul écran. En haut, l'intention : « Créer un
///    compte » ou « Se connecter ». Dessous, le formulaire de la méthode
///    retenue (numéro par défaut), puis le bouton. Changer de méthode se
///    fait par un bouton secondaire sous l'action principale. L'ancien
///    parcours demandait la méthode *avant* l'intention : on ne savait
///    qu'au formulaire si l'on était en train de s'inscrire.
/// 2. **Code SMS** — uniquement par le chemin téléphone.
/// 3. **Profil** — uniquement pour un compte qui n'en a pas encore.
///
/// Chaque écran a la même ossature : bandeau orange (titre + sous-titre),
/// une carte qui contient *tout* ce qu'il y a à faire, l'action
/// principale en bas de la carte. Rien d'autre à lire.
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

      return Scaffold(
        backgroundColor: palette.background,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            _CurvedHeader(palette: palette, state: state, compact: keyboardUp),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chevauchement de la courbe : la carte paraît posée
                      // sur le bandeau.
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: _StepBody(palette: palette, state: state),
                      ),
                      _FeedbackBanner(palette: palette),
                      _LegalNote(palette: palette, state: state),
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
  /// clignoter toute la carte.
  String get key => step.name;
}

// ---------------------------------------------------------------------------
// Bandeau incurvé
// ---------------------------------------------------------------------------

/// Bandeau de tête : dégradé orange, scène 3D décorative, titre de l'écran.
class _CurvedHeader extends GetView<AuthController> {
  const _CurvedHeader({
    required this.palette,
    required this.state,
    required this.compact,
  });

  final _AuthPalette palette;
  final _AuthState state;

  /// Clavier ouvert : le bandeau se rétracte pour rendre la hauteur au
  /// formulaire.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final height = (compact ? 128.0 : 236.0) + topInset;

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
            // Montée en permanence : la retirer quand le bandeau se
            // rétracte détruirait la WebView, rechargée à chaque fermeture
            // du clavier.
            const Opacity(
              opacity: 0.9,
              child: ThreeJsView(scene: 'auth', fallback: SizedBox.shrink()),
            ),
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _leading(),
                        const Spacer(),
                        if (_progress case (final position, final total))
                          _StepPill(position: position, total: total),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      _title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: compact ? 23 : 30,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColors.white,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      Text(
                        _subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppColors.white.withValues(alpha: 0.9),
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

  /// En haut à gauche, toujours le geste attendu à cet endroit :
  /// fermer sur le premier écran, revenir sur le code SMS. Le profil n'a
  /// ni l'un ni l'autre (le compte est déjà créé), d'où le logo.
  Widget _leading() => switch (state.step) {
    AuthStep.credentials => _CircleButton(
      icon: Icons.close_rounded,
      tooltip: 'Fermer',
      onTap: Get.back,
    ),
    AuthStep.phoneOtp => _CircleButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Retour',
      onTap: controller.back,
    ),
    AuthStep.accountSetup => ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: 38,
        height: 38,
        fit: BoxFit.cover,
      ),
    ),
  };

  /// Progression, affichée seulement là où elle a un sens : pendant une
  /// inscription. Une connexion se fait en un écran (deux par SMS) —
  /// « 1/3 » y laissait croire à un long parcours.
  (int, int)? get _progress {
    final total = state.isPhone ? 3 : 2;
    return switch (state.step) {
      AuthStep.credentials => state.isSignUp ? (1, total) : null,
      AuthStep.phoneOtp => state.isSignUp ? (2, 3) : null,
      AuthStep.accountSetup => (total, total),
    };
  }

  String get _title => switch (state.step) {
    AuthStep.credentials => state.isSignUp ? 'Créer un compte' : 'Bon retour !',
    AuthStep.phoneOtp => 'Code de vérification',
    AuthStep.accountSetup => 'Votre profil',
  };

  String get _subtitle => switch (state.step) {
    AuthStep.credentials =>
      state.isSignUp
          ? 'L’actualité, le marché et les démarches de Foumbot, au même '
                'endroit.'
          : 'Connectez-vous pour retrouver votre fil et vos discussions.',
    AuthStep.phoneOtp => 'Saisissez les six chiffres reçus par SMS.',
    AuthStep.accountSetup =>
      'Dernière étape : comment doit-on vous présenter ?',
  };
}

/// La courbe du bas du bandeau : une vague qui descend à gauche et remonte
/// à droite.
class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 46)
      ..quadraticBezierTo(w * 0.30, h + 8, w * 0.58, h - 26)
      ..quadraticBezierTo(w * 0.82, h - 52, w, h - 92)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Étape $position sur $total',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= total; i++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
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
              'Étape $position/$total',
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corps de l'écran
// ---------------------------------------------------------------------------

class _StepBody extends StatelessWidget {
  const _StepBody({required this.palette, required this.state});

  final _AuthPalette palette;
  final _AuthState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
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
        key: ValueKey(state.key),
        child: _FloatingCard(
          palette: palette,
          child: switch (state.step) {
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
        ),
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
        const SizedBox(height: 22),

        // 2. Le formulaire de la méthode choisie.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: state.isPhone
              ? _phoneFields(palette, controller)
              : _emailFields(palette, controller, state.isSignUp),
        ),
        const SizedBox(height: 22),

        // 3. L'action.
        _PrimaryButton(
          label: switch ((state.method, state.mode)) {
            (AuthMethod.phone, _) => 'Recevoir le code',
            (AuthMethod.email, AuthMode.signUp) => 'Créer mon compte',
            (AuthMethod.email, AuthMode.signIn) => 'Se connecter',
          },
          onPressed: controller.submitCredentials,
        ),

        // 4. L'autre méthode, en retrait.
        const SizedBox(height: 18),
        _OrDivider(palette: palette),
        const SizedBox(height: 18),
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
        const SizedBox(height: 16),
        Obx(
          () => _LabeledField(
            palette: palette,
            label: 'Mot de passe',
            // Le « mot de passe oublié » vit à côté du champ concerné,
            // pas perdu entre deux liens sous le bouton.
            labelAction: isSignUp
                ? null
                : _InlineLink(
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
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Envoyé au ',
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    color: palette.muted,
                  ),
                  children: [
                    TextSpan(
                      text: controller.phoneCtrl.text.trim(),
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _InlineLink(
              label: 'Modifier',
              onTap: () => controller.goTo(AuthStep.credentials),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LabeledField(
          palette: palette,
          label: 'Code à 6 chiffres',
          hint: '••••••',
          controller: controller.otpCtrl,
          error: controller.otpError,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          // Ce seul indice suffit à ce que le système propose le code dès
          // l'arrivée du SMS.
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
        const SizedBox(height: 22),
        _PrimaryButton(label: 'Vérifier', onPressed: controller.submitOtp),
        const SizedBox(height: 10),
        Center(
          child: _InlineLink(
            label: 'Je n’ai rien reçu — renvoyer le code',
            onTap: controller.submitPhone,
          ),
        ),
      ],
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
        const SizedBox(height: 8),
        _SegmentedTabs<AccountType>(
          palette: palette,
          value: state.accountType,
          onChanged: (t) => controller.accountType.value = t,
          options: const [
            (AccountType.personal, 'Un habitant'),
            (AccountType.structure, 'Une structure'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          state.accountType.description,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            height: 1.4,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: 20),
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
        const SizedBox(height: 22),
        _PrimaryButton(
          label: 'Terminer',
          onPressed: controller.submitAccountSetup,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Briques communes
// ---------------------------------------------------------------------------

/// La carte qui porte tout l'écran, détachée du fond par son ombre.
class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.palette, required this.child});

  final _AuthPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      shadowColor: AppColors.black.withValues(
        alpha: palette.isDark ? 0.6 : 0.16,
      ),
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: child,
      ),
    );
  }
}

/// Sélecteur à deux (ou plusieurs) onglets, l'actif en orange plein.
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.fieldFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (option, label) in options)
            Expanded(
              child: Semantics(
                selected: option == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option == value
                          ? AppColors.orange
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: option == value
                          ? [
                              BoxShadow(
                                color: AppColors.orange.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: option == value
                            ? AppColors.white
                            : palette.muted,
                      ),
                    ),
                  ),
                ),
              ),
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
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
    );
  }
}

/// Champ avec son libellé **au-dessus** : un simple texte d'aide disparaît
/// dès qu'on commence à taper, et l'on ne sait plus ce que le champ
/// attendait.
///
/// L'erreur s'affiche sous le champ concerné et le cadre passe au rouge :
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
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textStyle,
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
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final baseStyle =
        textStyle ?? GoogleFonts.manrope(fontSize: 15, color: palette.ink);

    return Obx(() {
      final message = error.value;
      final hasError = message != null;
      final enabled = !auth.isLoading.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _FieldLabel(palette: palette, text: label),
              ),
              ?labelAction,
            ],
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(
              left: icon != null ? 14 : 4,
              right: trailing != null ? 2 : 4,
            ),
            decoration: BoxDecoration(
              color: palette.fieldFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasError ? AppColors.danger : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 19,
                    color: hasError ? AppColors.danger : palette.muted,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    obscureText: obscure,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    inputFormatters: inputFormatters,
                    textAlign: textAlign,
                    textCapitalization: textCapitalization,
                    onSubmitted: onSubmitted,
                    // L'erreur s'efface dès la première correction.
                    onChanged: (_) {
                      if (error.value != null) error.value = null;
                    },
                    style: baseStyle,
                    cursorColor: AppColors.orange,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      hintText: hint,
                      hintStyle: baseStyle.copyWith(
                        color: palette.muted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 7, left: 2),
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
            )
          else if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 7, left: 2),
              child: Text(
                helper!,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.35,
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
/// écrans, pour qu'on sache toujours où appuyer.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(() {
      final isLoading = auth.isLoading.value;
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
                // Le dégradé est peint par le conteneur ; le bouton
                // n'apporte que la surface tactile et l'ondulation.
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLoading
                    ? const FoumbotLoader.button(key: ValueKey('loading'))
                    : Text(label, key: ValueKey(label)),
              ),
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
        height: 50,
        child: OutlinedButton.icon(
          onPressed: auth.isLoading.value ? null : onPressed,
          icon: Icon(icon, size: 19),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.ink,
            side: BorderSide(color: palette.ink.withValues(alpha: 0.14)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: GoogleFonts.manrope(fontSize: 12.5, color: palette.muted),
          ),
        ),
        line,
      ],
    );
  }
}

/// Lien texte orange, cible tactile confortable.
class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(
      () => TextButton(
        onPressed: auth.isLoading.value ? null : onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Retour du serveur : refus en rouge, confirmation en vert.
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
        padding: const EdgeInsets.only(bottom: 14),
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

/// Mention de fin de page, affichée seulement là où l'on s'engage : à la
/// création du compte.
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        'En créant un compte, vous acceptez de respecter les règles de la '
        'communauté Foumbot Link.',
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 11.5,
          height: 1.4,
          color: palette.muted.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
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
    required this.card,
    required this.fieldFill,
    required this.background,
    required this.headerGradient,
  });

  factory _AuthPalette.of(bool isDark) => _AuthPalette(
    isDark: isDark,
    ink: isDark ? AppColors.white : AppColors.black,
    muted: isDark ? AppColors.whiteMuted : AppColors.gray,
    card: isDark ? AppColors.blackElevated : AppColors.white,
    fieldFill: isDark ? AppColors.blackSoft : AppColors.whiteSoft,
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
  final Color fieldFill;
  final Color background;
  final Gradient headerGradient;
}
