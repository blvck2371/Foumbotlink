import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/account_type.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';

enum AuthStep { choice, emailForm, phoneForm, phoneOtp, accountSetup }

enum EmailMode { signIn, signUp }

class AuthController extends GetxController {
  final step = AuthStep.choice.obs;
  // La plupart des gens qui arrivent ici n'ont pas encore de compte —
  // on démarre donc sur le formulaire de création, avec un lien pour
  // basculer vers la connexion si besoin.
  final emailMode = EmailMode.signUp.obs;
  final isLoading = false.obs;

  /// Échec renvoyé par le serveur (identifiants refusés, réseau…) —
  /// distinct de [successMessage], qui partageait le même champ et donc
  /// la même couleur : « e-mail envoyé » s'affichait exactement comme
  /// « mot de passe incorrect ».
  final errorMessage = RxnString();
  final successMessage = RxnString();

  /// Erreurs par champ, affichées **sous le champ concerné**. Un message
  /// unique en bas de page oblige à deviner lequel des deux champs est en
  /// cause.
  final emailError = RxnString();
  final passwordError = RxnString();
  final phoneError = RxnString();
  final otpError = RxnString();
  final nameError = RxnString();

  /// Mot de passe affiché en clair. Saisir à l'aveugle sur un clavier
  /// tactile est la première cause d'échec de connexion.
  final obscurePassword = true.obs;

  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final nameCtrl = TextEditingController();

  final accountType = AccountType.personal.obs;

  String? _verificationId;
  String? _pendingEmail;
  String? _pendingPhone;

  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  @override
  void onInit() {
    super.onInit();
    _resumeExistingSessionIfNeeded();
  }

  Future<void> _resumeExistingSessionIfNeeded() async {
    if (!_auth.isSignedIn) return;
    // On attend de savoir avec certitude si le profil existe — sans ça,
    // "pas encore chargé" pourrait être pris à tort pour "pas de profil"
    // et renvoyer un utilisateur déjà inscrit vers la configuration.
    await _profiles.waitUntilLoaded();
    if (_profiles.hasProfile) {
      Get.back();
      return;
    }
    // Session Firebase déjà active mais profil Firestore jamais créé
    // (ex. app fermée entre les deux étapes) : reprendre directement à
    // la configuration du compte plutôt que de redemander email/téléphone.
    step.value = AuthStep.accountSetup;
  }

  void goTo(AuthStep next) {
    _clearMessages();
    step.value = next;
  }

  /// Étape précédente dans le parcours. L'écran n'offrait que la flèche
  /// de la barre du haut, qui quitte l'authentification entière : arrivé
  /// sur le code SMS, il n'y avait aucun moyen de revenir choisir
  /// l'e-mail sans tout recommencer.
  void back() {
    switch (step.value) {
      case AuthStep.emailForm:
      case AuthStep.phoneForm:
        goTo(AuthStep.choice);
      case AuthStep.phoneOtp:
        goTo(AuthStep.phoneForm);
      case AuthStep.choice:
      case AuthStep.accountSetup:
        // La configuration du compte n'a pas de retour : la session est
        // créée, revenir en arrière laisserait un compte sans profil.
        break;
    }
  }

  bool get canGoBack =>
      step.value == AuthStep.emailForm ||
      step.value == AuthStep.phoneForm ||
      step.value == AuthStep.phoneOtp;

  void _clearMessages() {
    errorMessage.value = null;
    successMessage.value = null;
    emailError.value = null;
    passwordError.value = null;
    phoneError.value = null;
    otpError.value = null;
    nameError.value = null;
  }

  // -----------------------------------------------------------------------
  // Validation
  // -----------------------------------------------------------------------

  /// Contrôles faits **avant** l'appel réseau. Ils n'ont pas vocation à
  /// remplacer les refus du serveur — un e-mail bien formé peut très bien
  /// être inconnu — mais à ne pas faire attendre un aller-retour pour une
  /// faute visible à l'œil nu.
  static String? validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Renseignez votre adresse e-mail.';
    final at = email.indexOf('@');
    final dot = email.lastIndexOf('.');
    if (at < 1 ||
        dot < at + 2 ||
        dot >= email.length - 1 ||
        email.contains(' ')) {
      return 'Cette adresse ne semble pas valide.';
    }
    return null;
  }

  static String? validatePassword(String value, {required bool isSignUp}) {
    if (value.isEmpty) return 'Renseignez votre mot de passe.';
    // Uniquement à l'inscription : à la connexion, la longueur d'un mot
    // de passe existant ne nous regarde pas, et le refuser localement
    // enfermerait un ancien compte hors de l'app.
    if (isSignUp && value.length < 6) {
      return 'Six caractères minimum.';
    }
    return null;
  }

  static String? validatePhone(String value) {
    final phone = value.replaceAll(' ', '');
    if (phone.isEmpty) return 'Renseignez votre numéro.';
    if (!phone.startsWith('+')) {
      return 'Commencez par l’indicatif, par exemple +237.';
    }
    final digits = phone.substring(1);
    if (digits.length < 8 ||
        digits.length > 15 ||
        int.tryParse(digits) == null) {
      return 'Ce numéro ne semble pas valide.';
    }
    return null;
  }

  static String? validateOtp(String value) {
    final code = value.trim();
    if (code.isEmpty) return 'Entrez le code reçu par SMS.';
    if (code.length != 6 || int.tryParse(code) == null) {
      return 'Le code compte six chiffres.';
    }
    return null;
  }

  static String? validateName(String value, AccountType type) {
    final name = value.trim();
    if (name.isEmpty) {
      return type == AccountType.structure
          ? 'Indiquez le nom de la structure.'
          : 'Indiquez votre nom.';
    }
    if (name.length < 2) return 'Ce nom est trop court.';
    return null;
  }

  void toggleEmailMode() {
    emailMode.value = emailMode.value == EmailMode.signIn
        ? EmailMode.signUp
        : EmailMode.signIn;
    _clearMessages();
  }

  Future<void> submitEmail() async {
    _clearMessages();
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;
    final isSignUp = emailMode.value == EmailMode.signUp;

    emailError.value = validateEmail(email);
    passwordError.value = validatePassword(password, isSignUp: isSignUp);
    if (emailError.value != null || passwordError.value != null) return;

    isLoading.value = true;
    final error = emailMode.value == EmailMode.signIn
        ? await _auth.signInWithEmail(email, password)
        : await _auth.signUpWithEmail(email, password);
    isLoading.value = false;
    if (error != null) {
      errorMessage.value = error;
      return;
    }
    await _afterSignIn(email: email);
  }

  Future<void> sendPasswordReset() async {
    _clearMessages();
    final email = emailCtrl.text.trim();
    emailError.value = validateEmail(email);
    if (emailError.value != null) return;

    isLoading.value = true;
    final error = await _auth.sendPasswordReset(email);
    isLoading.value = false;
    // Succès et échec dans deux champs distincts : ils s'affichaient tous
    // deux en orange, et « lien envoyé » se lisait comme un refus.
    if (error != null) {
      errorMessage.value = error;
    } else {
      successMessage.value =
          'Lien de réinitialisation envoyé à $email. Vérifiez votre boîte '
          'de réception, et vos indésirables.';
    }
  }

  Future<void> submitPhone() async {
    _clearMessages();
    final phone = phoneCtrl.text.trim();
    phoneError.value = validatePhone(phone);
    if (phoneError.value != null) return;

    isLoading.value = true;
    await _auth.sendPhoneCode(
      phoneNumber: phone,
      onCodeSent: (verificationId) {
        _verificationId = verificationId;
        isLoading.value = false;
        goTo(AuthStep.phoneOtp);
      },
      onError: (message) {
        isLoading.value = false;
        errorMessage.value = message;
      },
      onAutoVerified: () async {
        isLoading.value = false;
        await _afterSignIn(phoneNumber: phone);
      },
    );
  }

  Future<void> submitOtp() async {
    _clearMessages();
    final verificationId = _verificationId;
    final code = otpCtrl.text.trim();
    if (verificationId == null) return;
    otpError.value = validateOtp(code);
    if (otpError.value != null) return;

    isLoading.value = true;
    final error = await _auth.confirmPhoneCode(verificationId, code);
    isLoading.value = false;
    if (error != null) {
      errorMessage.value = error;
      return;
    }
    await _afterSignIn(phoneNumber: phoneCtrl.text.trim());
  }

  Future<void> _afterSignIn({String? email, String? phoneNumber}) async {
    _clearMessages();
    // Lecture directe (pas le listener réactif, plus lent à démarrer) :
    // on vient de se connecter, la réponse doit être immédiate et sûre.
    final hasProfile = await _profiles.ensureLoaded();
    if (hasProfile) {
      Get.back();
      return;
    }
    _pendingEmail = email;
    _pendingPhone = phoneNumber;
    goTo(AuthStep.accountSetup);
  }

  Future<void> submitAccountSetup() async {
    _clearMessages();
    final name = nameCtrl.text.trim();
    nameError.value = validateName(name, accountType.value);
    if (nameError.value != null) return;

    isLoading.value = true;
    await _profiles.createProfile(
      accountType: accountType.value,
      displayName: name,
      email: _pendingEmail,
      phoneNumber: _pendingPhone,
    );
    isLoading.value = false;
    Get.back();
  }

  @override
  void onClose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    phoneCtrl.dispose();
    otpCtrl.dispose();
    nameCtrl.dispose();
    super.onClose();
  }
}
