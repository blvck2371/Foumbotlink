import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/live_session.dart';
import '../services/auth_service.dart';
import '../services/live_service.dart';
import '../services/user_profile_service.dart';
import 'live_feed.dart';
import 'live_stage.dart';

enum LiveHostPhase {
  /// Autorisations et caméra en cours d'ouverture.
  preparing,

  /// Aperçu affiché, titre à saisir.
  ready,

  /// « Passer en direct » appuyé : salle en cours d'ouverture.
  starting,

  live,
  ending,

  /// Bilan affiché.
  ended,

  /// Caméra ou micro refusés, ou panne irrécupérable.
  failed,
}

/// Bilan montré à l'hôte à la fin.
class LiveSummary {
  const LiveSummary({
    required this.duration,
    required this.peakViewers,
    required this.likes,
    this.stoppedByServer = false,
  });
  final Duration duration;
  final int peakViewers;
  final int likes;

  /// Le live a été arrêté sans que l'hôte l'ait demandé (signalements,
  /// modération, connexion perdue trop longtemps).
  final bool stoppedByServer;
}

/// L'antenne : aperçu caméra, passage en direct, puis le live lui-même.
///
/// L'image part du téléphone vers LiveKit en un seul flux, décliné en
/// trois qualités (simulcast) : chaque spectateur reçoit celle que son
/// réseau supporte, sans que l'hôte n'envoie plus.
class LiveHostController extends GetxController {
  LiveService get _service => Get.find<LiveService>();

  final phase = LiveHostPhase.preparing.obs;
  final error = RxnString();

  /// Refus définitif d'une autorisation : il faut passer par les réglages.
  final needsSettings = false.obs;

  final titleCtrl = TextEditingController();
  final camera = Rxn<LocalVideoTrack>();
  final frontCamera = true.obs;
  final micOn = true.obs;
  final reconnecting = false.obs;
  final elapsed = Duration.zero.obs;
  final feed = Rxn<LiveFeed>();
  final summary = Rxn<LiveSummary>();

  /// Image et micro des invités sur le panel.
  final media = LiveStageMedia();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _clock;
  String? _liveId;
  DateTime? _startedAt;
  Worker? _endedWorker;
  int _peakSeen = 0;

  String? get liveId => _liveId;

  @override
  void onInit() {
    super.onInit();
    unawaited(WakelockPlus.enable().catchError((Object _) {}));
    unawaited(prepare());
  }

  /// Autorisations, puis aperçu de la caméra avant.
  Future<void> prepare() async {
    phase.value = LiveHostPhase.preparing;
    error.value = null;
    needsSettings.value = false;
    // Sur le web, le navigateur demande lui-même caméra et micro quand la
    // caméra s'ouvre ci-dessous.
    final statuses = kIsWeb
        ? const <Permission, PermissionStatus>{}
        : await [Permission.camera, Permission.microphone].request();
    if (!statuses.values.every((s) => s.isGranted)) {
      needsSettings.value = statuses.values.any((s) => s.isPermanentlyDenied);
      error.value =
          'Pour passer en direct, Foumbot Link a besoin de la caméra et du '
          'micro.';
      phase.value = LiveHostPhase.failed;
      return;
    }
    try {
      camera.value ??= await LocalVideoTrack.createCameraTrack(
        const CameraCaptureOptions(
          cameraPosition: CameraPosition.front,
          params: VideoParametersPresets.h720_169,
        ),
      );
      if (isClosed) return;
      phase.value = LiveHostPhase.ready;
    } catch (_) {
      error.value = 'La caméra n’a pas pu s’ouvrir.';
      phase.value = LiveHostPhase.failed;
    }
  }

  Future<void> switchCamera() async {
    final track = camera.value;
    if (track == null) return;
    final toFront = !frontCamera.value;
    try {
      await track.setCameraPosition(
        toFront ? CameraPosition.front : CameraPosition.back,
      );
      frontCamera.value = toFront;
    } catch (_) {}
  }

  Future<void> toggleMic() async {
    final next = !micOn.value;
    micOn.value = next;
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(next);
    } catch (_) {
      micOn.value = !next;
    }
  }

  /// « Passer en direct ».
  Future<void> goLive() async {
    final track = camera.value;
    if (track == null || phase.value != LiveHostPhase.ready) return;
    phase.value = LiveHostPhase.starting;
    error.value = null;
    try {
      final ticket = await _service.start(LiveRules.cleanTitle(titleCtrl.text));
      if (isClosed) {
        // Écran quitté pendant l'ouverture : pas de live sans hôte.
        unawaited(_service.end(ticket.liveId).catchError((Object _) {}));
        return;
      }
      _liveId = ticket.liveId;
      try {
        await _connect(ticket, track);
      } catch (e) {
        // Premier contact avec le serveur média raté (réseau mobile qui
        // hésite) : un second essai avant d'abandonner le live.
        debugPrint('Live : connexion LiveKit échouée ($e), nouvel essai');
        await _disposeRoom();
        if (isClosed) return;
        await _connect(ticket, track);
      }
      if (isClosed) return;

      final f = LiveFeed(liveId: ticket.liveId, me: _me(), isHost: true);
      feed.value = f;
      await f.start();
      _endedWorker = ever<bool>(f.ended, (gone) {
        if (gone && phase.value == LiveHostPhase.live) {
          unawaited(_finish(stoppedByServer: true));
        }
      });
      ever<LiveSession?>(f.live, (s) {
        if (s != null && s.viewers > _peakSeen) _peakSeen = s.viewers;
      });

      _startedAt = DateTime.now();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        final at = _startedAt;
        if (at != null) elapsed.value = DateTime.now().difference(at);
      });
      phase.value = LiveHostPhase.live;
    } on LiveException catch (e) {
      await _abortStart();
      error.value = e.message;
      phase.value = LiveHostPhase.ready;
    } catch (e) {
      debugPrint('Live : démarrage impossible ($e)');
      await _abortStart();
      error.value =
          'Le direct n’a pas pu démarrer. Vérifiez votre connexion et '
          'réessayez.';
      phase.value = LiveHostPhase.ready;
    }
  }

  Future<void> _connect(LiveTicket ticket, LocalVideoTrack track) async {
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // L'aperçu est publié tel quel : il ne doit pas s'arrêter si la
        // salle se reconnecte.
        stopLocalTrackOnUnpublish: false,
        defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
      ),
    );
    _room = room;
    _listener = media.attach(room)
      ..on<RoomReconnectingEvent>((_) => reconnecting.value = true)
      ..on<RoomReconnectedEvent>((_) => reconnecting.value = false)
      ..on<RoomDisconnectedEvent>((_) {
        if (phase.value == LiveHostPhase.live) unawaited(_recover());
      });
    await room.connect(ticket.url, ticket.token);
    await room.localParticipant?.publishVideoTrack(track);
    await room.localParticipant?.setMicrophoneEnabled(micOn.value);
  }

  /// La salle LiveKit a lâché pour de bon (réseau coupé trop longtemps) :
  /// on retente une fois avec un jeton neuf. Le live, lui, attend : la
  /// base temps réel l'a mis « hôte déconnecté » pendant ce temps.
  Future<void> _recover() async {
    final id = _liveId;
    final track = camera.value;
    if (id == null || track == null) return;
    reconnecting.value = true;
    try {
      await _disposeRoom();
      final ticket = await _service.join(id, fresh: true);
      await _connect(ticket, track);
      reconnecting.value = false;
    } catch (_) {
      reconnecting.value = false;
      await _finish(stoppedByServer: true);
    }
  }

  Future<void> _abortStart() async {
    final id = _liveId;
    _liveId = null;
    await _disposeRoom();
    if (id != null) {
      try {
        await _service.end(id);
      } catch (_) {}
    }
  }

  /// « Terminer » — ou fin imposée par le serveur.
  Future<void> endLive() => _finish(stoppedByServer: false);

  Future<void> _finish({required bool stoppedByServer}) async {
    if (phase.value == LiveHostPhase.ending ||
        phase.value == LiveHostPhase.ended) {
      return;
    }
    phase.value = LiveHostPhase.ending;
    _clock?.cancel();
    final f = feed.value;
    final last = f?.live.value;
    // D'abord annuler l'`onDisconnect`, puis clore : dans l'autre ordre,
    // une coupure réseau au mauvais moment recréerait un bout de live.
    await f?.close();
    final id = _liveId;
    if (id != null && !stoppedByServer) {
      try {
        await _service.end(id);
      } catch (_) {}
    }
    await _disposeRoom();
    // La caméra s'éteint avec le live, pas à la fermeture de l'écran.
    final cam = camera.value;
    camera.value = null;
    try {
      await cam?.stop();
      await cam?.dispose();
    } catch (_) {}
    summary.value = LiveSummary(
      duration: elapsed.value,
      peakViewers: _peakSeen,
      likes: last?.likes ?? 0,
      stoppedByServer: stoppedByServer,
    );
    phase.value = LiveHostPhase.ended;
  }

  Future<void> expel(LiveViewer viewer) async {
    final id = _liveId;
    if (id == null) return;
    try {
      await _service.expel(id, viewer.uid);
    } on LiveException catch (e) {
      Get.snackbar('Impossible', e.message);
    }
  }

  // -----------------------------------------------------------------------
  // Le panel : inviter, accepter, couper le micro, faire descendre
  // -----------------------------------------------------------------------

  /// Une action sur le panel ; le refus du serveur s'affiche tel quel.
  Future<void> stage(String action, String uid) async {
    final id = _liveId;
    if (id == null) return;
    try {
      await _service.stage(id, action, uid: uid);
    } on LiveException catch (e) {
      Get.snackbar('Impossible', e.message);
    }
  }

  Future<void> invite(String uid) => stage('invite', uid);
  Future<void> approve(String uid) => stage('approve', uid);
  Future<void> reject(String uid) => stage('reject', uid);

  /// Faire descendre un invité : il redevient spectateur.
  Future<void> removeFromStage(String uid) => stage('remove', uid);

  Future<void> toggleGuestMic(LiveGuest g) =>
      stage(g.mutedByHost ? 'unmute' : 'mute', g.uid);

  LiveMe _me() {
    final auth = Get.find<AuthService>();
    final profile = Get.find<UserProfileService>().profile.value;
    return LiveMe(
      uid: auth.uid,
      name: profile?.displayName.trim().isNotEmpty == true
          ? profile!.displayName
          : 'Habitant',
      photo: profile?.photoUrl,
    );
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    media.clear();
    if (room != null) {
      try {
        await room.disconnect();
        await room.dispose();
      } catch (_) {}
    }
  }

  @override
  void onClose() {
    _clock?.cancel();
    _endedWorker?.dispose();
    // Écran quitté en plein direct (geste système) : le live ne doit pas
    // rester ouvert sans image.
    if (phase.value == LiveHostPhase.live ||
        phase.value == LiveHostPhase.starting) {
      unawaited(_finish(stoppedByServer: false));
    } else {
      unawaited(feed.value?.close());
      unawaited(_disposeRoom());
    }
    final track = camera.value;
    camera.value = null;
    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await track?.stop();
        await track?.dispose();
      }).catchError((Object _) {}),
    );
    titleCtrl.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.onClose();
  }
}
