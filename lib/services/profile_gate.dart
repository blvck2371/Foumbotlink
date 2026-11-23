import 'package:get/get.dart';

import '../routes/app_routes.dart';
import 'auth_service.dart';
import 'user_profile_service.dart';

/// Le passage obligé des actions qui affichent un nom aux autres : publier,
/// commenter, écrire, appeler, lancer ou regarder un live, vendre…
///
/// Créer un compte connecte tout de suite, sans rien demander d'autre : on
/// peut parcourir l'app. Le nom et le type de compte ne sont demandés qu'à
/// la première action qui en a besoin, et l'action reprend dès que c'est
/// fait :
///
/// ```dart
/// if (!await ProfileGate.ensure(reason: 'Pour publier')) return;
/// ```
///
/// Rend `true` si un profil existe (déjà, ou tout juste créé), `false` si
/// la personne a fermé l'écran sans aller au bout.
class ProfileGate {
  ProfileGate._();

  static Future<bool> ensure({String? reason}) async {
    final auth = Get.find<AuthService>();
    final profiles = Get.find<UserProfileService>();

    if (auth.isSignedIn) {
      await profiles.waitUntilLoaded();
      if (profiles.hasProfile) return true;
    }

    // Pas connecté : connexion ou inscription, qui enchaîne sur le profil.
    // Connecté sans profil : l'écran s'ouvre directement sur le profil.
    await Get.toNamed(
      AppRoutes.auth,
      arguments: {'requireProfile': true, 'reason': reason},
    );
    if (!auth.isSignedIn) return false;
    await profiles.waitUntilLoaded();
    return profiles.hasProfile;
  }

  /// Connecté, mais profil pas encore complété.
  static bool get needsCompletion {
    final profiles = Get.find<UserProfileService>();
    return Get.find<AuthService>().isSignedIn &&
        !profiles.isLoading.value &&
        !profiles.hasProfile;
  }
}
