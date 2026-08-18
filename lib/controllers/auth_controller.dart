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
  final errorMessage = RxnString();

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
    errorMessage.value = null;
    step.value = next;
  }

  void toggleEmailMode() {
    emailMode.value =
        emailMode.value == EmailMode.signIn ? EmailMode.signUp : EmailMode.signIn;
    errorMessage.value = null;
  }

  Future<void> submitEmail() async {
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      errorMessage.value = 'Renseignez votre e-mail et votre mot de passe.';
      return;
    }
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
    final email = emailCtrl.text.trim();
    if (email.isEmpty) {
      errorMessage.value = 'Renseignez votre e-mail pour recevoir le lien.';
      return;
    }
    isLoading.value = true;
    final error = await _auth.sendPasswordReset(email);
    isLoading.value = false;
    errorMessage.value =
        error ?? 'E-mail de réinitialisation envoyé à $email.';
  }

  Future<void> submitPhone() async {
    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) {
      errorMessage.value = 'Renseignez votre numéro de téléphone.';
      return;
    }
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
    final verificationId = _verificationId;
    final code = otpCtrl.text.trim();
    if (verificationId == null) return;
    if (code.isEmpty) {
      errorMessage.value = 'Entrez le code reçu par SMS.';
      return;
    }
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
    errorMessage.value = null;
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
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      errorMessage.value = accountType.value == AccountType.structure
          ? 'Indiquez le nom de la structure.'
          : 'Indiquez votre nom.';
      return;
    }
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
