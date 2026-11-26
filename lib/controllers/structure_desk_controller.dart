import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/demarche.dart';
import '../models/dossier.dart';
import '../services/auth_service.dart';
import '../services/demarche_service.dart';
import '../services/dossier_service.dart';
import '../services/user_profile_service.dart';

/// Côté guichet : réception d'un dossier et suivi de ceux du service.
///
/// Réservé aux comptes structure **validés** — les règles Firestore le
/// vérifient aussi côté serveur, ce contrôle-ci ne fait qu'éviter de
/// proposer un écran qui refuserait toute écriture.
class StructureDeskController extends GetxController {
  /// Saisie du code lu sur la chemise.
  final codeCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  final referenceCtrl = TextEditingController();

  /// L'habitant reconnu derrière le code, tant que la réception n'est pas
  /// enregistrée.
  final matchedUid = RxnString();
  final matchedName = RxnString();
  final lookupError = RxnString();
  final isLooking = false.obs;
  final isSaving = false.obs;

  /// Dernière saisie interrogée, pour ne pas rouvrir la même écoute à
  /// chaque notification du contrôleur de texte (le curseur bouge aussi).
  String? _lastQueried;

  /// Démarche choisie parmi **celles de la structure**, ou `null` pour un
  /// intitulé libre. Le catalogue n'est plus commun à tout le monde : ce
  /// sont les démarches que ce guichet a lui-même publiées.
  final selectedDemarche = Rxn<Demarche>();

  /// Les démarches de cette structure, suivies en direct : une démarche
  /// créée depuis l'écran de gestion apparaît ici sans réouvrir le
  /// guichet.
  final demarches = <Demarche>[].obs;

  final dossiers = <Dossier>[].obs;
  final isLoading = true.obs;

  /// Filtre de la liste : ce que le guichet a en cours, ou tout.
  final showClosed = false.obs;

  StreamSubscription? _sub;
  StreamSubscription? _demarchesSub;
  StreamSubscription? _codeSub;

  DossierService get _dossiers => Get.find<DossierService>();
  DemarcheService get _demarches => Get.find<DemarcheService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  String get _structureName =>
      _profiles.profile.value?.displayName ?? 'Structure';

  bool get canReceive => matchedUid.value != null && _resolvedTitle.isNotEmpty;

  String get _resolvedTitle =>
      selectedDemarche.value?.title ?? titleCtrl.text.trim();

  List<Dossier> get visible => showClosed.value
      ? dossiers
      : dossiers.where((d) => !d.status.isClosed).toList();

  /// Les dossiers en attente d'un geste du service — ce sur quoi le
  /// guichet doit travailler aujourd'hui.
  int get pendingCount => dossiers.where((d) => !d.status.isClosed).length;

  @override
  void onInit() {
    super.onInit();
    _watch();
    _watchDemarches();
    // La recherche suit la frappe : l'agent n'a plus à appuyer sur un
    // bouton puis à attendre. Voir [_onCodeChanged].
    codeCtrl.addListener(_onCodeChanged);
  }

  @override
  void onClose() {
    codeCtrl.removeListener(_onCodeChanged);
    codeCtrl.dispose();
    titleCtrl.dispose();
    referenceCtrl.dispose();
    _sub?.cancel();
    _demarchesSub?.cancel();
    _codeSub?.cancel();
    super.onClose();
  }

  void _watchDemarches() {
    _demarchesSub?.cancel();
    _demarchesSub = _demarches.watchByStructure(
      structureUid: _auth.uid,
      onData: (list) {
        demarches.assignAll(list);
        // La démarche sélectionnée vient d'être supprimée ou renommée
        // depuis l'écran de gestion : on recale plutôt que de garder un
        // objet fantôme qui partirait tel quel dans le dossier.
        final current = selectedDemarche.value;
        if (current == null) return;
        final fresh = list.where((d) => d.id == current.id).firstOrNull;
        selectedDemarche.value = fresh;
      },
    );
  }

  void _watch() {
    _sub?.cancel();
    _sub = _dossiers.watchStructure(
      structureUid: _auth.uid,
      onData: (list) {
        dossiers.assignAll(list);
        isLoading.value = false;
      },
      onError: (_) => isLoading.value = false,
    );
  }

  // -----------------------------------------------------------------------
  // Réception
  // -----------------------------------------------------------------------

  /// Relance la recherche à chaque frappe.
  ///
  /// Tant que le code est incomplet, on n'affiche aucune erreur : signaler
  /// « il manque des caractères » pendant que l'agent tape ne l'aide pas.
  /// Dès qu'il atteint sept caractères, l'écoute s'ouvre et le résultat
  /// tombe — servi d'abord par le cache local, donc sans attente.
  void _onCodeChanged() {
    final raw = codeCtrl.text;
    if (raw == _lastQueried) return;
    _lastQueried = raw;

    _codeSub?.cancel();
    _codeSub = null;
    matchedUid.value = null;
    matchedName.value = null;
    lookupError.value = null;

    final normalized = TrackingCode.normalize(raw);
    if (normalized.length < TrackingCode.length) {
      isLooking.value = false;
      return;
    }

    isLooking.value = true;
    _codeSub = _dossiers
        .watchCode(raw)
        .listen(
          (result) {
            isLooking.value = false;
            switch (result) {
              case CodeFound(:final uid, :final displayName):
                matchedUid.value = uid;
                matchedName.value = displayName;
                lookupError.value = null;
              case CodeUnknown(:final message):
                matchedUid.value = null;
                matchedName.value = null;
                lookupError.value = message;
            }
          },
          onError: (Object e) {
            developer.log(
              'watchCode',
              name: 'StructureDeskController',
              error: e,
            );
            isLooking.value = false;
            lookupError.value =
                'Recherche impossible pour le moment. Vérifiez la connexion.';
          },
        );
  }

  /// Force une nouvelle recherche sur la saisie courante — le bouton reste
  /// utile quand l'agent veut réessayer après une coupure réseau.
  void lookup() {
    _lastQueried = null;
    _onCodeChanged();
  }

  void selectDemarche(Demarche? demarche) {
    selectedDemarche.value = demarche;
    if (demarche != null) titleCtrl.clear();
  }

  /// Enregistre l'arrivée du dossier. C'est ce geste qui déclenche le
  /// suivi côté habitant.
  Future<bool> receive() async {
    final uid = matchedUid.value;
    final title = _resolvedTitle;
    if (uid == null || title.isEmpty || isSaving.value) return false;

    isSaving.value = true;
    try {
      await _dossiers.receiveDossier(
        ownerUid: uid,
        ownerName: matchedName.value ?? 'Habitant',
        trackingCode: TrackingCode.normalize(codeCtrl.text),
        structureUid: _auth.uid,
        structureName: _structureName,
        title: title,
        demarcheId: selectedDemarche.value?.id,
        reference: referenceCtrl.text,
        // Les étapes de suivi que la structure a définies sur sa
        // démarche : le dossier les parcourra une à une.
        steps: selectedDemarche.value?.etapes ?? const [],
      );
      _resetForm();
      return true;
    } catch (e) {
      developer.log('receive', name: 'StructureDeskController', error: e);
      lookupError.value =
          'Enregistrement impossible. Vérifiez la connexion puis '
          'réessayez.';
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  void _resetForm() {
    _codeSub?.cancel();
    _codeSub = null;
    _lastQueried = null;
    codeCtrl.clear();
    titleCtrl.clear();
    referenceCtrl.clear();
    matchedUid.value = null;
    matchedName.value = null;
    selectedDemarche.value = null;
    lookupError.value = null;
  }

  void cancelReception() => _resetForm();

  // -----------------------------------------------------------------------
  // Avancement
  // -----------------------------------------------------------------------

  /// Fait passer [dossier] à [status]. Le motif est exigé là où son
  /// absence laisserait quelqu'un sans réponse.
  Future<String?> advance(
    Dossier dossier,
    DossierAction action, {
    String? note,
  }) async {
    if (action.requiresNote && (note == null || note.trim().isEmpty)) {
      return 'Indiquez ce qu’il manque, ou pourquoi le dossier est '
          'refusé : c’est ce que la personne lira.';
    }
    try {
      await _dossiers.advance(dossier: dossier, action: action, note: note);
      return null;
    } catch (e) {
      developer.log('advance', name: 'StructureDeskController', error: e);
      return 'Enregistrement impossible. Vérifiez la connexion.';
    }
  }

  /// Code lu par la caméra : il remplit le champ, et la recherche de
  /// l'habitant suit d'elle-même.
  bool useScanned(String raw) {
    final code = TrackingCode.fromScan(raw);
    if (code == null) return false;
    codeCtrl.text = code;
    return true;
  }
}
