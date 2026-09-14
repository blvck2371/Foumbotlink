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

  /// Les modèles que la structure n'a pas encore repris, comparés par
  /// intitulé : réimporter en double n'aiderait personne.
  List<DemarcheModele> get modelesDisponibles {
    final existing = demarches.map((d) => d.title.toLowerCase().trim()).toSet();
    return DemarcheModele.catalogue
        .where((m) => !existing.contains(m.title.toLowerCase().trim()))
        .toList();
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
  /// modification, prérempli depuis un modèle quand on en reprend un.
  void startEditing({Demarche? demarche, DemarcheModele? modele}) {
    editing.value = demarche;
    formError.value = null;

    category.value =
        demarche?.category ?? modele?.category ?? DemarcheCategory.etatCivil;
    titleCtrl.text = demarche?.title ?? modele?.title ?? '';
    descriptionCtrl.text = demarche?.description ?? modele?.description ?? '';
    lieuCtrl.text = demarche?.lieu ?? modele?.lieu ?? '';
    coutCtrl.text = demarche?.cout ?? modele?.cout ?? '';
    delaiCtrl.text = demarche?.delai ?? modele?.delai ?? '';
    documentsCtrl.text =
        (demarche?.documents ?? modele?.documents ?? const <String>[]).join('\n');
    etapesCtrl.text =
        (demarche?.etapes ?? modele?.etapes ?? const <String>[]).join('\n');
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

  /// Reprend d'un geste les modèles pas encore publiés.
  ///
  /// Ce ne sont que des points de départ : une fois importés, ils
  /// appartiennent à la structure, qui doit y corriger ses propres lieux,
  /// tarifs et délais.
  Future<String?> importerModeles() async {
    if (!canPublish) {
      return 'Votre compte structure doit être validé avant de publier des '
          'démarches.';
    }
    final modeles = modelesDisponibles;
    if (modeles.isEmpty) return 'Tous les modèles sont déjà repris.';

    isSaving.value = true;
    try {
      await _service.importModeles(
        structureUid: _auth.uid,
        structureName: _structureName,
        modeles: modeles,
      );
      return null;
    } catch (e) {
      developer.log('importerModeles',
          name: 'StructureDemarchesController', error: e);
      return 'Import impossible. Vérifiez votre connexion.';
    } finally {
      isSaving.value = false;
    }
  }

  /// Une ligne vide n'est pas une pièce à fournir : on les écarte plutôt
  /// que d'afficher des puces vides à l'habitant.
  static List<String> _lines(String raw) => raw
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
