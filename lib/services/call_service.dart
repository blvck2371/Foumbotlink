import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';

import '../models/call.dart';
import '../routes/app_routes.dart';
import 'auth_service.dart';
import 'callkit_helper.dart';

/// Les appels : chaque appel est un document `calls/{callId}` qui porte la
/// sonnerie (ringing → accepted → ended…). La voix et l'image passent par
/// LiveKit : les deux téléphones rejoignent la salle `call_{callId}` avec
/// un jeton remis par la Cloud Function `joinCall` ([joinRoom]).
///
/// Enregistré comme service permanent : c'est ce qui permet de détecter
/// un appel entrant tant que l'app est ouverte (premier ou arrière-plan),
/// même si l'utilisateur n'est pas sur l'écran de discussion concerné.
class CallService extends GetxService {
  final _db = FirebaseFirestore.instance;

  /// Appel entrant détecté pour l'utilisateur courant, ou `null`. Piloté
  /// par [_watchIncoming], observé par un binding global pour ouvrir
  /// l'écran d'appel automatiquement.
  final incomingCall = Rxn<Call>();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;

  /// Invitations à un appel de groupe déjà en cours (voir [_watchInvites]).
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invitesSub;
  String? _activeCallId;

  AuthService get _auth => Get.find<AuthService>();

  CollectionReference<Map<String, dynamic>> get _callsRef =>
      _db.collection('calls');

  @override
  void onInit() {
    super.onInit();
    _auth.firebaseUser.listen((user) {
      if (user != null) {
        _watchIncoming(user.uid);
      } else {
        _incomingSub?.cancel();
        _invitesSub?.cancel();
        incomingCall.value = null;
      }
    });
    if (_auth.isSignedIn) _watchIncoming(_auth.uid);

    // Filet de sécurité si le push FCM n'arrive pas (l'app est vivante donc
    // ce listener Firestore voit l'appel) : on lève la même UI d'appel
    // entrant native que le push, dédupliquée par `callId` côté OS. Le push
    // reste le chemin principal, seul capable de réveiller une app tuée.
    ever<Call?>(incomingCall, (call) {
      developer.log(
        'incomingCall changed: ${call?.id}, currentRoute=${Get.currentRoute}',
        name: 'CallService',
      );
      if (call == null) return;
      // Déjà en communication (ou sur l'écran d'appel) : on ne peut pas
      // interrompre l'appel en cours pour en ouvrir un second, donc on
      // signale occupé plutôt que de laisser sonner dans le vide jusqu'au
      // timeout de l'appelant.
      if (Get.currentRoute == AppRoutes.call) {
        leave(call.id, CallStatus.busy);
        return;
      }
      _presentIncoming(call);
    });
  }

  /// Lève l'écran d'appel entrant CallKit, en résolvant le nom de
  /// l'appelant pour l'affichage.
  Future<void> _presentIncoming(Call call) async {
    // Invitation à un appel de groupe : c'est celui qui nous ajoute qui
    // « appelle », pas l'appelant d'origine.
    final me = call.members[_auth.uid];
    final fromUid = me?.invitedBy ?? call.callerUid;
    var callerName = 'Appel entrant';
    try {
      final doc = await _db.collection('users').doc(fromUid).get();
      final name = (doc.data()?['displayName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) callerName = name;
    } on FirebaseException catch (_) {}
    if (me != null) callerName = '$callerName · appel de groupe';
    // Web : pas de CallKit. L'écran d'appel de l'app sait présenter un
    // appel entrant (« Accepter / Refuser ») : on l'ouvre directement,
    // tant que l'onglet est ouvert.
    if (kIsWeb) {
      markHandled(call.id);
      unawaited(
        Get.toNamed(
          AppRoutes.call,
          arguments: {
            'callId': call.id,
            'incoming': true,
            'otherUid': fromUid,
            'type': call.type,
            'conversationId': call.conversationId,
          },
        ),
      );
      return;
    }
    await showCallkitIncomingFromData({
      'callId': call.id,
      'callerUid': fromUid,
      'callerName': callerName,
      'callType': call.type.name,
      'conversationId': call.conversationId,
    });
  }

  void _watchIncoming(String myUid) {
    _watchInvites(myUid);
    _incomingSub?.cancel();
    developer.log('watching incoming calls for $myUid', name: 'CallService');
    // Filtre sur `createdAt` : au lancement de l'app, la première snapshot
    // renvoie tous les documents déjà "ringing" comme docChanges "added" —
    // sans cette borne, un appel abandonné (appelant parti sans annuler)
    // referait sonner le téléphone indéfiniment à chaque redémarrage.
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(seconds: 45)),
    );
    _incomingSub = _callsRef
        .where('calleeUid', isEqualTo: myUid)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen(
          (snap) {
            developer.log(
              'incoming snapshot: ${snap.docChanges.length} change(s)',
              name: 'CallService',
            );
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final call = Call.fromDoc(change.doc);
              developer.log(
                'incoming call ${call.id} from ${call.callerUid}',
                name: 'CallService',
              );
              if (call.id == _activeCallId) continue;
              incomingCall.value = call;
            }
          },
          onError: (e) {
            developer.log(
              'incoming calls listener error',
              name: 'CallService',
              error: e,
            );
            // Cette écoute tourne en fond en permanence, pas seulement sur
            // l'écran d'appel — sans ce snackbar, une erreur ici (règles,
            // index, réseau) ne serait jamais visible sur un téléphone
            // physique de test sans câble/console branchés.
            if (Get.overlayContext != null) {
              Get.snackbar(
                'Détection des appels entrants en erreur',
                '$e',
                duration: const Duration(seconds: 15),
                isDismissible: true,
              );
            }
          },
        );
  }

  /// Quelqu'un nous ajoute à un appel déjà en cours : le serveur nous inscrit
  /// dans `ringingUids` le temps que notre téléphone sonne.
  void _watchInvites(String myUid) {
    _invitesSub?.cancel();
    _invitesSub = _callsRef
        .where('ringingUids', arrayContains: myUid)
        .snapshots()
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final call = Call.fromDoc(change.doc);
              if (call.status != CallStatus.accepted) continue;
              if (call.members[myUid]?.state != CallMemberState.ringing) {
                continue;
              }
              if (call.id == _activeCallId) continue;
              developer.log('invitation ${call.id}', name: 'CallService');
              incomingCall.value = call;
            }
          },
          onError: (Object e) => developer.log(
            'invitations listener error',
            name: 'CallService',
            error: e,
          ),
        );
  }

  /// Marque l'appel courant comme "traité" (accepté, refusé ou ouvert)
  /// pour que [incomingCall] ne redéclenche pas l'écran automatiquement.
  void markHandled(String callId) {
    _activeCallId = callId;
    if (incomingCall.value?.id == callId) incomingCall.value = null;
  }

  Future<Call> createCall({
    required String conversationId,
    required String callerUid,
    required String calleeUid,
    required CallType type,
  }) async {
    final doc = _callsRef.doc();
    _activeCallId = doc.id;
    developer.log(
      'creating call ${doc.id} caller=$callerUid callee=$calleeUid',
      name: 'CallService',
    );
    await doc.set(
      Call(
        id: doc.id,
        conversationId: conversationId,
        callerUid: callerUid,
        calleeUid: calleeUid,
        type: type,
        status: CallStatus.ringing,
        createdAt: DateTime.now(),
      ).toMap(),
    );
    developer.log('call ${doc.id} written', name: 'CallService');
    return Call.fromDoc(await doc.get());
  }

  Stream<Call?> watchCall(String callId) {
    return _callsRef
        .doc(callId)
        .snapshots()
        .map((snap) => snap.exists ? Call.fromDoc(snap) : null);
  }

  /// L'appelé a décroché. `answeredAt` (horloge serveur) sert de référence
  /// commune aux deux appareils pour la durée affichée.
  Future<void> markAccepted(String callId) {
    return _callsRef.doc(callId).update({
      'status': CallStatus.accepted.name,
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }

  /// Invité d'un appel de groupe : on a décroché et rejoint la salle.
  Future<void> markJoined(String callId) {
    final me = _auth.uid;
    return _callsRef.doc(callId).update({
      'members.$me.state': CallMemberState.joined.name,
      'members.$me.at': FieldValue.serverTimestamp(),
      'ringingUids': FieldValue.arrayRemove([me]),
    });
  }

  /// Met fin à l'appel **pour cet appareil** : raccrocher, refuser, ne pas
  /// répondre, être occupé.
  ///
  /// Appel à deux : le statut de l'appel change, l'autre est coupé aussi.
  /// Appel de groupe : on n'écrit que notre propre ligne — les autres
  /// continuent, et le serveur clôt l'appel quand il ne reste personne.
  /// Le document est relu à chaque fois : un appel à deux peut être passé
  /// en groupe à tout moment.
  Future<void> leave(String callId, CallStatus reason) async {
    if (callId.isEmpty) return;
    try {
      final snap = await _callsRef.doc(callId).get();
      if (!snap.exists) return;
      final call = Call.fromDoc(snap);
      final me = _auth.uid;
      if (!call.isGroup || !call.members.containsKey(me)) {
        await updateStatus(callId, reason);
        return;
      }
      if (!(call.members[me]?.isActive ?? false)) return;
      final state = switch (reason) {
        CallStatus.declined => CallMemberState.declined,
        CallStatus.missed => CallMemberState.missed,
        CallStatus.busy => CallMemberState.busy,
        _ => CallMemberState.left,
      };
      await _callsRef.doc(callId).update({
        'members.$me.state': state.name,
        'members.$me.at': FieldValue.serverTimestamp(),
        'ringingUids': FieldValue.arrayRemove([me]),
      });
    } on FirebaseException catch (e) {
      developer.log('leave $callId', name: 'CallService', error: e);
    }
  }

  /// Ajoute [uid] à l'appel en cours. Rend son nom ; lève une
  /// [CallException] lisible si le serveur refuse.
  Future<String> invite(String callId, String uid) async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable(
            'inviteToCall',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call<Map<String, dynamic>>({'callId': callId, 'uid': uid});
      return (response.data['name'] as String?) ?? 'Cette personne';
    } on FirebaseFunctionsException catch (e) {
      developer.log('inviteToCall: ${e.code}', name: 'CallService', error: e);
      throw CallException(switch (e.code) {
        'unavailable' || 'deadline-exceeded' || 'internal' =>
          'Serveur d’appel injoignable. Vérifiez votre connexion.',
        _ => e.message ?? 'Impossible d’ajouter cette personne.',
      }, retryable: true);
    }
  }

  Future<void> updateStatus(String callId, CallStatus status) async {
    try {
      final data = <String, dynamic>{'status': status.name};
      if (status == CallStatus.ended ||
          status == CallStatus.declined ||
          status == CallStatus.missed ||
          status == CallStatus.busy) {
        data['endedAt'] = FieldValue.serverTimestamp();
      }
      await _callsRef.doc(callId).update(data);
    } on FirebaseException catch (_) {}
  }

  void clearActiveCall(String callId) {
    if (_activeCallId == callId) _activeCallId = null;
  }

  /// Vrai si `callId` est l'appel que cet appareil est en train de gérer.
  /// Sert notamment à ignorer le push `call_cancelled` que les Cloud
  /// Functions diffusent à *tous* les appareils de l'appelé quand il
  /// décroche : sans ce filtre, l'appareil qui vient de répondre coupe sa
  /// propre UI d'appel (et, sur iOS, sa session audio CallKit).
  bool isActiveCall(String? callId) =>
      callId != null && callId.isNotEmpty && callId == _activeCallId;

  // ---------------------------------------------------------------------
  // LiveKit
  // ---------------------------------------------------------------------

  /// Jeton d'entrée dans la salle LiveKit de l'appel. Refusé par le serveur
  /// si l'on n'est ni l'appelant ni l'appelé, si l'appel est déjà terminé,
  /// ou entre deux comptes dont l'un a bloqué l'autre.
  Future<CallTicket> joinRoom(String callId) async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable(
            'joinCall',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call<Map<String, dynamic>>({'callId': callId});
      final data = response.data;
      final url = data['url'] as String?;
      final token = data['token'] as String?;
      if (url == null || url.isEmpty || token == null || token.isEmpty) {
        throw const CallException('Réponse du serveur d’appel incomplète.');
      }
      return CallTicket(url: url, token: token);
    } on FirebaseFunctionsException catch (e) {
      developer.log('joinCall: ${e.code}', name: 'CallService', error: e);
      throw switch (e.code) {
        'not-found' ||
        'failed-precondition' => const CallException('Cet appel est terminé.'),
        'permission-denied' => CallException(
          e.message ?? 'Cet appel n’est pas possible.',
        ),
        'unavailable' || 'deadline-exceeded' || 'internal' =>
          const CallException(
            'Serveur d’appel injoignable. Vérifiez votre connexion.',
            retryable: true,
          ),
        _ => CallException(
          'Impossible de rejoindre l’appel (${e.code}).',
          retryable: true,
        ),
      };
    }
  }

  @override
  void onClose() {
    _incomingSub?.cancel();
    _invitesSub?.cancel();
    super.onClose();
  }
}

/// Accès à la salle LiveKit d'un appel.
class CallTicket {
  const CallTicket({required this.url, required this.token});
  final String url;
  final String token;
}

/// Refus ou panne lisible par l'utilisateur.
class CallException implements Exception {
  const CallException(this.message, {this.retryable = false});
  final String message;

  /// Panne passagère (réseau) : réessayer peut suffire. Sinon l'appel est
  /// terminé ou interdit, inutile d'insister.
  final bool retryable;

  @override
  String toString() => message;
}
