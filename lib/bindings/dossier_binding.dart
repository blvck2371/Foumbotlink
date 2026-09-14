import 'package:get/get.dart';

import '../controllers/demarches_controller.dart';
import '../controllers/dossier_controller.dart';
import '../controllers/structure_demarches_controller.dart';
import '../controllers/structure_desk_controller.dart';

/// Suivi des dossiers côté habitant.
class DossierBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(DossierController.new);
  }
}

/// Guichet côté structure — contrôleur distinct : les deux écrans ne
/// partagent ni les données lues ni les droits d'écriture.
class StructureDeskBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(StructureDeskController.new);
  }
}

/// Catalogue des démarches publiées par les structures.
class DemarchesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(DemarchesController.new);
  }
}

/// Gestion, par une structure, des démarches qu'elle publie.
class StructureDemarchesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(StructureDemarchesController.new);
  }
}
