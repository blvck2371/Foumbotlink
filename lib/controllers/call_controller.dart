// L'API CallKit de LiveKit (mode audio « système d'appel externe »,
// disponibilité du moteur audio) est marquée expérimentale : c'est pourtant
// la voie documentée par LiveKit pour CallKit. À revérifier à chaque montée
// de version de livekit_client (testé avec 2.14.0).
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/call.dart';
import '../models/user_profile.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/callkit_helper.dart';
import '../services/chat_service.dart';

/// Une vignette d'appel de groupe : quelqu'un dans la salle, ou un invité
/// dont le téléphone sonne encore.
class CallTile {
  const CallTile({
    required this.uid,
    required this.name,
    this.video,
    this.cameraOff = true,
    this.speaking = false,
    this.ringing = false,
  });

  final String uid;
  final String name;
  final VideoTrack? video;
  final bool cameraOff;
  final bool speaking;

  /// Invité pas encore là : son téléphone sonne.
  final bool ringing;
}

/// Quelqu'un qu'on peut ajouter à l'appel.
class InviteCandidate {
  const InviteCandidate({required this.uid, required this.name, this.photoUrl});
  final String uid;
  final String name;
  final String? photoUrl;
}

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

/// Pilote un appel de bout en bout.
///
/// Deux canaux, chacun dans son rôle :
///  - le document Firestore `calls/{callId}` porte la **sonnerie** : qui
///    appelle, décroché, refusé, raccroché (et déclenche les pushes) ;
///  - la salle LiveKit `call_{callId}` porte la **voix et l'image**. Chaque
///    téléphone y envoie son micro (et sa caméra) et reçoit ceux de l'autre.
///    LiveKit relaie le flux par ses serveurs : plus de connexion directe
///    entre les deux téléphones à établir, donc plus d'appel muet quand l'un
///    des deux est derrière le NAT d'un opérateur mobile.
///
/// L'appelant entre dans la salle dès la sonnerie, l'appelé en décrochant :
/// la voix passe dès que le second arrive.
class CallController extends GetxController {
  static const _ringTimeout = Duration(seconds: 45);

  /// Délai de grâce avant d'abandonner une communication déjà établie mais
  /// dont le média s'est coupé. Assez long pour absorber un passage sous un
  /// tunnel ou une bascule Wi-Fi → 4G, assez court pour ne pas laisser
  /// l'utilisateur parler dans le vide.
  static const _reconnectGrace = Duration(seconds: 30);

  /// Si iOS ne signale pas l'activation de la session audio CallKit dans ce
  /// délai (évènement perdu), on démarre quand même le son : mieux vaut un
  /// appel qui marche qu'un appel muet.
  static const _callkitAudioFallback = Duration(seconds: 3);

  /// Décroché, mais la voix ne passe toujours pas : au-delà, on abandonne
  /// plutôt que de laisser « Connexion… » à l'écran indéfiniment.
  static const _connectTimeout = Duration(seconds: 25);

  /// Retours dans la salle tentés après une coupure franche.
  static const _maxRecoverAttempts = 10;

  /// Appel de groupe : seul dans la salle depuis tout ce temps (les autres
  /// sont partis, l'invité ne répond pas), on raccroche.
  static const _aloneTimeout = Duration(seconds: 50);

  final call = Rxn<Call>();
  final otherProfile = Rxn<UserProfile>();
  final phase = CallScreenPhase.connecting.obs;
  final isMuted = false.obs;
  final isCameraOff = false.obs;
  final isSpeakerOn = true.obs;
  final isFrontCamera = true.obs;
  final elapsedSeconds = 0.obs;
  final errorMessage = RxnString();

  /// Caméra de ce téléphone (appel vidéo), pour l'aperçu en vignette.
  final localVideo = Rxn<LocalVideoTrack>();

  /// Caméra de l'autre, ou `null` tant qu'elle n'est pas reçue.
  final remoteVideo = Rxn<VideoTrack>();

  /// L'autre a coupé sa caméra.
  final remoteCameraOff = false.obs;

  /// Appel de groupe : une vignette par personne (présente ou qui sonne).
  final tiles = <CallTile>[].obs;

  /// Une invitation est en cours d'envoi.
  final inviting = false.obs;

  late final bool _incoming;
  late final CallType _type;
  late final String _otherUid;
  String _callId = '';
  String _conversationId = '';

  /// L'utilisateur a déjà appuyé sur « Répondre » — dans l'UI d'appel native
  /// (CallKit), avant même que cet écran n'existe. Sans ce drapeau il devait
  /// décrocher une seconde fois une fois l'écran ouvert.
  bool _autoAccept = false;

  Room? _room;
  EventsListener<RoomEvent>? _roomEvents;
  StreamSubscription<Call?>? _callSub;
  Timer? _ringTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  Timer? _callkitAudioTimer;
  Timer? _connectTimer;
  Timer? _aloneTimer;
  bool _closing = false;
  bool _accepting = false;
  bool _recovering = false;

  /// Côté appelé ou invité : ce téléphone a décroché.
  bool _answeredByMe = false;

  /// Le son passe par la session audio CallKit (iOS, appel décroché depuis
  /// l'UI native) : LiveKit ne doit pas l'activer lui-même.
  bool _callkitAudio = false;

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

  /// L'appel est passé en groupe (quelqu'un a été ajouté).
  bool get isGroup => call.value?.isGroup ?? false;

  /// On peut ajouter quelqu'un : communication établie, appel en cours, et
  /// encore de la place.
  bool get canInvite {
    final c = call.value;
    if (c == null || c.status != CallStatus.accepted) return false;
    if (phase.value != CallScreenPhase.active) return false;
    if (!c.isGroup) return true;
    return c.activeMembers.length < Call.maxMembers;
  }

  /// Invité dans un appel de groupe (et non appelant ou appelé d'origine).
  bool get _isInvitee =>
      _incoming && call.value?.members[myUid]?.invitedBy != null;

  /// Identifiant du document d'appel piloté par cet écran. Permet aux
  /// évènements de l'UI d'appel native (relayés par PushService) de vérifier
  /// qu'ils concernent bien **cet** appel avant d'agir dessus.
  String get callId => _callId;

  /// Le média a été établi au moins une fois — donc le chrono a du sens.
  bool get wasEverConnected => _connectedAt != null;

  /// Vrai dès que l'appel a été décroché — y compris pendant une
  /// reconnexion. Détermine si une fin d'appel est un « appel terminé » ou
  /// un « appel manqué/refusé ».
  bool get _wasAnswered =>
      _connectedAt != null ||
      (_incoming ? _answeredByMe : call.value?.answeredAt != null);

  /// Quelqu'un d'autre est dans la salle.
  bool get _anyonePresent => _room?.remoteParticipants.isNotEmpty ?? false;

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
    if (isVideoCall) {
      unawaited(WakelockPlus.enable().catchError((Object _) {}));
    }

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
        _startIncomingRingTimeout();
      }
    } else {
      _startOutgoingCall();
    }
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
      if (_callId.isNotEmpty) _calls.leave(_callId, _terminalStatus);
    }
    _teardown();
    _phaseWorker?.dispose();
    _stopRinging();
    _ringPlayer.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
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
    if (_closing) return;
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
      if (_closing) {
        // Raccroché pendant la création du document.
        unawaited(_calls.updateStatus(_callId, CallStatus.missed));
        return;
      }
      _watchCallDoc();
      _startRingTimeout();

      // L'appelant entre dans la salle pendant que ça sonne : quand l'autre
      // décroche, il n'y a plus qu'à l'attendre, la voix passe aussitôt.
      await _joinRoom();
    } on Exception catch (e) {
      // Message affiché tel quel (pas juste loggé) : sur un téléphone
      // physique de test, personne n'a le câble + la console ouverts en
      // permanence — sans ça, une panne reste impossible à diagnostiquer.
      _failAndEnd('Impossible de démarrer l’appel : ${_describe(e)}');
    }
  }

  /// Invitation à un appel de groupe qui sonne dans l'app : personne d'autre
  /// ne la fera expirer (dans un appel à deux, c'est l'appelant qui marque
  /// l'appel manqué).
  void _startIncomingRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () {
      if (_closing || phase.value != CallScreenPhase.ringingIncoming) return;
      if (!isGroup) return;
      _closing = true;
      unawaited(_calls.leave(_callId, CallStatus.missed));
      _teardown();
      phase.value = CallScreenPhase.ended;
      if (Get.currentRoute == AppRoutes.call) Get.back();
    });
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
    // Garde-fou anti double-tap : un second appui lancerait une seconde
    // connexion à la salle en parallèle.
    if (_accepting || _closing) return;
    _accepting = true;
    // Coupe sonnerie et vibreur dès le tap, sans attendre la connexion (qui
    // peut prendre une seconde ou deux, voire afficher une demande de
    // permission) — sinon le téléphone continue de sonner dans la main de
    // quelqu'un qui a déjà décroché.
    phase.value = CallScreenPhase.connecting;

    final granted = await _ensurePermissions();
    if (_closing) return;
    if (!granted) {
      errorMessage.value =
          'Autorisez le micro${isVideoCall ? ' et la caméra' : ''} pour répondre.';
      _accepting = false;
      return;
    }

    try {
      // Décroché depuis l'UI native iOS : CallKit a la main sur la session
      // audio, LiveKit doit s'y plier.
      if (_autoAccept && Platform.isIOS) await _useCallkitAudio();

      await _joinRoom();
      if (_closing) return;
      // Invité d'un appel de groupe : on ne touche qu'à sa propre ligne.
      // Appelé d'un appel à deux : le décroché fait passer l'appel en cours.
      final current = call.value ?? await _calls.watchCall(_callId).first;
      if (current != null &&
          current.isGroup &&
          current.members.containsKey(myUid)) {
        await _calls.markJoined(_callId);
      } else {
        await _calls.markAccepted(_callId);
      }
      _answeredByMe = true;
      // L'UI CallKit entrante passe en état « connecté » (iOS surtout).
      await markCallkitConnected(_callId);
      // L'appelant est en général déjà dans la salle : la communication
      // démarre tout de suite. Sinon, `ParticipantConnectedEvent` s'en
      // chargera à son arrivée.
      if (_anyonePresent) _markConnected();
    } on Exception catch (e) {
      _accepting = false;
      _failAndEnd(
        'Impossible de répondre à l’appel : ${_describe(e)}',
        status: CallStatus.declined,
      );
    }
  }

  Future<void> declineCall() async {
    // Le statut mis à jour ci-dessous peut revenir de manière optimiste
    // via [_watchCallDoc] avant même la fin de cet appel réseau — le
    // garde-fou [_closing] évite un double `_teardown`/`Get.back()`.
    if (_closing) return;
    _closing = true;
    await _calls.leave(_callId, CallStatus.declined);
    _teardown();
    phase.value = CallScreenPhase.ended;
    Get.back();
  }

  // ---------------------------------------------------------------------
  // Salle LiveKit
  // ---------------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.microphone,
      if (isVideoCall) Permission.camera,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Entre dans la salle de l'appel et y publie micro (et caméra).
  Future<void> _joinRoom() async {
    final ticket = await _calls.joinRoom(_callId);
    if (_closing) return;

    if (isVideoCall && localVideo.value == null) {
      localVideo.value = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          cameraPosition: isFrontCamera.value
              ? CameraPosition.front
              : CameraPosition.back,
          params: VideoParametersPresets.h540_169,
        ),
      );
    }

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // La caméra est gérée ici (vignette d'aperçu) : elle ne doit pas
        // s'éteindre si la salle se reconnecte.
        stopLocalTrackOnUnpublish: false,
      ),
    );
    _room = room;
    _listenRoom(room);

    await AudioManager.instance.setSpeakerOutputPreferred(isSpeakerOn.value);
    await room.connect(ticket.url, ticket.token);
    if (_closing || _room != room) return;

    final local = room.localParticipant;
    await local?.setMicrophoneEnabled(!isMuted.value);
    final cam = localVideo.value;
    if (cam != null) {
      await local?.publishVideoTrack(cam);
      if (isCameraOff.value) await cam.mute(stopOnMute: false);
    }
    _syncRemoteTracks(room);
  }

  void _listenRoom(Room room) {
    _roomEvents = room.createListener()
      // Vignettes du groupe : recalculées à chaque évènement de la salle
      // (arrivée, départ, caméra, qui parle…).
      ..listen((_) => _refreshTiles())
      ..on<ParticipantConnectedEvent>((e) {
        developer.log(
          'participant arrivé: ${e.participant.identity}',
          name: 'CallController',
        );
        _aloneTimer?.cancel();
        _aloneTimer = null;
        if (_canBeActive) _markConnected();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        developer.log(
          'participant parti: ${e.participant.identity}',
          name: 'CallController',
        );
        if (e.participant.identity == _otherUid) remoteVideo.value = null;
        if (isGroup) {
          // Les autres continuent ; seul, on attend un peu qu'un invité
          // arrive avant de raccrocher.
          if (!_anyonePresent) _startAloneTimeout();
          return;
        }
        // L'autre a perdu le réseau — ou vient de raccrocher, auquel cas
        // le statut Firestore « ended » fermera l'écran dans un instant.
        _onMediaLost();
      })
      ..on<TrackSubscribedEvent>((e) {
        if (_canBeActive) _markConnected();
        if (e.participant.identity != _otherUid) return;
        final track = e.track;
        if (track is VideoTrack) {
          remoteVideo.value = track;
          remoteCameraOff.value = e.publication.muted;
        }
      })
      ..on<TrackUnsubscribedEvent>((e) {
        if (e.participant.identity != _otherUid) return;
        if (e.track is VideoTrack) remoteVideo.value = null;
      })
      ..on<TrackMutedEvent>((e) {
        if (e.participant.identity == _otherUid &&
            e.publication.kind == TrackType.VIDEO) {
          remoteCameraOff.value = true;
        }
      })
      ..on<TrackUnmutedEvent>((e) {
        if (e.participant.identity == _otherUid &&
            e.publication.kind == TrackType.VIDEO) {
          remoteCameraOff.value = false;
        }
      })
      ..on<RoomReconnectingEvent>((_) {
        developer.log('salle: reconnexion…', name: 'CallController');
        _onMediaLost();
      })
      ..on<RoomReconnectedEvent>((_) {
        developer.log('salle: reconnectée', name: 'CallController');
        if (_anyonePresent && _canBeActive) _markConnected();
      })
      ..on<RoomDisconnectedEvent>((e) {
        developer.log('salle: déconnectée (${e.reason})', name: 'CallController');
        if (_closing || _room != room) return;
        switch (e.reason) {
          case DisconnectReason.roomDeleted:
          case DisconnectReason.participantRemoved:
          case DisconnectReason.duplicateIdentity:
            // Le serveur a fermé la salle (appel terminé) ou ce compte a
            // répondu sur un autre téléphone : cet écran n'a plus d'objet.
            endCall();
          default:
            unawaited(_recover());
        }
      });
  }

  /// Une communication ne devient « active » qu'une fois décrochée : côté
  /// appelant, l'appelé arrive dans la salle juste avant d'écrire
  /// `accepted`, mais il est bien là.
  bool get _canBeActive => _incoming ? _accepting || _wasAnswered : true;

  /// Vignettes de l'appel de groupe : chaque personne dans la salle, puis
  /// les invités dont le téléphone sonne encore.
  void _refreshTiles() {
    final c = call.value;
    if (c == null || !c.isGroup) {
      if (tiles.isNotEmpty) tiles.clear();
      return;
    }
    final list = <CallTile>[];
    final present = <String>{};
    for (final p in _room?.remoteParticipants.values ?? <RemoteParticipant>[]) {
      present.add(p.identity);
      RemoteTrackPublication? cam;
      for (final pub in p.videoTrackPublications) {
        if (pub.track != null) cam = pub;
      }
      list.add(
        CallTile(
          uid: p.identity,
          name: c.members[p.identity]?.name ??
              (p.name.isNotEmpty ? p.name : 'Habitant'),
          video: switch (cam?.track) {
            final VideoTrack t => t,
            _ => null,
          },
          cameraOff: cam == null || cam.muted,
          speaking: p.isSpeaking,
        ),
      );
    }
    for (final m in c.members.values) {
      if (m.state == CallMemberState.ringing &&
          m.uid != myUid &&
          !present.contains(m.uid)) {
        list.add(CallTile(uid: m.uid, name: m.name, ringing: true));
      }
    }
    tiles.assignAll(list);
  }

  void _startAloneTimeout() {
    if (_closing || _aloneTimer != null || !_wasAnswered) return;
    _aloneTimer = Timer(_aloneTimeout, () {
      if (_closing || _anyonePresent) return;
      errorMessage.value = 'Plus personne dans l’appel.';
      endCall();
    });
  }

  /// Reprend la caméra de l'autre s'il était déjà dans la salle.
  void _syncRemoteTracks(Room room) {
    final other = room.remoteParticipants[_otherUid];
    if (other == null) return;
    for (final pub in other.videoTrackPublications) {
      final track = pub.track;
      if (track != null) {
        remoteVideo.value = track;
        remoteCameraOff.value = pub.muted;
      }
    }
  }

  /// La salle a lâché pour de bon (réseau coupé plus longtemps que ce que
  /// LiveKit rattrape seul) : on y retourne avec un jeton neuf, tant que
  /// le délai de grâce n'est pas écoulé.
  Future<void> _recover() async {
    if (_closing || _recovering) return;
    _recovering = true;
    _onMediaLost();
    try {
      await _disposeRoom();
      // Une tentative toutes les 3 s pendant le délai de grâce.
      for (var attempt = 0; attempt < _maxRecoverAttempts; attempt++) {
        if (_closing) return;
        try {
          await _joinRoom();
          if (_anyonePresent && _canBeActive) _markConnected();
          return;
        } on CallException catch (e) {
          if (!e.retryable) {
            // Appel terminé entre-temps : inutile d'insister.
            _failAndEnd(e.message);
            return;
          }
        } on Object catch (e) {
          developer.log('reprise échouée', name: 'CallController', error: e);
        }
        await _disposeRoom();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      _failAndEnd('Connexion perdue.');
    } finally {
      _recovering = false;
    }
  }

  // ---------------------------------------------------------------------
  // CallKit (iOS)
  // ---------------------------------------------------------------------

  /// CallKit active lui-même la session audio de l'appel (`didActivate`) :
  /// si LiveKit l'activait de son côté, iOS pouvait couper le son dès le
  /// décroché depuis l'écran verrouillé. LiveKit passe donc en mode
  /// « système d'appel externe » et son moteur audio ne tourne que pendant
  /// que la session CallKit est active.
  Future<void> _useCallkitAudio() async {
    _callkitAudio = true;
    try {
      await AudioManager.instance.setAudioSessionManagementMode(
        AudioSessionManagementMode.externalCallSystem,
      );
      callkitAudioActive.addListener(_onCallkitAudioChanged);
      await _applyCallkitAudio();
      if (!callkitAudioActive.value) {
        _callkitAudioTimer = Timer(_callkitAudioFallback, () {
          if (_closing || callkitAudioActive.value) return;
          developer.log(
            'session CallKit non signalée : son démarré quand même',
            name: 'CallController',
          );
          unawaited(
            AudioManager.instance
                .setEngineAvailability(
                  AudioEngineAvailability.defaultAvailability,
                )
                .catchError((Object _) {}),
          );
        });
      }
    } on Object catch (e) {
      developer.log('mode audio CallKit', name: 'CallController', error: e);
    }
  }

  void _onCallkitAudioChanged() {
    _callkitAudioTimer?.cancel();
    unawaited(_applyCallkitAudio());
  }

  Future<void> _applyCallkitAudio() async {
    try {
      await AudioManager.instance.setEngineAvailability(
        callkitAudioActive.value
            ? AudioEngineAvailability.defaultAvailability
            : AudioEngineAvailability.none,
      );
    } on Object catch (e) {
      developer.log('moteur audio', name: 'CallController', error: e);
    }
  }

  /// Rend la main à LiveKit sur la session audio (les lives en ont besoin).
  void _releaseCallkitAudio() {
    if (!_callkitAudio) return;
    _callkitAudio = false;
    _callkitAudioTimer?.cancel();
    callkitAudioActive.removeListener(_onCallkitAudioChanged);
    unawaited(
      Future<void>(() async {
        await AudioManager.instance.setEngineAvailability(
          AudioEngineAvailability.defaultAvailability,
        );
        await AudioManager.instance.setAudioSessionManagementMode(
          AudioSessionManagementMode.automatic,
        );
      }).catchError((Object _) {}),
    );
  }

  // ---------------------------------------------------------------------
  // État de la communication
  // ---------------------------------------------------------------------

  /// L'autre est dans la salle : on bascule l'UI en « actif ».
  void _markConnected() {
    if (_closing) return;
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final wasActive = phase.value == CallScreenPhase.active;
    // Référence du chrono figée à la première connexion : une reconnexion
    // ne remet pas la durée à zéro (WhatsApp continue de compter pendant la
    // coupure).
    _connectedAt ??=
        (_isInvitee ? null : call.value?.answeredAt) ?? DateTime.now();
    phase.value = CallScreenPhase.active;
    errorMessage.value = null;
    if (wasActive) return;

    _startDurationTimer();
    if (_incoming) unawaited(markCallkitConnected(_callId));
  }

  /// Le média s'est interrompu. Tant que le délai de grâce [_reconnectGrace]
  /// n'est pas écoulé on garde l'appel ouvert : LiveKit se reconnecte seul,
  /// ou [_recover] repart avec un jeton neuf. C'est ce qui évite qu'un
  /// simple changement de réseau raccroche brutalement.
  void _onMediaLost() {
    if (_closing) return;
    // Rien à sauver tant que la communication n'a jamais été établie : la
    // sonnerie a son propre délai d'expiration ([_startRingTimeout]).
    if (!_wasAnswered) return;

    if (phase.value != CallScreenPhase.reconnecting) {
      phase.value = CallScreenPhase.reconnecting;
    }
    _reconnectTimer ??= Timer(_reconnectGrace, () {
      if (_closing || phase.value == CallScreenPhase.active) return;
      errorMessage.value = 'Connexion perdue.';
      endCall();
    });
  }

  void _watchCallDoc() {
    _callSub?.cancel();
    _callSub = _calls.watchCall(_callId).listen((c) {
      if (c == null || _closing) return;
      call.value = c;

      // La sonnerie a été décrochée : le délai d'expiration « appel manqué »
      // n'a plus lieu d'être.
      if (c.status != CallStatus.ringing) _ringTimer?.cancel();

      // Côté appelant : le décroché arrive parfois après l'entrée de
      // l'appelé dans la salle.
      _refreshTiles();

      if (c.status == CallStatus.accepted && (!_incoming || _answeredByMe)) {
        if (_anyonePresent) {
          _markConnected();
        } else if (c.isGroup) {
          _startAloneTimeout();
        } else {
          _startConnectTimeout();
        }
      }

      // Invitation refusée ou expirée depuis un autre appareil (ou l'UI
      // native) : cet écran qui sonne n'a plus lieu d'être.
      final me = c.members[myUid];
      if (c.isGroup &&
          me != null &&
          !me.isActive &&
          phase.value == CallScreenPhase.ringingIncoming) {
        _closing = true;
        _teardown();
        phase.value = CallScreenPhase.ended;
        if (Get.currentRoute == AppRoutes.call) Get.back();
        return;
      }

      if (c.status == CallStatus.declined ||
          c.status == CallStatus.ended ||
          c.status == CallStatus.missed ||
          c.status == CallStatus.busy) {
        _closing = true;
        _teardown();
        phase.value = CallScreenPhase.ended;
        if (Get.currentRoute == AppRoutes.call) Get.back();
      }
    });
  }

  void _startConnectTimeout() {
    if (_connectedAt != null || _connectTimer != null) return;
    _connectTimer = Timer(_connectTimeout, () {
      if (_closing || _connectedAt != null) return;
      _failAndEnd(
        'La communication n’a pas pu s’établir. Vérifiez votre connexion '
        'et rappelez.',
      );
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

  // ---------------------------------------------------------------------
  // Commandes
  // ---------------------------------------------------------------------

  Future<void> toggleMute() async {
    final muted = !isMuted.value;
    isMuted.value = muted;
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    } on Object catch (_) {
      isMuted.value = !muted;
    }
  }

  Future<void> toggleCamera() async {
    final off = !isCameraOff.value;
    isCameraOff.value = off;
    final cam = localVideo.value;
    if (cam == null) return;
    try {
      if (off) {
        await cam.mute(stopOnMute: false);
      } else {
        await cam.unmute(stopOnMute: false);
      }
    } on Object catch (_) {
      isCameraOff.value = !off;
    }
  }

  Future<void> toggleSpeaker() async {
    final on = !isSpeakerOn.value;
    isSpeakerOn.value = on;
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(on);
    } on Object catch (_) {
      isSpeakerOn.value = !on;
    }
  }

  Future<void> switchCamera() async {
    final cam = localVideo.value;
    if (cam == null) return;
    final toFront = !isFrontCamera.value;
    try {
      await cam.setCameraPosition(
        toFront ? CameraPosition.front : CameraPosition.back,
      );
      isFrontCamera.value = toFront;
    } on Object catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Appel de groupe
  // ---------------------------------------------------------------------

  /// Personnes qu'on peut ajouter : celles de nos conversations récentes,
  /// hors membres déjà présents ou qui sonnent.
  Future<List<InviteCandidate>> inviteCandidates() async {
    final c = call.value;
    // Appel à deux : l'appelant et l'appelé sont là par définition. En
    // groupe, ceux qui sont partis peuvent être rappelés.
    final taken = <String>{
      myUid,
      if (c != null && c.isGroup)
        ...c.activeMembers.map((m) => m.uid)
      else if (c != null) ...[c.callerUid, c.calleeUid],
    };
    final conversations = await Get.find<ChatService>().recentConversations(
      myUid,
      limit: 40,
    );
    final uids = <String>[];
    for (final conv in conversations) {
      final other = conv.otherUid(myUid);
      if (other.isNotEmpty && !taken.contains(other) && !uids.contains(other)) {
        uids.add(other);
      }
    }
    final users = FirebaseFirestore.instance.collection('users');
    final profiles = await Future.wait(
      uids.map((uid) async {
        try {
          final doc = await users.doc(uid).get();
          final data = doc.data();
          if (data == null) return null;
          final name = (data['displayName'] as String?)?.trim();
          final photo = data['photoUrl'] as String?;
          return InviteCandidate(
            uid: uid,
            name: name == null || name.isEmpty ? 'Habitant' : name,
            photoUrl: photo != null && photo.startsWith('http') ? photo : null,
          );
        } on FirebaseException catch (_) {
          return null;
        }
      }),
    );
    return profiles.whereType<InviteCandidate>().toList();
  }

  /// Fait sonner le téléphone de [candidate] ; s'il décroche, il rejoint
  /// l'appel.
  Future<void> invite(InviteCandidate candidate) async {
    if (inviting.value || !canInvite) return;
    inviting.value = true;
    try {
      final name = await _calls.invite(_callId, candidate.uid);
      Get.snackbar('Appel de groupe', 'On appelle $name…');
    } on CallException catch (e) {
      Get.snackbar('Impossible d’ajouter ${candidate.name}', e.message);
    } finally {
      inviting.value = false;
    }
  }

  Future<void> endCall() async {
    if (_closing) return;
    _closing = true;
    // `_callId` peut encore être vide si l'utilisateur raccroche pendant
    // la fenêtre d'attente de permission micro/caméra, avant même que
    // `createCall` ait eu le temps de créer le document Firestore.
    if (_callId.isNotEmpty) await _calls.leave(_callId, _terminalStatus);
    _teardown();
    phase.value = CallScreenPhase.ended;
    if (Get.currentRoute == AppRoutes.call) Get.back();
  }

  /// Panne pendant la mise en relation : message affiché, appel clos.
  void _failAndEnd(String message, {CallStatus? status}) {
    if (_closing) return;
    errorMessage.value = message;
    phase.value = CallScreenPhase.ended;
    _closing = true;
    if (_callId.isNotEmpty) {
      _calls.leave(_callId, status ?? _terminalStatus);
    }
    _teardown();
  }

  static String _describe(Object e) =>
      e is CallException ? e.message : e.toString();

  void _teardown() {
    _aloneTimer?.cancel();
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _callkitAudioTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _callSub?.cancel();
    unawaited(_disposeRoom());
    final cam = localVideo.value;
    localVideo.value = null;
    remoteVideo.value = null;
    unawaited(
      Future<void>(() async {
        await cam?.stop();
        await cam?.dispose();
      }).catchError((Object _) {}),
    );
    _releaseCallkitAudio();
    if (_callId.isNotEmpty) {
      _calls.clearActiveCall(_callId);
      // Point de passage unique de toutes les fins d'appel (raccroché,
      // refusé, distant terminé, erreur, fermeture d'écran) : on retire
      // aussi l'UI d'appel native si elle traîne encore.
      dismissCallkit(_callId);
    }
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;
    final events = _roomEvents;
    _roomEvents = null;
    await events?.dispose();
    if (room != null) {
      try {
        await room.disconnect();
        await room.dispose();
      } on Object catch (_) {}
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
