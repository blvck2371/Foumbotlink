import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

import '../models/call.dart';
import '../routes/app_routes.dart';
import 'auth_service.dart';
import 'callkit_helper.dart';

/// Signalisation WebRTC via Firestore : chaque appel est un document
/// `calls/{callId}` (offer/answer SDP + statut) accompagné de deux
/// sous-collections de candidats ICE. Le média (audio/vidéo) ne passe
/// jamais par Firestore — seul le "poignée de main" nécessaire à établir
/// la connexion pair-à-pair transite ici.
///
/// Enregistré comme service permanent : c'est ce qui permet de détecter
/// un appel entrant tant que l'app est ouverte (premier ou arrière-plan),
/// même si l'utilisateur n'est pas sur l'écran de discussion concerné.
class CallService extends GetxService {
  static const callerCandidates = 'callerCandidates';
  static const calleeCandidates = 'calleeCandidates';

  final _db = FirebaseFirestore.instance;

  /// Appel entrant détecté pour l'utilisateur courant, ou `null`. Piloté
  /// par [_watchIncoming], observé par un binding global pour ouvrir
  /// l'écran d'appel automatiquement.
  final incomingCall = Rxn<Call>();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingSub;
  String? _activeCallId;

  AuthService get _auth => Get.find<AuthService>();

  CollectionReference<Map<String, dynamic>> get _callsRef =>
      _db.collection('calls');

  CollectionReference<Map<String, dynamic>> _candidatesRef(
    String callId,
    String who,
  ) => _callsRef.doc(callId).collection(who);

  @override
  void onInit() {
    super.onInit();
    _auth.firebaseUser.listen((user) {
      if (user != null) {
        _watchIncoming(user.uid);
      } else {
        _incomingSub?.cancel();
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
        updateStatus(call.id, CallStatus.busy);
        return;
      }
      _presentIncoming(call);
    });
  }

  /// Lève l'écran d'appel entrant CallKit, en résolvant le nom de
  /// l'appelant pour l'affichage.
  Future<void> _presentIncoming(Call call) async {
    var callerName = 'Appel entrant';
    try {
      final doc = await _db.collection('users').doc(call.callerUid).get();
      final name = (doc.data()?['displayName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) callerName = name;
    } on FirebaseException catch (_) {}
    await showCallkitIncomingFromData({
      'callId': call.id,
      'callerUid': call.callerUid,
      'callerName': callerName,
      'callType': call.type.name,
      'conversationId': call.conversationId,
    });
  }

  void _watchIncoming(String myUid) {
    _incomingSub?.cancel();
    // Préchauffe les serveurs ICE : sans ça, l'aller-retour vers
    // getIceServers retarderait le décrochage du premier appel.
    unawaited(_iceServers());
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

  Future<void> setOffer(String callId, Map<String, dynamic> offer) {
    return _callsRef.doc(callId).update({'offer': offer});
  }

  Future<void> setAnswer(String callId, Map<String, dynamic> answer) {
    return _callsRef.doc(callId).update({
      'answer': answer,
      'status': CallStatus.accepted.name,
      // Horloge serveur : référence commune aux deux appareils pour la durée
      // affichée (voir Call.answeredAt).
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }

  /// Renégociation (ICE restart) : l'appelant réécrit son offer, l'appelé y
  /// répond. Le statut reste `accepted` — la communication n'est pas
  /// interrompue, seul le chemin réseau est reconstruit.
  Future<void> setRenegotiationOffer(
    String callId,
    Map<String, dynamic> offer,
  ) {
    return _callsRef.doc(callId).update({'offer': offer});
  }

  Future<void> setRenegotiationAnswer(
    String callId,
    Map<String, dynamic> answer,
  ) {
    return _callsRef.doc(callId).update({'answer': answer});
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

  Future<void> addCandidate(
    String callId,
    String who,
    Map<String, dynamic> candidate,
  ) {
    return _candidatesRef(callId, who).add(candidate);
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchCandidates(
    String callId,
    String who,
    void Function(Map<String, dynamic>) onCandidate,
  ) {
    return _candidatesRef(callId, who).snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          onCandidate(change.doc.data()!);
        }
      }
    });
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
  // Configuration WebRTC
  // ---------------------------------------------------------------------

  /// Serveurs STUN/TURN de secours, compilés dans l'app.
  ///
  /// ⚠️ `openrelay.metered.ca` est un service de démonstration public : il est
  /// régulièrement saturé ou hors service. Quand il ne répond pas, deux
  /// téléphones en 4G/5G (NAT opérateur symétrique) échangent bien
  /// offer/answer via Firestore mais **aucun flux audio ne s'établit** — ICE
  /// part en `failed` et l'appel se coupe juste après le décrochage.
  ///
  /// Ce n'est donc qu'un dernier recours : [rtcConfiguration] demande
  /// d'abord des identifiants TURN temporaires à la Cloud Function
  /// `getIceServers` (Cloudflare), puis lit `config/webrtc` dans Firestore,
  /// et seulement ensuite retombe sur cette liste.
  static const fallbackIceServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
      ],
    },
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turns:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  List<Map<String, dynamic>>? _cachedIceServers;

  /// Fin de validité de [_cachedIceServers]. Les identifiants TURN de
  /// `getIceServers` expirent : on les renouvelle une heure avant.
  DateTime? _cachedIceServersUntil;

  /// Configuration passée à `createPeerConnection`, serveurs ICE inclus.
  ///
  /// Format attendu dans `config/webrtc` (lisible par tout utilisateur
  /// authentifié, écrit seulement depuis la console — voir firestore.rules) :
  /// ```json
  /// { "iceServers": [
  ///     { "urls": ["stun:stun.l.google.com:19302"] },
  ///     { "urls": "turns:mon-turn.example:443?transport=tcp",
  ///       "username": "...", "credential": "..." }
  /// ] }
  /// ```
  Future<Map<String, dynamic>> rtcConfiguration() async {
    return {
      'iceServers': await _iceServers(),
      // Évite tout décalage Plan-B / Unified-Plan entre les deux pairs.
      'sdpSemantics': 'unified-plan',
      // Pré-collecte quelques candidats avant l'offre → connexion plus rapide.
      'iceCandidatePoolSize': 4,
    };
  }

  Future<List<Map<String, dynamic>>> _iceServers() async {
    final cached = _cachedIceServers;
    final until = _cachedIceServersUntil;
    if (cached != null && (until == null || DateTime.now().isBefore(until))) {
      return cached;
    }

    // 1. Identifiants TURN temporaires (Cloud Function → Cloudflare).
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable(
            'getIceServers',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
          )
          .call<Map<String, dynamic>>();
      final servers = _parseIceServers(response.data['iceServers']);
      if (servers.isNotEmpty) {
        final ttl = (response.data['ttlSeconds'] as num?)?.toInt() ?? 3600;
        _cachedIceServersUntil = DateTime.now().add(
          Duration(seconds: (ttl - 3600).clamp(60, ttl)),
        );
        developer.log(
          '${servers.length} serveur(s) ICE reçus de getIceServers',
          name: 'CallService',
        );
        return _cachedIceServers = servers;
      }
    } on Object catch (e) {
      // TURN pas encore configuré, réseau coupé… : on passe à la suite.
      developer.log(
        'getIceServers indisponible',
        name: 'CallService',
        error: e,
      );
    }

    // 2. Liste posée à la main dans `config/webrtc`, 3. liste compilée —
    // gardées en cache le temps de la session, sauf si la fonction répond
    // au prochain essai (on la retente au bout de 10 minutes).
    _cachedIceServersUntil = DateTime.now().add(const Duration(minutes: 10));
    try {
      final doc = await _db.collection('config').doc('webrtc').get();
      final servers = _parseIceServers(doc.data()?['iceServers']);
      if (servers.isNotEmpty) {
        developer.log(
          '${servers.length} serveur(s) ICE chargé(s) depuis config/webrtc',
          name: 'CallService',
        );
        return _cachedIceServers = servers;
      }
    } on Object catch (e) {
      // Un appel doit pouvoir démarrer même si Firestore est injoignable :
      // on retombe silencieusement sur la liste compilée.
      developer.log('config/webrtc illisible', name: 'CallService', error: e);
    }

    return _cachedIceServers = List<Map<String, dynamic>>.from(
      fallbackIceServers.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static List<Map<String, dynamic>> _parseIceServers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['urls'] != null)
        .toList();
  }

  @override
  void onClose() {
    _incomingSub?.cancel();
    super.onClose();
  }
}
