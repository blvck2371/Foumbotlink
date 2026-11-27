import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pro_listing.dart';
import '../models/report.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/directory_service.dart';
import '../services/moderation_service.dart';
import '../services/profile_gate.dart';
import '../widgets/report_sheet.dart';

/// Annuaire des professionnels : liste classée, filtres par métier,
/// recherche, et actions de contact partagées avec la fiche.
class DirectoryController extends GetxController {
  final _service = Get.find<DirectoryService>();
  final _auth = Get.find<AuthService>();

  final listings = <ProListing>[].obs;
  final isLoading = true.obs;
  final error = RxnString();

  /// Métier sélectionné ; `null` = tous.
  final category = Rxn<ProCategory>();
  final query = ''.obs;
  final searchCtrl = TextEditingController();

  StreamSubscription<List<ProListing>>? _sub;

  String get myUid => _auth.isSignedIn ? _auth.uid : '';

  /// Fiche du compte courant, si elle existe.
  ProListing? get myListing =>
      myUid.isEmpty ? null : listings.firstWhereOrNull((l) => l.id == myUid);

  /// Liste affichée : métier puis recherche, en gardant l'ordre du
  /// classement (meilleure note et plus d'avis d'abord).
  List<ProListing> get visible {
    final cat = category.value;
    final words = ProListing.normalize(query.value)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return listings.where((l) {
      if (cat != null && l.category != cat) return false;
      if (words.isEmpty) return true;
      final text = l.searchText;
      return words.every(text.contains);
    }).toList();
  }

  /// Nombre de fiches par métier, pour n'afficher que les puces utiles.
  Map<ProCategory, int> get countsByCategory {
    final counts = <ProCategory, int>{};
    for (final l in listings) {
      counts[l.category] = (counts[l.category] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void onInit() {
    super.onInit();
    final arg = Get.arguments;
    if (arg is Map && arg['category'] is String) {
      category.value = ProCategory.fromKey(arg['category'] as String);
    }
    load();
  }

  @override
  void onClose() {
    _sub?.cancel();
    searchCtrl.dispose();
    super.onClose();
  }

  /// Suit l'annuaire en direct : le cache local s'affiche tout de suite,
  /// puis chaque fiche créée, modifiée ou renotée remonte d'elle-même.
  Future<void> load() async {
    error.value = null;
    await _sub?.cancel();
    _sub = _service.watchAll().listen(
      (list) {
        listings.assignAll(list);
        error.value = null;
        isLoading.value = false;
      },
      onError: (Object e) {
        error.value = 'Impossible de charger l’annuaire : $e';
        isLoading.value = false;
      },
    );
  }

  void setQuery(String value) => query.value = value;

  void clearQuery() {
    searchCtrl.clear();
    query.value = '';
  }

  void toggleCategory(ProCategory c) =>
      category.value = category.value == c ? null : c;

  /// Remplace une fiche dans la liste après modification ou nouvel avis,
  /// et retrie.
  void upsertLocal(ProListing listing) {
    final i = listings.indexWhere((l) => l.id == listing.id);
    if (i >= 0) {
      listings[i] = listing;
    } else {
      listings.add(listing);
    }
    listings.sort(DirectoryService.compareRank);
  }

  void removeLocal(String id) => listings.removeWhere((l) => l.id == id);

  Future<void> openDetail(ProListing listing) async {
    await Get.toNamed(AppRoutes.directoryDetail, arguments: listing);
  }

  /// Créer ou modifier sa fiche : il faut un profil complet, puisque la
  /// fiche est rattachée au compte.
  Future<void> openEditor() async {
    final ok = await ProfileGate.ensure(
      reason: 'Pour apparaître dans l’annuaire',
    );
    if (!ok) return;
    final mine = myListing ?? await _service.fetch(_auth.uid);
    final saved = await Get.toNamed(AppRoutes.directoryEdit, arguments: mine);
    if (saved is ProListing) {
      upsertLocal(saved);
      await Get.toNamed(AppRoutes.directoryDetail, arguments: saved);
    } else if (saved == false) {
      removeLocal(_auth.uid);
    }
  }

  // ---------------------------------------------------------------------
  // Contact
  // ---------------------------------------------------------------------

  /// Coordonnées du professionnel. Réservées aux comptes connectés :
  /// renvoie `null` si l'utilisateur refuse de se connecter.
  Future<ProContact?> revealContact(ProListing pro) async {
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return null;
    }
    try {
      return await _service.contact(pro.id);
    } on Object catch (e) {
      _toast('Coordonnées indisponibles : $e');
      return null;
    }
  }

  Future<void> call(ProListing pro) async {
    final contact = await revealContact(pro);
    final phone = _dialable(contact?.phone ?? '');
    if (phone.isEmpty) {
      if (contact != null) _toast('Aucun numéro renseigné.');
      return;
    }
    await _service.recordContact(proUid: pro.id, myUid: myUid, channel: 'call');
    await _launch(Uri(scheme: 'tel', path: phone));
  }

  Future<void> whatsapp(ProListing pro) async {
    final contact = await revealContact(pro);
    final number = _whatsappNumber(contact?.whatsappOrPhone ?? '');
    if (number.isEmpty) {
      if (contact != null) _toast('Aucun numéro WhatsApp renseigné.');
      return;
    }
    await _service.recordContact(
      proUid: pro.id,
      myUid: myUid,
      channel: 'whatsapp',
    );
    final text = 'Bonjour, je vous contacte depuis l’annuaire Foumbot Link '
        '(${pro.categoryLabel}).';
    await _launch(
      Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> message(ProListing pro) async {
    final ok = await ProfileGate.ensure(reason: 'Pour écrire à ce professionnel');
    if (!ok || pro.id == _auth.uid) return;
    await _service.recordContact(proUid: pro.id, myUid: myUid, channel: 'chat');
    Get.toNamed(
      AppRoutes.chat,
      arguments: {
        'otherUid': pro.id,
        'prefill': 'Bonjour, je vous contacte depuis l’annuaire '
            '(${pro.categoryLabel}).',
      },
    );
  }

  Future<void> report(ProListing pro) async {
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      if (!_auth.isSignedIn) return;
    }
    final choice = await showReportSheet(targetLabel: 'cette fiche');
    if (choice == null) return;
    try {
      await Get.find<ModerationService>().report(
        ContentReport(
          targetType: ReportTargetType.proListing,
          targetId: pro.id,
          targetPath: 'directory/${pro.id}',
          targetOwnerUid: pro.id,
          reporterUid: _auth.uid,
          reason: choice.reason,
          details: choice.details,
          excerpt: '${pro.name} — ${pro.categoryLabel}',
        ),
      );
      _toast('Signalement envoyé. Merci.');
    } on Object catch (e) {
      _toast('Signalement impossible : $e');
    }
  }

  String _dialable(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    return s;
  }

  /// Numéro international sans `+`, pour `wa.me`. Un numéro camerounais
  /// local à 9 chiffres (6XXXXXXXX) est préfixé 237.
  String _whatsappNumber(String raw) {
    final s = _dialable(raw);
    if (s.startsWith('+')) return s.substring(1);
    if (s.length == 9 && s.startsWith('6')) return '237$s';
    return s;
  }

  Future<void> _launch(Uri uri, {LaunchMode? mode}) async {
    try {
      final ok = await launchUrl(uri, mode: mode ?? LaunchMode.platformDefault);
      if (!ok) _toast('Aucune application pour ouvrir « ${uri.scheme} »');
    } on Object catch (e) {
      _toast('Action impossible : $e');
    }
  }

  void _toast(String message) => Get.snackbar(
    'Annuaire',
    message,
    snackPosition: SnackPosition.BOTTOM,
  );
}
