import 'dart:async';

import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/market_item.dart';
import '../services/upload_failure.dart';
import '../services/auth_service.dart';
import '../services/market_service.dart';
import '../services/user_profile_service.dart';

/// Formulaire d'annonce, en création comme en modification.
///
/// Le mode est déterminé par l'argument de route : un [MarketItem] passé
/// à l'écran ouvre le formulaire pré-rempli sur cette annonce.
class MarketComposeController extends GetxController {
  final titleCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final customPlaceCtrl = TextEditingController();

  /// Location : durée minimale, dans l'unité choisie (facultative).
  final rentalMinCtrl = TextEditingController();

  final listingType = MarketListingType.vente.obs;
  final category = MarketCategory.divers.obs;
  final negotiable = false.obs;
  final priceOnRequest = false.obs;
  final condition = Rxn<ItemCondition>();

  /// Location : le prix s'entend par heure, par jour ou par mois.
  final rentalUnit = RentalUnit.jour.obs;

  bool get isRental => listingType.value == MarketListingType.location;

  /// Lieu choisi dans la liste, ou [MarketPlaces.autre] quand la personne
  /// préfère saisir le sien.
  final place = RxnString();

  /// Photos de l'annonce, dans l'ordre d'affichage. Une entrée est soit
  /// une URL https (photo déjà en ligne, conservée telle quelle), soit un
  /// chemin de fichier local (nouvelle photo à envoyer).
  final images = <String>[].obs;

  final isPublishing = false.obs;
  final isLoadingExisting = false.obs;
  final _formTick = 0.obs;

  /// Annonce en cours de modification, `null` en création.
  MarketItem? editing;
  bool get isEditing => editing != null;

  static const maxImages = 5;

  MarketService get _market => Get.find<MarketService>();

  @override
  void onInit() {
    super.onInit();
    titleCtrl.addListener(_bumpFormTick);
    phoneCtrl.addListener(_bumpFormTick);
    customPlaceCtrl.addListener(_bumpFormTick);

    final args = Get.arguments;
    if (args is MarketItem) {
      _loadForEdit(args);
    } else {
      unawaited(_prefillPhoneFromProfile());
    }
  }

  /// Le numéro du profil est proposé par défaut : à Foumbot c'est le même
  /// dans 99 % des cas, et le saisir à chaque annonce est la première
  /// raison d'abandonner un formulaire.
  ///
  /// Lu dans les coordonnées privées, pas sur le profil public : le
  /// numéro n'y figure plus, il aurait suffi d'une requête pour aspirer
  /// celui de toute la commune.
  Future<void> _prefillPhoneFromProfile() async {
    final contact = await Get.find<UserProfileService>().loadContact();
    final phone = contact.phoneNumber?.trim() ?? '';
    // L'écran a pu être quitté, ou quelque chose déjà saisi, pendant la
    // lecture : dans les deux cas on ne touche à rien.
    if (phone.isNotEmpty && phoneCtrl.text.isEmpty) phoneCtrl.text = phone;
  }

  Future<void> _loadForEdit(MarketItem item) async {
    editing = item;
    isLoadingExisting.value = true;
    titleCtrl.text = item.title;
    descriptionCtrl.text = item.description;
    priceCtrl.text = item.price > 0 ? item.price.toString() : '';
    listingType.value = item.listingType;
    category.value = item.category;
    negotiable.value = item.negotiable;
    priceOnRequest.value = item.priceOnRequest;
    condition.value = item.condition;
    rentalUnit.value = item.rentalUnitOrDefault;
    rentalMinCtrl.text = (item.rentalMinDuration ?? 0) > 0
        ? item.rentalMinDuration.toString()
        : '';
    images.assignAll(item.imageUrls);

    if (MarketPlaces.values.contains(item.location)) {
      place.value = item.location;
    } else if (item.location.isNotEmpty) {
      place.value = MarketPlaces.autre;
      customPlaceCtrl.text = item.location;
    }

    // Le numéro n'est pas dans le document de l'annonce : il faut aller
    // le chercher dans la sous-collection pour pré-remplir le champ.
    final phone = await _market.fetchPhone(item);
    if (phone != null) phoneCtrl.text = phone;
    isLoadingExisting.value = false;
    _bumpFormTick();
  }

  void _bumpFormTick() => _formTick.value++;

  /// Lieu final envoyé à Firestore.
  String get resolvedPlace {
    final selected = place.value;
    if (selected == null) return '';
    if (selected == MarketPlaces.autre) return customPlaceCtrl.text.trim();
    return selected;
  }

  bool get canSubmit {
    _formTick.value;
    place.value;
    return titleCtrl.text.trim().isNotEmpty &&
        phoneCtrl.text.trim().isNotEmpty &&
        resolvedPlace.isNotEmpty &&
        !isPublishing.value &&
        !isLoadingExisting.value;
  }

  @override
  void onClose() {
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    priceCtrl.dispose();
    phoneCtrl.dispose();
    customPlaceCtrl.dispose();
    rentalMinCtrl.dispose();
    super.onClose();
  }

  void selectListingType(MarketListingType type) => listingType.value = type;
  void selectCategory(MarketCategory cat) => category.value = cat;
  void selectRentalUnit(RentalUnit unit) => rentalUnit.value = unit;

  int? get _rentalMin {
    final n = int.tryParse(rentalMinCtrl.text.replaceAll(RegExp(r'\D'), ''));
    return n != null && n > 0 ? n : null;
  }

  void toggleNegotiable() => negotiable.value = !negotiable.value;

  void selectPlace(String? value) {
    place.value = value;
    if (value != MarketPlaces.autre) customPlaceCtrl.clear();
    _bumpFormTick();
  }

  void togglePriceOnRequest() {
    priceOnRequest.value = !priceOnRequest.value;
    if (priceOnRequest.value) priceCtrl.clear();
  }

  void selectCondition(ItemCondition? c) {
    condition.value = condition.value == c ? null : c;
  }

  bool get showCondition {
    final cat = category.value;
    return cat == MarketCategory.vehicules ||
        cat == MarketCategory.electronique ||
        cat == MarketCategory.divers ||
        cat == MarketCategory.vetements;
  }

  /// Sélection des photos, **redimensionnées et recompressées à la
  /// source**.
  ///
  /// Une photo d'appareil récent pèse plusieurs mégaoctets. Envoyée
  /// telle quelle, elle coûte au vendeur son forfait à la publication, et
  /// à chaque habitant qui ouvre la grille — pour une image affichée sur
  /// 200 pixels de large. 1280 px et qualité 70 suffisent largement à une
  /// annonce, et divisent le poids par dix ou plus.
  Future<void> pickImages() async {
    if (images.length >= maxImages) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      limit: maxImages - images.length,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    for (final file in picked) {
      if (images.length >= maxImages) break;
      images.add(file.path);
    }
  }

  void removeImage(int index) {
    if (index >= 0 && index < images.length) images.removeAt(index);
  }

  /// Réordonne les photos — la première sert de vignette dans la grille,
  /// c'est donc un vrai réglage et pas un détail cosmétique.
  void moveImage(int from, int to) {
    if (from < 0 || from >= images.length) return;
    if (to < 0 || to >= images.length) return;
    final entry = images.removeAt(from);
    images.insert(to, entry);
  }

  int get _price => priceOnRequest.value
      ? 0
      : (int.tryParse(priceCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0);

  Future<MarketItem?> submit() async {
    if (isPublishing.value) return null;
    isPublishing.value = true;
    try {
      final existing = editing;
      if (existing != null) {
        return await _market.updateListing(
          original: existing,
          listingType: listingType.value,
          category: category.value,
          title: titleCtrl.text,
          description: descriptionCtrl.text,
          location: resolvedPlace,
          sellerPhone: phoneCtrl.text,
          price: _price,
          negotiable: negotiable.value,
          priceOnRequest: priceOnRequest.value,
          condition: showCondition ? condition.value : null,
          rentalUnit: isRental ? rentalUnit.value : null,
          rentalMinDuration: isRental ? _rentalMin : null,
          images: List.of(images),
        );
      }

      final auth = Get.find<AuthService>();
      final profile = Get.find<UserProfileService>().profile.value!;
      return await _market.createListing(
        listingType: listingType.value,
        category: category.value,
        title: titleCtrl.text,
        description: descriptionCtrl.text,
        price: _price,
        negotiable: negotiable.value,
        priceOnRequest: priceOnRequest.value,
        condition: showCondition ? condition.value : null,
        rentalUnit: isRental ? rentalUnit.value : null,
        rentalMinDuration: isRental ? _rentalMin : null,
        sellerUid: auth.uid,
        sellerName: profile.displayName,
        sellerPhone: phoneCtrl.text,
        location: resolvedPlace,
        localImagePaths: images.where((e) => !e.startsWith('http')).toList(),
      );
    } catch (e) {
      // Sans ce filet, l'échec remontait dans le vide : l'exception
      // s'échappait du callback du bouton, la page restait ouverte et
      // rien ne disait que l'annonce n'était pas partie.
      developer.log(
        'Publication d’annonce',
        name: 'MarketComposeController',
        error: e,
      );
      _notify(
        isEditing ? 'Enregistrement impossible' : 'Publication impossible',
        uploadFailureMessage(e),
      );
      return null;
    } finally {
      isPublishing.value = false;
    }
  }

  void _notify(String title, String message) {
    if (Get.overlayContext == null) return;
    Get.snackbar(title, message, duration: const Duration(seconds: 4));
  }
}
