import 'dart:async';

import 'package:get/get.dart';

import '../models/demarche.dart';
import '../models/search_text.dart';
import '../services/demarche_companion.dart';
import '../services/demarche_service.dart';

/// Une structure qui publie des démarches, vue depuis le catalogue.
class DemarcheStructure {
  const DemarcheStructure({
    required this.uid,
    required this.name,
    required this.demarches,
  });

  final String uid;
  final String name;
  final List<Demarche> demarches;
}

/// Catalogue des démarches **publiées**.
///
/// Une démarche appartient à la structure qui la publie : une mairie, un
/// tribunal, une entreprise ou une association n'ont ni les mêmes
/// démarches, ni les mêmes pièces, ni les mêmes tarifs. Le catalogue est
/// donc organisé par structure, et rien n'est montré qu'une structure
/// n'ait elle-même publié, et qu'elle ne tienne à jour.
class DemarchesController extends GetxController {
  final demarches = <Demarche>[].obs;
  final isLoading = true.obs;
  final loadError = RxnString();

  /// Filtre de l'écran (titre, description, pièces, lieu, structure).
  final query = ''.obs;

  /// Structure choisie dans le filtre, `null` = toutes.
  final selectedStructure = RxnString();

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
        // Les échéances suivies se recalent sur ce que publient les
        // structures (délai modifié, retiré, démarche supprimée).
        unawaited(Get.find<DemarcheCompanion>().sync(list));
        isLoading.value = false;
        final sel = selectedStructure.value;
        if (sel != null && list.every((d) => d.structureUid != sel)) {
          selectedStructure.value = null;
        }
      },
      onError: (_) {
        isLoading.value = false;
        loadError.value =
            'Les démarches n’ont pas pu être chargées. Vérifiez votre '
            'connexion.';
      },
    );
  }

  /// Toutes les structures qui publient, par ordre alphabétique.
  List<DemarcheStructure> get structures => groupByStructure(demarches);

  /// Les structures et leurs démarches, après filtre et recherche.
  List<DemarcheStructure> get visibleStructures {
    final tokens = searchQueryTokens(query.value);
    final sel = selectedStructure.value;
    return groupByStructure([
      for (final d in demarches)
        if ((sel == null || d.structureUid == sel) &&
            (tokens.isEmpty || matches(d, tokens)))
          d,
    ]);
  }

  static List<DemarcheStructure> groupByStructure(Iterable<Demarche> list) {
    final byUid = <String, List<Demarche>>{};
    for (final d in list) {
      byUid.putIfAbsent(d.structureUid, () => []).add(d);
    }
    final out =
        [
          for (final e in byUid.entries)
            DemarcheStructure(
              uid: e.key,
              name: e.value.first.structureName,
              demarches: e.value
                ..sort((a, b) {
                  final byCat = a.category.index.compareTo(b.category.index);
                  return byCat != 0
                      ? byCat
                      : normalizeForSearch(
                          a.title,
                        ).compareTo(normalizeForSearch(b.title));
                }),
            ),
        ]..sort(
          (a, b) =>
              normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
        );
    return out;
  }

  static bool matches(Demarche d, List<String> tokens) =>
      matchScore(
        tokens,
        '${d.title} ${d.description} ${d.documents.join(' ')} ${d.lieu} '
        '${d.structureName} ${d.category.label}',
      ) >
      0;
}
