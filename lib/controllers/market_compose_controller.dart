import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/market_item.dart';
import '../services/auth_service.dart';
import '../services/market_service.dart';
import '../services/user_profile_service.dart';

class MarketComposeController extends GetxController {
  final titleCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final locationCtrl = TextEditingController();

  final listingType = MarketListingType.vente.obs;
  final category = MarketCategory.divers.obs;
  final negotiable = false.obs;
  final priceOnRequest = false.obs;
  final condition = Rxn<ItemCondition>();
  final images = <String>[].obs;
  final isPublishing = false.obs;
  final _formTick = 0.obs;

  @override
  void onInit() {
    super.onInit();
    titleCtrl.addListener(_bumpFormTick);
    phoneCtrl.addListener(_bumpFormTick);
    locationCtrl.addListener(_bumpFormTick);
  }

  void _bumpFormTick() => _formTick.value++;

  bool get canSubmit {
    _formTick.value;
    return titleCtrl.text.trim().isNotEmpty &&
        phoneCtrl.text.trim().isNotEmpty &&
        locationCtrl.text.trim().isNotEmpty &&
        !isPublishing.value;
  }

  @override
  void onClose() {
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    priceCtrl.dispose();
    phoneCtrl.dispose();
    locationCtrl.dispose();
    super.onClose();
  }

  void selectListingType(MarketListingType type) => listingType.value = type;
  void selectCategory(MarketCategory cat) => category.value = cat;
  void toggleNegotiable() => negotiable.value = !negotiable.value;

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

  Future<void> pickImages() async {
    if (images.length >= 5) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(limit: 5 - images.length);
    for (final file in picked) {
      if (images.length >= 5) break;
      images.add(file.path);
    }
  }

  void removeImage(int index) {
    if (index >= 0 && index < images.length) images.removeAt(index);
  }

  Future<MarketItem?> submit() async {
    if (isPublishing.value) return null;
    isPublishing.value = true;
    try {
      final auth = Get.find<AuthService>();
      final profile = Get.find<UserProfileService>().profile.value!;
      return await Get.find<MarketService>().createListing(
        listingType: listingType.value,
        category: category.value,
        title: titleCtrl.text,
        description: descriptionCtrl.text,
        price: priceOnRequest.value
            ? 0
            : (int.tryParse(priceCtrl.text.replaceAll(RegExp(r'\D'), '')) ??
                0),
        negotiable: negotiable.value,
        priceOnRequest: priceOnRequest.value,
        condition: condition.value,
        sellerUid: auth.uid,
        sellerName: profile.displayName,
        sellerPhone: phoneCtrl.text,
        location: locationCtrl.text,
        localImagePaths: List.of(images),
      );
    } finally {
      isPublishing.value = false;
    }
  }
}
