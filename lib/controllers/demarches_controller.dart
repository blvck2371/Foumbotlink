import 'dart:async';

import 'package:get/get.dart';

import '../models/demarche.dart';
import '../services/demarche_service.dart';

/// Le catalogue public, alimenté par les structures.
///
/// Rien n'est codé en dur : ce que l'habitant voit est exactement ce que
/// les structures de la commune ont publié, chacune pour ses propres
/// guichets.
class DemarchesController extends GetxController {
  final demarches = <Demarche>[].obs;
  final isLoading = true.obs;
  final loadError = RxnString();

  StreamSubscription? _sub;

  DemarcheService get _service => Get.find<DemarcheService>();

  bool get isEmpty => !isLoading.value && demarches.isEmpty;

  @override
  void onInit() {
    super.onInit();
    _watch();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _watch() {
    _sub?.cancel();
    _sub = _service.watchAll(
      onData: (list) {
        demarches.assignAll(list);
        loadError.value = null;
        isLoading.value = false;
      },
      onError: (_) {
        isLoading.value = false;
        loadError.value =
            'Les démarches n’ont pas pu être chargées. Vérifiez votre '
            'connexion.';
      },
    );
  }

  List<Demarche> byCategory(DemarcheCategory category) =>
      demarches.where((d) => d.category == category).toList();
}
