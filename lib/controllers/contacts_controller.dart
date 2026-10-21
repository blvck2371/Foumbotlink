import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../models/phone_contact.dart';
import '../services/auth_service.dart';
import '../services/contact_match_service.dart';
import '../services/follow_service.dart';
import '../services/user_profile_service.dart';

/// Numéro de téléphone du compte, et habitants retrouvés dans le
/// répertoire.
///
/// Les deux vont ensemble : sans numéro enregistré, on peut retrouver les
/// autres mais eux ne peuvent pas nous retrouver. L'écran le dit.
class ContactsController extends GetxController {
  /// Numéro enregistré, sous forme canonique, ou vide.
  final phoneNumber = ''.obs;
  final isLoadingPhone = true.obs;
  final isSavingPhone = false.obs;
  final phoneError = RxnString();

  final matches = <ContactMatch>[].obs;
  final isSearching = false.obs;
  final failure = Rxn<ContactMatchFailure>();

  /// Nombre de numéros exploitables lus dans le répertoire — de quoi dire
  /// « 214 contacts parcourus » plutôt qu'afficher un vide sans mot.
  final scanned = 0.obs;
  final hasSearched = false.obs;

  /// Comptes auxquels on vient de s'abonner depuis cet écran. Ils restent
  /// affichés, marqués comme suivis : les faire disparaître d'un coup
  /// donnerait l'impression d'une erreur.
  final followed = <String>{}.obs;
  final following = <String>{}.obs;

  UserProfileService get _profiles => Get.find<UserProfileService>();
  ContactMatchService get _contacts => Get.find<ContactMatchService>();
  FollowService get _follow => Get.find<FollowService>();
  AuthService get _auth => Get.find<AuthService>();

  bool get hasPhone => phoneNumber.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    loadPhone();
  }

  Future<void> loadPhone() async {
    isLoadingPhone.value = true;
    try {
      final contact = await _profiles.loadContact();
      phoneNumber.value = contact.phoneNumber ?? '';
    } finally {
      isLoadingPhone.value = false;
    }
  }

  /// Enregistre le numéro saisi. Renvoie vrai si c'est passé.
  Future<bool> savePhone(String raw) async {
    phoneError.value = null;
    if (PhoneContact.normalize(raw) == null) {
      phoneError.value =
          'Ce numéro ne semble pas valide. Exemple : 690 00 00 00 ou '
          '+237 690 00 00 00.';
      return false;
    }

    isSavingPhone.value = true;
    try {
      final saved = await _profiles.savePhoneNumber(raw);
      if (saved == null) {
        phoneError.value = 'Ce numéro ne semble pas valide.';
        return false;
      }
      phoneNumber.value = saved;
      return true;
    } catch (e) {
      developer.log('savePhone', name: 'ContactsController', error: e);
      phoneError.value =
          'Enregistrement impossible. Vérifiez votre connexion.';
      return false;
    } finally {
      isSavingPhone.value = false;
    }
  }

  Future<void> removePhone() async {
    try {
      await _profiles.removePhoneNumber();
      phoneNumber.value = '';
    } catch (e) {
      developer.log('removePhone', name: 'ContactsController', error: e);
      phoneError.value = 'Suppression impossible. Vérifiez votre connexion.';
    }
  }

  /// Parcourt le répertoire et rapproche. Aucun numéro ne part : seules
  /// des empreintes (voir [ContactMatchService]).
  Future<void> findFriends() async {
    if (isSearching.value) return;
    isSearching.value = true;
    failure.value = null;
    try {
      final result = await _contacts.findFriends();
      hasSearched.value = true;
      scanned.value = result.scanned;
      if (result.ok) {
        matches.assignAll(result.matches);
      } else {
        matches.clear();
        failure.value = result.failure;
      }
    } finally {
      isSearching.value = false;
    }
  }

  bool isFollowed(String uid) => followed.contains(uid);
  bool isBusy(String uid) => following.contains(uid);

  Future<void> followContact(ContactMatch match) async {
    if (!_auth.isSignedIn || followed.contains(match.uid)) return;
    following.add(match.uid);
    try {
      await _follow.follow(_auth.uid, match.uid);
      followed.add(match.uid);
    } catch (e) {
      developer.log('followContact', name: 'ContactsController', error: e);
      Get.snackbar(
        'Abonnement impossible',
        'Vérifiez votre connexion puis réessayez.',
        duration: const Duration(seconds: 3),
      );
    } finally {
      following.remove(match.uid);
    }
  }
}
