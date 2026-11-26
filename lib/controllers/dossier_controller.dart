import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/dossier.dart';
import '../services/auth_service.dart';
import '../services/dossier_service.dart';
import '../services/user_profile_service.dart';
import '../services/profile_gate.dart';

/// Côté habitant : mon code de suivi, et l'état de mes dossiers.
class DossierController extends GetxController {
  final dossiers = <Dossier>[].obs;
  final isLoading = true.obs;
  final trackingCode = ''.obs;
  final codeError = RxnString();

  StreamSubscription? _sub;
  StreamSubscription? _codeSub;

  /// L'attribution n'est tentée qu'une fois par ouverture d'écran :
  /// l'écoute émet à chaque écriture, et sans ce verrou la première
  /// attribution en déclencherait une deuxième.
  bool _allocating = false;

  DossierService get _dossiers => Get.find<DossierService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  bool get isSignedIn => _auth.isSignedIn && _profiles.hasProfile;

  /// Les dossiers encore en mouvement, mis en tête : c'est ce que la
  /// personne vient voir. Les dossiers retirés ou rejetés restent
  /// consultables, mais plus bas.
  List<Dossier> get active =>
      dossiers.where((d) => !d.status.isClosed).toList();

  List<Dossier> get closed => dossiers.where((d) => d.status.isClosed).toList();

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  /// « Se connecter » depuis l'écran de suivi : connexion et profil si
  /// besoin, puis chargement du code et des dossiers.
  Future<void> signInAndLoad() async {
    if (!await ProfileGate.ensure(reason: 'Pour suivre vos démarches')) return;
    isLoading.value = true;
    _bootstrap();
  }

  @override
  void onClose() {
    _sub?.cancel();
    _codeSub?.cancel();
    super.onClose();
  }

  void _bootstrap() {
    if (!isSignedIn) {
      isLoading.value = false;
      return;
    }
    _watchCode();
    _watch();
  }

  /// Le code est suivi en direct, pas lu une fois.
  ///
  /// Firestore sert d'abord le cache local : dès la deuxième ouverture,
  /// le code s'affiche sans attendre le réseau, là où l'ancien `get()`
  /// laissait l'écran vide le temps d'un aller-retour. L'attribution ne
  /// part que si l'écoute confirme qu'il n'y a pas encore de code.
  void _watchCode() {
    _codeSub?.cancel();
    _codeSub = _dossiers
        .watchTrackingCode(_auth.uid)
        .listen(
          (code) {
            if (code != null && code.isNotEmpty) {
              trackingCode.value = code;
              codeError.value = null;
              return;
            }
            _allocateCode();
          },
          onError: (Object e) {
            developer.log(
              'watchTrackingCode',
              name: 'DossierController',
              error: e,
            );
            // Pas de message d'erreur ici : hors ligne, l'écoute échoue mais
            // un code déjà connu reste parfaitement valable à recopier.
            if (trackingCode.value.isEmpty) _allocateCode();
          },
        );
  }

  /// Attribue un code à la première ouverture de l'écran, pas à
  /// l'inscription : les comptes créés avant cette fonctionnalité en
  /// reçoivent un sans migration, et personne n'a de code qu'il n'a
  /// jamais regardé.
  Future<void> _allocateCode() async {
    if (_allocating || trackingCode.value.isNotEmpty) return;
    _allocating = true;
    try {
      final profile = _profiles.profile.value;
      trackingCode.value = await _dossiers.ensureTrackingCode(
        uid: _auth.uid,
        displayName: profile?.displayName ?? 'Habitant',
      );
      codeError.value = null;
    } catch (e) {
      developer.log('ensureTrackingCode', name: 'DossierController', error: e);
      codeError.value =
          'Votre code n’a pas pu être attribué. Vérifiez votre connexion '
          'puis rouvrez cet écran.';
    } finally {
      _allocating = false;
    }
  }

  void _watch() {
    _sub?.cancel();
    _sub = _dossiers.watchMine(
      uid: _auth.uid,
      onData: (list) {
        dossiers.assignAll(list);
        isLoading.value = false;
      },
      onError: (_) => isLoading.value = false,
    );
  }

  void copyCode() {
    final code = trackingCode.value;
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    Get.snackbar(
      'Code copié',
      'Écrivez-le en gros sur la chemise de votre dossier.',
      duration: const Duration(seconds: 3),
    );
  }
}
