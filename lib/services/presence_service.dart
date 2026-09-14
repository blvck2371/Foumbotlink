import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'auth_service.dart';

/// Présence "en ligne" — Firestore seul ne peut pas détecter un crash ou
/// une coupure réseau brutale (contrairement à Realtime Database avec
/// `onDisconnect`), donc on utilise un battement de cœur : tant que l'app
/// est au premier plan, on rafraîchit `users/{uid}.lastSeenAt` toutes les
/// 25s. Le calcul "en ligne" (voir UserProfile.isOnline) considère le
/// compte hors ligne dès que ce battement s'arrête depuis plus de 40s —
/// pas besoin d'écrire explicitement "hors ligne" pour que ça se corrige.
class PresenceService extends GetxService with WidgetsBindingObserver {
  final _db = FirebaseFirestore.instance;
  Timer? _heartbeat;
  Worker? _authWorker;

  AuthService get _auth => Get.find<AuthService>();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    _authWorker = ever<User?>(_auth.firebaseUser, (user) {
      if (user != null) {
        goOnline();
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
    });

    if (_auth.isSignedIn) {
      goOnline();
      _startHeartbeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_auth.isSignedIn) return;
    switch (state) {
      case AppLifecycleState.resumed:
        goOnline();
        _startHeartbeat();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopHeartbeat();
      default:
        break;
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) => goOnline());
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> goOnline() async {
    if (!_auth.isSignedIn) return;
    try {
      await _db.collection('users').doc(_auth.uid).set({
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (_) {}
  }

  /// À appeler explicitement avant une déconnexion volontaire, pour que
  /// le contact ne paraisse pas "en ligne" pendant les ~40s suivant le
  /// dernier battement.
  Future<void> goOffline() async {
    _stopHeartbeat();
    if (!_auth.isSignedIn) return;
    try {
      await _db.collection('users').doc(_auth.uid).set({
        'lastSeenAt': null,
      }, SetOptions(merge: true));
    } on FirebaseException catch (_) {}
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _authWorker?.dispose();
    _stopHeartbeat();
    super.onClose();
  }
}
