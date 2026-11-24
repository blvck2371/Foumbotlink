import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/user_profile_service.dart';

/// Où en est le compte vis-à-vis de la certification. Les seuils viennent
/// du serveur, qui les lit dans `config/certification` (voir
/// functions/certification.js) : rien n'est fixé dans l'app.
class CertificationStatus {
  const CertificationStatus({
    required this.verified,
    required this.enabled,
    required this.isStructure,
    required this.followers,
    required this.likes,
    required this.minFollowers,
    required this.minLikes,
    required this.eligible,
    this.requestStatus,
  });

  final bool verified;

  /// Ouverte pour ce type de compte. Fermée = « bientôt disponible ».
  final bool enabled;
  final bool isStructure;
  final int followers;
  final int likes;
  final int minFollowers;
  final int minLikes;
  final bool eligible;

  /// `pending`, `approved`, `rejected`, ou `null` sans demande.
  final String? requestStatus;

  bool get pending => requestStatus == 'pending';
  bool get rejected => requestStatus == 'rejected';

  factory CertificationStatus.fromMap(Map<String, dynamic> d) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final request = d['request'];
    return CertificationStatus(
      verified: d['verified'] == true,
      enabled: d['enabled'] == true,
      isStructure: d['accountType'] == 'structure',
      followers: n(d['followers']),
      likes: n(d['likes']),
      minFollowers: n(d['minFollowers']),
      minLikes: n(d['minLikes']),
      eligible: d['eligible'] == true,
      requestStatus: request is Map ? request['status'] as String? : null,
    );
  }
}

/// « Modifier mon profil » : nom, photo, coordonnées et certification.
class EditProfileController extends GetxController {
  UserProfileService get _profiles => Get.find<UserProfileService>();

  final nameCtrl = TextEditingController();
  final nameError = RxnString();
  final saving = false.obs;
  final uploadingPhoto = false.obs;

  final email = RxnString();
  final phone = RxnString();

  final certification = Rxn<CertificationStatus>();
  final certificationLoading = true.obs;
  final certificationError = RxnString();
  final requesting = false.obs;

  Rxn<UserProfile> get profile => _profiles.profile;

  /// Le nom a changé par rapport à celui enregistré.
  final dirty = false.obs;

  @override
  void onInit() {
    super.onInit();
    nameCtrl.text = profile.value?.displayName ?? '';
    nameCtrl.addListener(_onNameChanged);
    unawaited(_loadContact());
    unawaited(loadCertification());
  }

  void _onNameChanged() {
    nameError.value = null;
    dirty.value = nameCtrl.text.trim() != (profile.value?.displayName ?? '');
  }

  Future<void> _loadContact() async {
    try {
      final c = await _profiles.loadContact();
      email.value = c.email;
      phone.value = c.phoneNumber;
    } on Object catch (e) {
      developer.log('Coordonnées', name: 'EditProfile', error: e);
    }
  }

  /// Après un passage par l'écran du numéro, qui peut l'avoir changé.
  Future<void> refreshContact() => _loadContact();

  Future<void> save() async {
    if (saving.value) return;
    saving.value = true;
    final error = await _profiles.updateDisplayName(nameCtrl.text);
    saving.value = false;
    if (error != null) {
      nameError.value = error;
      return;
    }
    dirty.value = false;
    Get.snackbar(
      'Profil enregistré',
      'Votre nom apparaîtra aussi sur vos publications d’ici quelques '
          'instants.',
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> pickPhoto(ImageSource source) async {
    if (uploadingPhoto.value) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    uploadingPhoto.value = true;
    try {
      await _profiles.uploadProfilePhoto(picked.path);
    } on FirebaseException catch (e) {
      Get.snackbar('Échec de l’envoi', e.message ?? '$e');
    } finally {
      uploadingPhoto.value = false;
    }
  }

  Future<void> removePhoto() async {
    if (uploadingPhoto.value || profile.value?.photoUrl == null) return;
    uploadingPhoto.value = true;
    try {
      await _profiles.removeProfilePhoto();
    } on FirebaseException catch (e) {
      Get.snackbar('Suppression impossible', e.message ?? '$e');
    } finally {
      uploadingPhoto.value = false;
    }
  }

  // ---------------------------------------------------------------------
  // Certification
  // ---------------------------------------------------------------------

  Future<void> loadCertification() async {
    certificationLoading.value = true;
    certificationError.value = null;
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('certificationStatus')
          .call<Map<String, dynamic>>();
      certification.value = CertificationStatus.fromMap(
        Map<String, dynamic>.from(res.data),
      );
    } on FirebaseFunctionsException catch (e) {
      certificationError.value = _readable(
        e,
        'Impossible de charger la certification. Réessayez plus tard.',
      );
    } on Object catch (_) {
      certificationError.value = 'Impossible de charger la certification.';
    } finally {
      certificationLoading.value = false;
    }
  }

  Future<void> requestCertification() async {
    if (requesting.value) return;
    requesting.value = true;
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('requestCertification')
          .call<Map<String, dynamic>>();
      final approved = res.data['status'] == 'approved';
      Get.snackbar(
        approved ? 'Compte certifié' : 'Demande envoyée',
        approved
            ? 'Votre compte porte désormais le badge de certification.'
            : 'L’équipe Foumbot Link va examiner votre demande. Vous serez '
                  'prévenu·e de sa décision.',
        duration: const Duration(seconds: 4),
      );
    } on FirebaseFunctionsException catch (e) {
      Get.snackbar(
        'Demande impossible',
        _readable(e, 'Une erreur est survenue. Réessayez plus tard.'),
      );
    } finally {
      requesting.value = false;
      await loadCertification();
    }
  }

  /// Les messages des `HttpsError` du serveur (seuils non atteints,
  /// demande déjà en cours…) sont écrits pour l'utilisateur ; les autres
  /// codes ne portent que le nom technique (« INTERNAL ») : on les remplace.
  static String _readable(FirebaseFunctionsException e, String fallback) {
    const userFacing = {
      'failed-precondition',
      'already-exists',
      'unauthenticated',
      'permission-denied',
    };
    final message = e.message;
    if (userFacing.contains(e.code) && message != null && message.isNotEmpty) {
      return message;
    }
    return fallback;
  }

  @override
  void onClose() {
    nameCtrl.removeListener(_onNameChanged);
    nameCtrl.dispose();
    super.onClose();
  }
}
