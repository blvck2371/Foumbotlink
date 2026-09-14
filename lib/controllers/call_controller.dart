import 'dart:async';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart' hide navigator;
import 'package:permission_handler/permission_handler.dart';

import '../models/call.dart';
import '../models/user_profile.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/callkit_helper.dart';

enum CallScreenPhase {
  connecting,
  ringingOutgoing,
  ringingIncoming,
  active,

  /// Communication établie puis coupée (perte de réseau, bascule
  /// Wi-Fi ↔ données…). L'appel n'est **pas** terminé : le chrono continue et
  /// on tente de rétablir le média, comme WhatsApp qui affiche
  /// « Reconnexion… » plutôt que de raccrocher.
  reconnecting,
  ended,
}

/// Pilote un appel WebRTC de bout en bout : création/écoute du document de
/// signalisation Firestore, échange offer/answer + candidats ICE, gestion
/// du flux média local/distant, et état d'UI (muet, caméra, haut-parleur,
/// durée).
///
/// Les serveurs ICE ne sont **pas** codés en dur ici : ils viennent de
/// [CallService.rtcConfiguration], qui les lit dans `config/webrtc`
/// (Firestore) avec repli sur une liste compilée. Sans TURN opérationnel,
/// deux téléphones derrière un NAT symétrique (très courant en 4G/5G
/// opérateur) échangent bien la signalisation mais n'établissent jamais le
/// flux audio — voir le commentaire de `CallService.fallbackIceServers`.
class CallController extends GetxController {
  static const _ringTimeout = Duration(seconds: 45);

  /// Délai de grâce avant d'abandonner une communication déjà établie mais
  /// dont le média s'est coupé. Assez long pour absorber un passage sous un
  /// tunnel ou une bascule Wi-Fi → 4G, assez court pour ne pas laisser
  /// l'utilisateur parler dans le vide.
  static const _reconnectGrace = Duration(seconds: 30);

  /// Au-delà, le réseau est manifestement inutilisable : inutile de
  /// reconstruire une n-ième fois le chemin ICE.
  static const _maxIceRestarts = 3;

  final call = Rxn<Call>();
  final otherProfile = Rxn<UserProfile>();
  final phase = CallScreenPhase.connecting.obs;
  final isMuted = false.obs;
  final isCameraOff = false.obs;
  final isSpeakerOn = true.obs;
  final isFrontCamera = true.obs;
  final elapsedSeconds = 0.obs;
  final errorMessage = RxnString();

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  late final bool _incoming;
  late final CallType _type;
  late final String _otherUid;
  String _callId = '';
  String _conversationId = '';

  /// L'utilisateur a déjà appuyé sur « Répondre » — dans l'UI d'appel native
  /// (CallKit), avant même que cet écran n'existe. Sans ce drapeau il devait
  /// décrocher une seconde fois une fois l'écran ouvert.
  bool _autoAccept = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<Call?>? _callSub;
  StreamSubscription? _remoteCandidatesSub;
  Timer? _ringTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  bool _remoteDescriptionSet = false;
  final _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _closing = false;
  bool _accepting = false;

  /// SDP distant actuellement appliqué. Sert à distinguer une renégociation
  /// (ICE restart : nouveau SDP) d'une simple re-notification Firestore du
  /// même document — sans quoi chaque snapshot rejouerait
  /// `setRemoteDescription` et casserait la session.
  String? _appliedRemoteSdp;
  bool _renegotiating = false;
  int _iceRestarts = 0;

  /// Début de la communication, référence du chrono. Volontairement issu de
  /// `Call.answeredAt` (horloge serveur) quand il est disponible, pour que
  /// les deux téléphones affichent la même durée.
  DateTime? _connectedAt;

  // Tonalité entendue pendant la sonnerie — côté appelant (tonalité de
  // retour) comme côté appelé (sonnerie + vibreur) quand l'app est déjà au
  // premier plan et qu'aucune UI CallKit ne sonne à sa place.
  final _ringPlayer = AudioPlayer();
  Timer? _hapticTimer;
  Worker? _phaseWorker;

  AuthService get _auth => Get.find<AuthService>();
  CallService get _calls => Get.find<CallService>();

  String get myUid => _auth.uid;
  bool get isVideoCall => _type == CallType.video;

  /// Identifiant du document de signalisation piloté par cet écran. Permet
  /// aux évènements de l'UI d'appel native (relayés par PushService) de
  /// vérifier qu'ils concernent bien **cet** appel avant d'agir dessus.
  String get callId => _callId;

  /// Le média a été établi au moins une fois — donc le chrono a du sens.
  /// Distinct de [_wasAnswered] : on peut avoir décroché sans qu'aucun flux
  /// audio ne s'établisse jamais (TURN injoignable).
  bool get wasEverConnected => _connectedAt != null;

  /// Vrai dès que l'appel a été décroché — y compris pendant une
  /// reconnexion. Détermine si une fin d'appel est un « appel terminé » ou
  /// un « appel manqué/refusé ».
  bool get _wasAnswered =>
      _connectedAt != null || call.value?.answeredAt != null;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>;
    _incoming = args['incoming'] as bool? ?? false;
    _otherUid = args['otherUid'] as String;
    _type = args['type'] as CallType;
    _conversationId = args['conversationId'] as String? ?? '';
    _callId = args['callId'] as String? ?? '';
    _autoAccept = args['autoAccept'] as bool? ?? false;

    _phaseWorker = ever<CallScreenPhase>(phase, _onPhaseChanged);
    _loadOtherProfile();

    Future.wait([localRenderer.initialize(), remoteRenderer.initialize()]).then(
      (_) {
        if (_incoming) {
          _calls.markHandled(_callId);
          _watchCallDoc();
          if (_autoAccept) {
            // Décroché depuis CallKit : on enchaîne directement sur la
            // connexion, sans réafficher « Accepter / Refuser » ni faire
            // sonner le téléphone une deuxième fois.
            phase.value = CallScreenPhase.connecting;
            acceptCall();
          } else {
            phase.value = CallScreenPhase.ringingIncoming;
          }
        } else {
          _startOutgoingCall();
        }
      },
    );
  }

  void _onPhaseChanged(CallScreenPhase p) {
    switch (p) {
      case CallScreenPhase.ringingOutgoing:
        _startRingback();
      case CallScreenPhase.ringingIncoming:
        _startRingtone();
      case CallScreenPhase.connecting:
      case CallScreenPhase.active:
      case CallScreenPhase.reconnecting:
      case CallScreenPhase.ended:
        _stopRinging();
    }
  }

  Future<void> _startRingback() async {
    await _stopRinging();
    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(AssetSource('audio/ringback.wav'));
    } on Exception catch (_) {}
  }

  Future<void> _startRingtone() async {
    await _stopRinging();
    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(AssetSource('audio/ringtone.wav'));
    } on Exception catch (_) {}
    HapticFeedback.vibrate();
    _hapticTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => HapticFeedback.vibrate(),
    );
  }

  Future<void> _stopRinging() async {
    _hapticTimer?.cancel();
    _hapticTimer = null;
    try {
      await _ringPlayer.stop();
    } on Exception catch (_) {}
  }

  @override
  void onClose() {
    // Filet de sécurité : si l'écran se ferme sans être passé par
    // [endCall]/[declineCall] (retour système, navigation ailleurs...),
    // on marque quand même l'appel comme terminé côté Firestore — sinon
    // l'autre participant continuerait de le voir sonner/actif alors que
    // cet écran a disparu.
    if (!_closing) {
      _closing = true;
      if (_callId.isNotEmpty) _calls.updateStatus(_callId, _terminalStatus);
    }
    _teardown();
    _phaseWorker?.dispose();
    _stopRinging();
    _ringPlayer.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.onClose();
  }

  /// Statut à écrire quand cet appareil met fin à l'appel. Un appel décroché
  /// se termine toujours en `ended` — même s'il se coupe pendant une
  /// reconnexion, ce n'est ni un refus ni un appel manqué (et un `missed`
  /// déclencherait à tort une notification « Appel manqué »).
  CallStatus get _terminalStatus {
    if (_wasAnswered) return CallStatus.ended;
    return _incoming ? CallStatus.declined : CallStatus.missed;
  }

  Future<void> _loadOtherProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_otherUid)
          .get();
      if (doc.exists) {
        otherProfile.value = UserProfile.fromMap(doc.id, doc.data()!);
      }
    } on FirebaseException catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Appelant
  // ---------------------------------------------------------------------

  Future<void> _startOutgoingCall() async {
    phase.value = CallScreenPhase.ringingOutgoing;
    final granted = await _ensurePermissions();
    if (!granted) {
      errorMessage.value =
          'Autorisez le micro${isVideoCall ? ' et la caméra' : ''} pour appeler.';
      phase.value = CallScreenPhase.ended;
      return;
    }

    try {
      final created = await _calls.createCall(
        conversationId: _conversationId,
        callerUid: myUid,
        calleeUid: _otherUid,
        type: _type,
      );
      _callId = created.id;
      call.value = created;

      await _initLocalStream();
      await _createPeerConnection();

      _remoteCandidatesSub = _calls.watchCandidates(
        _callId,
        CallService.calleeCandidates,
        _onRemoteCandidate,
      );

      final offer = await _pc!.createOffer(
        isVideoCall
            ? {'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1}
            : {'offerToReceiveAudio': 1},
      );
      await _pc!.setLocalDescription(offer);
      await _calls.setOffer(_callId, {'sdp': offer.sdp, 'type': offer.type});

      _watchCallDoc();
      _startRingTimeout();
    } on Exception catch (e) {
      // Message technique affiché tel quel (pas juste loggé) : sur un
      // téléphone physique de test, personne n'a le câble + la console
      // ouverts en permanence — sans ça, une erreur Firestore/WebRTC reste
      // invisible et impossible à diagnostiquer à distance.
      errorMessage.value = 'Impossible de démarrer l’appel : $e';
      phase.value = CallScreenPhase.ended;
      _closing = true;
      if (_callId.isNotEmpty) _calls.updateStatus(_callId, CallStatus.ended);
      _teardown();
    }
  }

  void _startRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () {
      if (call.value?.status == CallStatus.ringing) {
        _calls.updateStatus(_callId, CallStatus.missed);
        endCall();
      }
    });
  }

  // ---------------------------------------------------------------------
  // Appelé
  // ---------------------------------------------------------------------

  Future<void> acceptCall() async {
    // Garde-fou anti double-tap : sans lui, un appui rapide et répété sur
    // "Accepter" lancerait deux fois `getUserMedia`/`createPeerConnection`
    // en parallèle, la seconde écrasant `_pc`/`_localStream` de la
    // première sans jamais la libérer.
    if (_accepting || _closing) return;
    _accepting = true;
    // Coupe sonnerie et vibreur dès le tap, sans attendre la fin de
    // `getUserMedia` (qui peut prendre une seconde ou deux, voire afficher
    // une demande de permission) — sinon le téléphone continue de sonner
    // dans la main de quelqu'un qui a déjà décroché.
    phase.value = CallScreenPhase.connecting;

    var current = call.value;
    if (current?.offer == null) {
      // L'offre SDP peut arriver quelques centaines de ms (voire plus, si
      // l'appelant doit d'abord autoriser micro/caméra) après que cet écran
      // s'est ouvert sur la notification d'appel entrant — on attend un
      // peu plutôt que d'ignorer silencieusement le tap sur "Accepter".
      try {
        current = await _calls
            .watchCall(_callId)
            .firstWhere((c) => c?.offer != null)
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        current = null;
      }
      if (_closing) return;
      if (current?.offer == null) {
        errorMessage.value = 'Cet appel n’est plus disponible.';
        _accepting = false;
        return;
      }
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      errorMessage.value =
          'Autorisez le micro${isVideoCall ? ' et la caméra' : ''} pour répondre.';
      _accepting = false;
      return;
    }

    try {
      await _initLocalStream();
      // Ordre imposé par l'Unified Plan côté répondeur : créer la
      // PeerConnection SANS nos pistes → appliquer l'offre distante →
      // ajouter nos pistes → répondre. Ajouter les pistes avant l'offre
      // peut créer des m-lines en double et casser l'audio bidirectionnel.
      await _createPeerConnection(withLocalTracks: false);

      final offer = current!.offer!;
      await _applyRemoteDescription(offer);
      await _addLocalTracks();
      await _flushPendingCandidates();

      _remoteCandidatesSub = _calls.watchCandidates(
        _callId,
        CallService.callerCandidates,
        _onRemoteCandidate,
      );

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _calls.setAnswer(_callId, {'sdp': answer.sdp, 'type': answer.type});
      // L'UI CallKit entrante passe en état « connecté » (iOS surtout).
      await markCallkitConnected(_callId);

      // Pas encore "active" : le SDP est échangé mais la connexion P2P
      // (ICE) n'est pas forcément établie. C'est `onConnectionState` (dans
      // [_createPeerConnection]) qui fera passer à `active` — de manière
      // symétrique avec le côté appelant — une fois le média réellement
      // connecté, pas seulement la signalisation terminée.
      phase.value = CallScreenPhase.connecting;
    } on Exception catch (e) {
      errorMessage.value = 'Impossible de répondre à l’appel : $e';
      _accepting = false;
      _closing = true;
      if (_callId.isNotEmpty) _calls.updateStatus(_callId, CallStatus.declined);
      _teardown();
      phase.value = CallScreenPhase.ended;
    }
  }

  Future<void> declineCall() async {
    // Le statut mis à jour ci-dessous peut revenir de manière optimiste
    // via [_watchCallDoc] avant même la fin de cet appel réseau — le
    // garde-fou [_closing] évite un double `_teardown`/`Get.back()`.
    if (_closing) return;
    _closing = true;
    await _calls.updateStatus(_callId, CallStatus.declined);
    _teardown();
    phase.value = CallScreenPhase.ended;
    Get.back();
  }

  // ---------------------------------------------------------------------
  // Commun
  // ---------------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.microphone,
      if (isVideoCall) Permission.camera,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _initLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideoCall
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    _localStream = stream;
    localRenderer.srcObject = stream;
  }

  Future<void> _createPeerConnection({bool withLocalTracks = true}) async {
    final pc = await createPeerConnection(await _calls.rtcConfiguration());
    _pc = pc;

    if (withLocalTracks) await _addLocalTracks();

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _closing) return;
      _calls.addCandidate(
        _callId,
        _incoming ? CallService.calleeCandidates : CallService.callerCandidates,
        candidate.toMap(),
      );
    };

    // `onIceConnectionState` est plus fiable que `onConnectionState` sur
    // certaines builds Android de flutter_webrtc — on écoute les deux.
    pc.onIceConnectionState = (state) {
      developer.log('iceConnectionState: $state', name: 'CallController');
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _markConnected();
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          // État transitoire : très souvent résolu tout seul en quelques
          // secondes. On bascule l'UI en « Reconnexion… » sans toucher au
          // média ni tenter quoi que ce soit tout de suite.
          _onMediaLost(attemptRestart: false);
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _onMediaLost(attemptRestart: true);
        default:
          break;
      }
    };

    pc.onConnectionState = (state) {
      developer.log('connectionState: $state', name: 'CallController');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _markConnected();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _onMediaLost(attemptRestart: false);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _onMediaLost(attemptRestart: true);
        default:
          break;
      }
    };
  }

  Future<void> _addLocalTracks() async {
    final pc = _pc;
    final stream = _localStream;
    if (pc == null || stream == null) return;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  /// Média réellement connecté (ICE établi). On bascule l'UI en « actif » et
  /// on **force la route audio** : sans ça le son distant sort par défaut
  /// dans l'écouteur (volume très faible), ce qui donne l'impression que
  /// « personne ne s'entend ».
  void _markConnected() {
    if (_closing) return;
    _ringTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _iceRestarts = 0;

    final wasActive = phase.value == CallScreenPhase.active;
    // Référence du chrono figée à la première connexion : une reconnexion
    // ne remet pas la durée à zéro (WhatsApp continue de compter pendant la
    // coupure).
    _connectedAt ??= call.value?.answeredAt ?? DateTime.now();
    phase.value = CallScreenPhase.active;
    errorMessage.value = null;
    if (wasActive) return;

    _startDurationTimer();
    if (_incoming) unawaited(markCallkitConnected(_callId));
    unawaited(Helper.setSpeakerphoneOn(isSpeakerOn.value));
  }

  /// Le flux média s'est interrompu. Tant que le délai de grâce
  /// [_reconnectGrace] n'est pas écoulé on garde l'appel ouvert — et si le
  /// chemin ICE a franchement échoué, l'appelant en reconstruit un (ICE
  /// restart). C'est ce qui évite qu'un simple changement de réseau
  /// raccroche brutalement.
  void _onMediaLost({required bool attemptRestart}) {
    if (_closing) return;
    // Rien à sauver tant que la communication n'a jamais été établie : la
    // sonnerie a son propre délai d'expiration ([_startRingTimeout]).
    if (!_wasAnswered) {
      if (attemptRestart) {
        errorMessage.value =
            'Connexion audio impossible entre les deux appareils — réseau '
            'trop restrictif, un serveur TURN opérationnel est nécessaire.';
        endCall();
      }
      return;
    }

    if (phase.value != CallScreenPhase.reconnecting) {
      phase.value = CallScreenPhase.reconnecting;
    }

    _reconnectTimer ??= Timer(_reconnectGrace, () {
      if (_closing || phase.value == CallScreenPhase.active) return;
      // Un appel décroché dont le média ne s'est jamais établi n'est pas une
      // « connexion perdue » : c'est un TURN manquant ou injoignable, et le
      // diagnostic n'est pas le même.
      errorMessage.value = wasEverConnected
          ? 'Connexion perdue.'
          : 'Connexion audio impossible entre les deux appareils — réseau '
                'trop restrictif, un serveur TURN opérationnel est nécessaire.';
      endCall();
    });

    if (attemptRestart) unawaited(_restartIce());
  }

  /// Reconstruit le chemin ICE sans interrompre la session : l'appelant
  /// réémet une offre marquée `iceRestart`, l'appelé y répond
  /// (voir [_watchCallDoc]). Le statut Firestore reste `accepted`.
  Future<void> _restartIce() async {
    // Seul l'appelant réémet une offre : si les deux côtés renégociaient en
    // même temps, on tomberait en « glare » (collision d'offres) et la
    // session serait à refaire entièrement.
    if (_incoming || _closing || _renegotiating) return;
    if (_iceRestarts >= _maxIceRestarts) return;
    final pc = _pc;
    if (pc == null) return;

    _renegotiating = true;
    _iceRestarts++;
    try {
      developer.log('ICE restart #$_iceRestarts', name: 'CallController');
      final offer = await pc.createOffer({'iceRestart': true});
      await pc.setLocalDescription(offer);
      await _calls.setRenegotiationOffer(_callId, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } on Object catch (e) {
      developer.log('ICE restart échoué', name: 'CallController', error: e);
    } finally {
      _renegotiating = false;
    }
  }

  /// Côté appelé : l'appelant a réémis une offre (ICE restart). On y répond
  /// sur la PeerConnection existante — les pistes locales restent en place.
  Future<void> _answerRenegotiation(Map<String, dynamic> offer) async {
    if (_closing || _renegotiating) return;
    final pc = _pc;
    if (pc == null) return;

    _renegotiating = true;
    try {
      developer.log('réponse à un ICE restart', name: 'CallController');
      await _applyRemoteDescription(offer);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _calls.setRenegotiationAnswer(_callId, {
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } on Object catch (e) {
      developer.log('renégociation échouée', name: 'CallController', error: e);
    } finally {
      _renegotiating = false;
    }
  }

  Future<void> _applyRemoteDescription(Map<String, dynamic> description) async {
    final sdp = description['sdp'] as String?;
    if (sdp == null) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp, description['type'] as String),
    );
    _appliedRemoteSdp = sdp;
    _remoteDescriptionSet = true;
  }

  Future<void> _flushPendingCandidates() async {
    if (_pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await _pc?.addCandidate(candidate);
    }
  }

  void _onRemoteCandidate(Map<String, dynamic> data) {
    final candidate = RTCIceCandidate(
      data['candidate'] as String,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    if (_remoteDescriptionSet) {
      _pc?.addCandidate(candidate);
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  void _watchCallDoc() {
    _callSub?.cancel();
    _callSub = _calls.watchCall(_callId).listen((c) async {
      if (c == null || _closing) return;
      call.value = c;

      // La sonnerie a été décrochée : le délai d'expiration « appel manqué »
      // n'a plus lieu d'être, même si ICE met du temps à s'établir.
      if (c.status != CallStatus.ringing) _ringTimer?.cancel();

      if (_pc != null && !_closing) {
        if (_incoming) {
          // Appelé : une offre dont le SDP a changé après le décrochage est
          // une renégociation (ICE restart) initiée par l'appelant.
          final offer = c.offer;
          if (c.answeredAt != null &&
              offer != null &&
              offer['sdp'] != _appliedRemoteSdp) {
            await _answerRenegotiation(offer);
          }
        } else {
          // Appelant : applique l'answer, initiale comme renégociée.
          final answer = c.answer;
          if (answer != null && answer['sdp'] != _appliedRemoteSdp) {
            await _applyRemoteDescription(answer);
            await _flushPendingCandidates();
          }
        }
      }

      if (c.status == CallStatus.declined ||
          c.status == CallStatus.ended ||
          c.status == CallStatus.missed ||
          c.status == CallStatus.busy) {
        if (!_closing) {
          _closing = true;
          _teardown();
          phase.value = CallScreenPhase.ended;
          if (Get.currentRoute == AppRoutes.call) Get.back();
        }
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _tickDuration();
    // La durée est recalculée à partir de [_connectedAt] plutôt
    // qu'incrémentée : un timer Flutter est suspendu quand l'app passe en
    // arrière-plan, ce qui faisait « perdre » à l'affichage tout le temps
    // passé écran éteint pendant une conversation.
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickDuration(),
    );
  }

  void _tickDuration() {
    final start = _connectedAt;
    if (start == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    elapsedSeconds.value = seconds < 0 ? 0 : seconds;
  }

  void toggleMute() {
    isMuted.value = !isMuted.value;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      t.enabled = !isMuted.value;
    }
  }

  void toggleCamera() {
    isCameraOff.value = !isCameraOff.value;
    for (final t in _localStream?.getVideoTracks() ?? const []) {
      t.enabled = !isCameraOff.value;
    }
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn.value = !isSpeakerOn.value;
    await Helper.setSpeakerphoneOn(isSpeakerOn.value);
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    await Helper.switchCamera(track);
    isFrontCamera.value = !isFrontCamera.value;
  }

  Future<void> endCall() async {
    if (_closing) return;
    _closing = true;
    // `_callId` peut encore être vide si l'utilisateur raccroche pendant
    // la fenêtre d'attente de permission micro/caméra, avant même que
    // `createCall` ait eu le temps de créer le document Firestore.
    if (_callId.isNotEmpty) await _calls.updateStatus(_callId, _terminalStatus);
    _teardown();
    phase.value = CallScreenPhase.ended;
    Get.back();
  }

  void _teardown() {
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    _callSub?.cancel();
    _remoteCandidatesSub?.cancel();
    for (final t in _localStream?.getTracks() ?? const []) {
      t.stop();
    }
    _localStream?.dispose();
    _pc?.close();
    _pc = null;
    if (_callId.isNotEmpty) {
      _calls.clearActiveCall(_callId);
      // Point de passage unique de toutes les fins d'appel (raccroché,
      // refusé, distant terminé, erreur, fermeture d'écran) : on retire
      // aussi l'UI d'appel native si elle traîne encore.
      dismissCallkit(_callId);
    }
  }

  /// `m:ss` sous l'heure, `h:mm:ss` au-delà — comme les autres applications
  /// d'appel.
  String get formattedDuration {
    final total = elapsedSeconds.value;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h == 0) return '$m:$ss';
    return '$h:${m.toString().padLeft(2, '0')}:$ss';
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
