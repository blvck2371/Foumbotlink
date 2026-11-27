import 'package:get/get.dart';

import '../controllers/directory_controller.dart';

/// Partagé par la liste, la fiche et l'édition : une fiche ouverte depuis
/// ailleurs que l'annuaire (profil, lien) trouve quand même ses actions
/// de contact.
class DirectoryBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<DirectoryController>()) {
      Get.lazyPut(DirectoryController.new);
    }
  }
}
