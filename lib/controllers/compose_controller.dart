import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../models/feed_item.dart';
import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/user_profile_service.dart';

class ComposeController extends GetxController {
  static const _maxImages = 5;

  final postKind = FeedType.info.obs;
  final images = <String>[].obs;
  final isPublishing = false.obs;
  final _formTick = 0.obs;

  final titleCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();

  FeedService get _feed => Get.find<FeedService>();
  AuthService get _auth => Get.find<AuthService>();
  UserProfileService get _profiles => Get.find<UserProfileService>();

  bool get canPublishOfficialContent =>
      _profiles.profile.value?.accountType.canPublishOfficialContent ?? false;

  @override
  void onInit() {
    super.onInit();
    titleCtrl.addListener(_bumpFormTick);
    bodyCtrl.addListener(_bumpFormTick);
  }

  void _bumpFormTick() => _formTick.value++;

  bool get canSubmit {
    _formTick.value;
    return titleCtrl.text.trim().isNotEmpty &&
        bodyCtrl.text.trim().isNotEmpty &&
        !isPublishing.value;
  }

  void selectPostKind(FeedType kind) {
    postKind.value = kind;
  }

  Future<void> pickImages() async {
    final remaining = _maxImages - images.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    images.addAll(picked.map((f) => f.path));
  }

  void removeImage(int index) => images.removeAt(index);

  Future<FeedItem?> submit() async {
    if (isPublishing.value) return null;
    isPublishing.value = true;
    try {
      final profile = _profiles.profile.value!;
      final official = profile.accountType.canPublishOfficialContent;
      final feedType = official ? postKind.value : FeedType.post;
      final authorSubtitle = official
          ? (postKind.value == FeedType.annonce
              ? 'Annonce officielle'
              : 'Information')
          : profile.authorSubtitle;

      return await _feed.createPost(
        type: feedType,
        title: titleCtrl.text,
        body: bodyCtrl.text,
        authorUid: _auth.uid,
        authorName: profile.displayName,
        authorSubtitle: authorSubtitle,
        authorVerified: profile.verified,
        localImagePaths: images,
      );
    } finally {
      isPublishing.value = false;
    }
  }

  @override
  void onClose() {
    titleCtrl.dispose();
    bodyCtrl.dispose();
    super.onClose();
  }
}
