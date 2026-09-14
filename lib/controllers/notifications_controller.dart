import 'dart:async';

import 'package:get/get.dart';

import '../models/app_notification.dart';
import '../services/auth_service.dart';
import '../services/notification_router.dart';
import '../services/notification_service.dart';

class NotificationsController extends GetxController {
  final notifications = <AppNotification>[].obs;
  final isLoading = true.obs;

  StreamSubscription? _sub;

  AuthService get _auth => Get.find<AuthService>();
  NotificationService get _notifs => Get.find<NotificationService>();

  int get unreadCount => notifications.where((n) => !n.read).length;

  @override
  void onInit() {
    super.onInit();
    if (!_auth.isSignedIn) {
      isLoading.value = false;
      return;
    }
    final uid = _auth.uid;
    _sub = _notifs.watch(
      uid: uid,
      onData: (list) {
        notifications.assignAll(list);
        isLoading.value = false;
      },
      onError: (_) => isLoading.value = false,
    );
    _notifs.checkAppUpdate(uid);
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> markAllRead() async {
    if (!_auth.isSignedIn) return;
    final unreadIds = notifications
        .where((n) => !n.read)
        .map((n) => n.id)
        .toList();
    await _notifs.markAllRead(_auth.uid, unreadIds);
  }

  Future<void> open(AppNotification n) async {
    if (!n.read && _auth.isSignedIn) {
      _notifs.markRead(_auth.uid, n.id).catchError((_) {});
    }

    // Même aiguillage que pour un tap sur une bannière push (voir
    // NotificationRouter) : on reconstitue la forme `data` FCM.
    NotificationRouter.routeFromData({
      'type': n.type.name,
      ...n.data,
      if (n.fromUid != null) 'fromUid': n.fromUid,
    });
  }
}
