import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/demarche.dart';
import '../services/auth_service.dart';
import '../services/demarche_service.dart';
import '../services/user_profile_service.dart';

/// Gestion des démarches d'une structure : les siennes, qu'elle crée,
/// corrige et retire elle-même.
class StructureDemarchesController extends GetxController {
  final demarches = <Demarche>[].obs;
  final isLoading = true.obs;
  final isSaving = false.obs;

  /// Démarche en cours d'édition — `null` pendant une création.
  final editing = Rxn<Demarche>();

  final titleCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final lieuCtrl = TextEditingController();
  final coutCtrl = TextEditingController();
  final delaiCtrl = TextEditingController();

  /// Pièces à fournir et étapes : une par ligne, c'est la façon la plus
  /// directe de saisir une liste sur un téléphone.
  final documentsCtrl = TextEditingController();
  final etapesCtrl = TextEditingController();

  /// Délai à respecter (facultatif) : nombre de jours, et à partir de quoi.
  final echeanceJoursCtrl = TextEditingController();
  final echeanceDepuisCtrl = TextEditingController();

  final category = DemarcheCategory.etatCivil.obs;
  final formError = RxnString();

  StreamSubscription? _sub;

  DemarcheService get _service => Get.find<DemarcheService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  String get _structureName =>
      _profiles.profile.value?.displayName ?? 'Structure';

  /// Seule une structure validée peut publier : les règles Firestore le
  /// vérifient de toute façon, autant ne pas proposer un formulaire dont
  /// chaque envoi serait refusé.
  bool get canPublish {
    final profile = _profiles.profile.value;
    return profile != null && profile.canPublish && profile.verified;
  }

  @override
  void onInit() {
    super.onInit();
    _watch();
  }

  @override
  void onClose() {
    _sub?.cancel();
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    lieuCtrl.dispose();
    coutCtrl.dispose();
    delaiCtrl.dispose();
    documentsCtrl.dispose();
    etapesCtrl.dispose();
    echeanceJoursCtrl.dispose();
    echeanceDepuisCtrl.dispose();
    super.onClose();
  }

  void _watch() {
    _sub?.cancel();
    _sub = _service.watchByStructure(
      structureUid: _auth.uid,
      onData: (list) {
        demarches.assignAll(list);
        isLoading.value = false;
      },
      onError: (_) => isLoading.value = false,
    );
  }

  // -----------------------------------------------------------------------
  // Formulaire
  // -----------------------------------------------------------------------

  /// Prépare le formulaire : vide pour une création, rempli pour une
  /// modification.
  void startEditing({Demarche? demarche}) {
    editing.value = demarche;
    formError.value = null;

    category.value = demarche?.category ?? DemarcheCategory.etatCivil;
    titleCtrl.text = demarche?.title ?? '';
    descriptionCtrl.text = demarche?.description ?? '';
    lieuCtrl.text = demarche?.lieu ?? '';
    coutCtrl.text = demarche?.cout ?? '';
    delaiCtrl.text = demarche?.delai ?? '';
    documentsCtrl.text = (demarche?.documents ?? const <String>[]).join('\n');
    etapesCtrl.text = (demarche?.etapes ?? const <String>[]).join('\n');
    echeanceJoursCtrl.text = demarche?.echeanceJours?.toString() ?? '';
    echeanceDepuisCtrl.text = demarche?.echeanceDepuis ?? '';
  }

  void setCategory(DemarcheCategory value) => category.value = value;

  /// Enregistre la démarche. Renvoie `true` si l'écriture a abouti.
  Future<bool> save() async {
    if (isSaving.value) return false;

    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      formError.value = 'Donnez un intitulé à la démarche.';
      return false;
    }
    if (!canPublish) {
      formError.value =
          'Votre compte structure doit être validé avant de publier des '
          'démarches.';
      return false;
    }

    // Délai : les deux champs ensemble, ou aucun.
    final joursText = echeanceJoursCtrl.text.trim();
    final depuis = echeanceDepuisCtrl.text.trim();
    int? jours;
    if (joursText.isNotEmpty || depuis.isNotEmpty) {
      jours = int.tryParse(joursText);
      if (jours == null || jours < 1 || jours > 3650) {
        formError.value =
            'Le délai doit être un nombre de jours (entre 1 et 3650).';
        return false;
      }
      if (depuis.isEmpty) {
        formError.value =
            'Précisez à partir de quand court le délai (ex. « la naissance '
            'de l’enfant »).';
        return false;
      }
    }

    final documents = _lines(documentsCtrl.text);
    final etapes = _lines(etapesCtrl.text);

    isSaving.value = true;
    formError.value = null;
    try {
      final current = editing.value;
      if (current == null) {
        await _service.create(
          structureUid: _auth.uid,
          structureName: _structureName,
          category: category.value,
          title: title,
          description: descriptionCtrl.text,
          documents: documents,
          lieu: lieuCtrl.text,
          cout: coutCtrl.text,
          delai: delaiCtrl.text,
          etapes: etapes,
          echeanceJours: jours,
          echeanceDepuis: jours == null ? null : depuis,
        );
      } else {
        await _service.update(
          current.copyWith(
            // Le nom affiché suit celui du compte : une structure qui se
            // renomme ne doit pas laisser l'ancien nom sur ses démarches.
            structureName: _structureName,
            category: category.value,
            title: title,
            description: descriptionCtrl.text,
            documents: documents,
            lieu: lieuCtrl.text,
            cout: coutCtrl.text,
            delai: delaiCtrl.text,
            etapes: etapes,
            echeanceJours: jours,
            echeanceDepuis: jours == null ? null : depuis,
            clearEcheance: jours == null,
          ),
        );
      }
      return true;
    } catch (e) {
      developer.log('save', name: 'StructureDemarchesController', error: e);
      formError.value =
          'Enregistrement impossible. Vérifiez votre connexion puis '
          'réessayez.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<String?> remove(Demarche demarche) async {
    try {
      await _service.delete(demarche.id);
      return null;
    } catch (e) {
      developer.log('remove', name: 'StructureDemarchesController', error: e);
      return 'Suppression impossible. Vérifiez votre connexion.';
    }
  }

  static List<String> _lines(String raw) =>
      raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
