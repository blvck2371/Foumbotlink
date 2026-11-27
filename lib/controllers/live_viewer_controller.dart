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
import '../services/moderation_service.dart';
import '../services/user_profile_service.dart';
import 'live_feed.dart';
import 'live_stage.dart';

enum LiveWatchStatus { connecting, watching, ended, failed }

/// Un live regardé : la salle LiveKit (l'image et le son de l'hôte et de
/// ses invités) et son fil temps réel. Une seule à la fois — celle de la
/// page affichée.
///
/// Le spectateur peut aussi monter sur le panel, comme sur TikTok : il le
/// demande (ou accepte l'invitation de l'hôte), et quand le serveur le
/// place sur le panel, l'app reprend un jeton d'émission, se reconnecte à
/// la salle et publie sa caméra et son micro. Quand l'hôte le fait
/// descendre, ses pistes sont retirées et il redevient spectateur.
class LiveWatchSession {
  LiveWatchSession(this.initial, this.me);

  final LiveSession initial;
  final LiveMe me;

  final status = LiveWatchStatus.connecting.obs;
  final message = RxnString();
  final feed = Rxn<LiveFeed>();

  /// Images et micros de ceux qui émettent (hôte et invités).
  final media = LiveStageMedia();

  /// Ma caméra, quand je suis sur le panel.
  final camera = Rxn<LocalVideoTrack>();
  final frontCamera = true.obs;

  /// Mon micro tel que je le veux ; coupé de fait si l'hôte l'a coupé.
  final micOn = true.obs;

  /// Je publie sur le panel (salle reconnectée avec un jeton d'émission).
  final publishing = false.obs;

  /// Montée ou descente en cours.
  final stageBusy = false.obs;

  /// Navigateur qui bloque le son tant qu'on n'a pas touché la page : un
  /// bouton « Activer le son » s'affiche (web surtout).
  final audioBlocked = false.obs;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Worker? _endedWorker;
  Worker? _guestWorker;
  bool _disposed = false;
  LiveGuestStatus? _lastStatus;
  bool? _lastMuted;

  /// J'ai moi-même annulé ma demande : pas de « demande refusée ».
  bool _cancelledByMe = false;

  LiveService get _service => Get.find<LiveService>();

  /// État le plus frais : le fil temps réel s'il est ouvert, sinon ce que
  /// la liste montrait.
  LiveSession get live => feed.value?.live.value ?? initial;

  /// Ma place sur le panel (invitation, demande, ou sur le panel).
  LiveGuest? get myGuest => feed.value?.myGuest;

  Future<void> open() async {
    final LiveTicket ticket;
    try {
      ticket = await _service.join(initial.id);
    } on LiveException catch (e) {
      if (_disposed) return;
      message.value = e.message;
      status.value = e.ended ? LiveWatchStatus.ended : LiveWatchStatus.failed;
      return;
    }
    if (_disposed) return;

    final f = LiveFeed(liveId: initial.id, me: me, isHost: false);
    feed.value = f;
    // Fil temps réel et salle vidéo s'ouvrent en même temps : l'image
    // n'attend pas les commentaires.
    final feedStarted = f.start();
    _endedWorker = ever<bool>(f.ended, (gone) {
      if (!gone) return;
      status.value = LiveWatchStatus.ended;
      unawaited(_stopCamera());
      unawaited(_disposeRoom());
    });
    _guestWorker = ever<Map<String, LiveGuest>>(f.guests, (_) => _onGuest());
    if (_disposed) return;

    try {
      await _connect(ticket);
      await feedStarted;
      if (_disposed) return;
      // Le son d'un live sort du haut-parleur, pas de l'écouteur (réglage
      // propre au téléphone : le navigateur n'en a pas).
      if (!kIsWeb) {
        unawaited(
          AudioManager.instance
              .setSpeakerOutputPreferred(true)
              .catchError((Object _) {}),
        );
      }
      status.value = LiveWatchStatus.watching;
      _onGuest();
    } catch (_) {
      if (_disposed) return;
      message.value = 'Connexion au live impossible.';
      status.value = LiveWatchStatus.failed;
    }
  }

  Future<void> _connect(LiveTicket ticket) async {
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true));
    _room = room;
    _listener = media.attach(room)
      ..on<AudioPlaybackStatusChanged>((e) => audioBlocked.value = !e.isPlaying)
      ..on<RoomDisconnectedEvent>((e) {
        if (_disposed || status.value == LiveWatchStatus.ended) return;
        // Retiré par l'hôte, salle fermée : on ne reste pas devant un
        // écran noir.
        status.value = e.reason == DisconnectReason.participantRemoved
            ? LiveWatchStatus.failed
            : LiveWatchStatus.ended;
        message.value = e.reason == DisconnectReason.participantRemoved
            ? 'L’hôte vous a retiré de ce live.'
            : null;
      });
    await room.connect(ticket.url, ticket.token);
    media.refresh(room);
    if (kIsWeb) {
      // On arrive ici d'un toucher : la plupart des navigateurs laissent
      // alors jouer le son. Sinon, le bouton « Activer le son » prend le
      // relais.
      try {
        await room.startAudio();
      } catch (_) {}
      audioBlocked.value = !room.canPlaybackAudio;
    }
  }

  /// « Activer le son » : un toucher suffit au navigateur.
  Future<void> enableAudio() async {
    try {
      await _room?.startAudio();
    } catch (_) {}
    audioBlocked.value = !(_room?.canPlaybackAudio ?? true);
  }

  /// Suit ma place sur le panel, telle que le serveur la tient.
  void _onGuest() {
    if (_disposed || status.value != LiveWatchStatus.watching) return;
    final g = myGuest;
    final st = g?.status;
    final muted = g?.mutedByHost ?? false;
    if (st == LiveGuestStatus.onStage && !publishing.value) {
      if (_lastStatus != LiveGuestStatus.onStage) unawaited(_goOnStage());
    } else if (st != LiveGuestStatus.onStage &&
        _lastStatus == LiveGuestStatus.onStage) {
      unawaited(_leaveStageLocally(byHost: true));
    } else if (st == LiveGuestStatus.onStage && _lastMuted != muted) {
      unawaited(_applyMic());
      if (muted) {
        Get.snackbar('Micro coupé', 'L’hôte a coupé votre micro.');
      }
    }
    if (_lastStatus == LiveGuestStatus.requested &&
        st == null &&
        !_cancelledByMe) {
      Get.snackbar('Demande refusée', 'L’hôte n’a pas accepté votre demande.');
    }
    _lastStatus = st;
    _lastMuted = muted;
  }

  /// Placé sur le panel : jeton d'émission, salle reconnectée, caméra et
  /// micro publiés.
  Future<void> _goOnStage() async {
    if (stageBusy.value) return;
    stageBusy.value = true;
    try {
      final ticket = await _service.join(initial.id, fresh: true);
      if (_disposed) return;
      if (!ticket.isGuest) return; // plus sur le panel entre-temps
      LocalVideoTrack? cam;
      try {
        cam = await LocalVideoTrack.createCameraTrack(
          const CameraCaptureOptions(
            cameraPosition: CameraPosition.front,
            params: VideoParametersPresets.h540_169,
          ),
        );
      } catch (_) {
        // Sans caméra, on monte quand même avec le micro.
      }
      if (_disposed) {
        await cam?.stop();
        return;
      }
      frontCamera.value = true;
      camera.value = cam;
      await _disposeRoom();
      await _connect(ticket);
      final local = _room?.localParticipant;
      if (cam != null) await local?.publishVideoTrack(cam);
      publishing.value = true;
      await _applyMic();
      Get.snackbar(
        'Vous êtes en direct',
        'Vous avez rejoint le panel de ${live.hostName}.',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('Live : montée sur le panel impossible ($e)');
      Get.snackbar('Impossible', 'Vous n’avez pas pu monter sur le panel.');
      unawaited(_leave());
    } finally {
      stageBusy.value = false;
    }
  }

  /// Redevenir spectateur : pistes retirées, caméra éteinte. La salle
  /// reste ouverte (le serveur a déjà repris le droit d'émettre).
  Future<void> _leaveStageLocally({required bool byHost}) async {
    final wasPublishing = publishing.value;
    publishing.value = false;
    try {
      await _room?.localParticipant?.unpublishAllTracks();
    } catch (_) {}
    await _stopCamera();
    if (byHost && wasPublishing && !_disposed) {
      Get.snackbar('Panel', 'Vous êtes redevenu spectateur.');
    }
  }

  Future<void> _stopCamera() async {
    final cam = camera.value;
    camera.value = null;
    try {
      await cam?.stop();
      await cam?.dispose();
    } catch (_) {}
  }

  Future<void> _applyMic() async {
    final on = micOn.value && !(myGuest?.mutedByHost ?? false);
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(on);
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Actions du spectateur
  // -----------------------------------------------------------------------

  /// Caméra et micro autorisés, sinon pas de panel.
  Future<bool> _ensurePermissions() async {
    // Sur le web, c'est le navigateur qui demande caméra et micro, à
    // l'ouverture de la caméra.
    if (kIsWeb) return true;
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (statuses[Permission.microphone]?.isGranted ?? false) return true;
    Get.snackbar(
      'Micro requis',
      'Autorisez le micro (et la caméra) pour monter sur le panel.',
    );
    return false;
  }

  Future<void> _call(String action) async {
    try {
      await _service.stage(initial.id, action);
    } on LiveException catch (e) {
      Get.snackbar('Impossible', e.message);
    }
  }

  /// « Rejoindre » : demander à monter sur le panel.
  Future<void> requestJoin() async {
    if (!await _ensurePermissions()) return;
    _cancelledByMe = false;
    await _call('request');
  }

  Future<void> acceptInvite() async {
    if (!await _ensurePermissions()) {
      await _call('leave');
      return;
    }
    await _call('accept');
  }

  /// Refuser une invitation, annuler une demande, ou quitter le panel.
  Future<void> _leave() => _call('leave');
  Future<void> declineInvite() => _leave();
  Future<void> cancelRequest() {
    _cancelledByMe = true;
    return _leave();
  }

  Future<void> leaveStage() async {
    await _leaveStageLocally(byHost: false);
    await _leave();
  }

  Future<void> toggleMic() async {
    if (myGuest?.mutedByHost ?? false) {
      Get.snackbar('Micro coupé', 'L’hôte a coupé votre micro.');
      return;
    }
    micOn.value = !micOn.value;
    await _applyMic();
  }

  Future<void> switchCamera() async {
    final cam = camera.value;
    if (cam == null) return;
    final toFront = !frontCamera.value;
    try {
      await cam.setCameraPosition(
        toFront ? CameraPosition.front : CameraPosition.back,
      );
      frontCamera.value = toFront;
    } catch (_) {}
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _endedWorker?.dispose();
    _guestWorker?.dispose();
    // On quitte ce live (glissé vers un autre, écran fermé) : la place sur
    // le panel, la demande ou l'invitation tombent avec.
    if (myGuest != null && !(feed.value?.ended.value ?? true)) {
      unawaited(_service.stage(initial.id, 'leave').catchError((Object _) {}));
    }
    publishing.value = false;
    await _stopCamera();
    await feed.value?.close();
    await _disposeRoom();
  }
}

/// Regarder des lives, l'un après l'autre en glissant vers le haut, comme
/// sur TikTok. Seule la page affichée est connectée : glisser quitte le
/// live précédent avant d'entrer dans le suivant.
class LiveViewerController extends GetxController {
  LiveService get _service => Get.find<LiveService>();
  ModerationService get _moderation => Get.find<ModerationService>();

  final pages = <LiveSession>[].obs;
  final index = 0.obs;
  final session = Rxn<LiveWatchSession>();

  /// Ouvert depuis une notification sur un live déjà terminé.
  final missing = false.obs;
  final loading = true.obs;

  late final PageController pageController;
  String get _myUid {
    final auth = Get.find<AuthService>();
    return auth.isSignedIn ? auth.uid : '';
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    final wanted = args is Map ? args['liveId'] as String? : null;
    unawaited(WakelockPlus.enable().catchError((Object _) {}));

    // La liste est figée à l'ouverture (les lives ne changent pas de
    // place sous le doigt) ; les nouveaux s'ajoutent à la fin.
    final list = _visible(_service.lives);
    var start = wanted == null ? 0 : list.indexWhere((l) => l.id == wanted);
    pageController = PageController(initialPage: start < 0 ? 0 : start);
    if (_myUid.isEmpty) {
      // Ouvert depuis une notification après déconnexion.
      missing.value = true;
      loading.value = false;
      return;
    }
    pages.assignAll(list);
    ever<List<LiveSession>>(_service.lives, _appendNew);

    if (wanted != null && start < 0) {
      unawaited(
        _service.fetch(wanted).then((live) {
          if (isClosed) return;
          if (live == null || live.hostUid == _myUid) {
            missing.value = true;
            loading.value = false;
            return;
          }
          pages.insert(0, live);
          _select(0);
        }),
      );
    } else if (list.isEmpty) {
      missing.value = true;
      loading.value = false;
    } else {
      _select(start < 0 ? 0 : start);
    }
  }

  List<LiveSession> _visible(Iterable<LiveSession> all) => [
    for (final l in all)
      if (l.hostUid != _myUid && !_moderation.hides(l.hostUid)) l,
  ];

  void _appendNew(List<LiveSession> all) {
    final known = pages.map((p) => p.id).toSet();
    final fresh = _visible(all).where((l) => !known.contains(l.id));
    if (fresh.isNotEmpty) pages.addAll(fresh);
  }

  void onPageChanged(int i) => _select(i);

  void _select(int i) {
    if (i < 0 || i >= pages.length) return;
    loading.value = false;
    index.value = i;
    final previous = session.value;
    if (previous?.initial.id == pages[i].id) return;
    unawaited(previous?.dispose());
    final next = LiveWatchSession(pages[i], _me());
    session.value = next;
    unawaited(next.open());
    // Le live suivant (et le précédent) s'ouvriront sans attente.
    if (i + 1 < pages.length) _service.prefetch(pages[i + 1].id);
    if (i > 0) _service.prefetch(pages[i - 1].id);
  }

  LiveMe _me() {
    final profile = Get.find<UserProfileService>().profile.value;
    return LiveMe(
      uid: _myUid,
      name: profile?.displayName.trim().isNotEmpty == true
          ? profile!.displayName
          : 'Habitant',
      photo: profile?.photoUrl,
    );
  }

  /// Bloquer l'hôte : on quitte son live, qui disparaît de la liste.
  void removeCurrentPage() {
    final i = index.value;
    if (i >= pages.length) return;
    unawaited(session.value?.dispose());
    session.value = null;
    pages.removeAt(i);
    if (pages.isEmpty) {
      Get.back();
      return;
    }
    _select(i.clamp(0, pages.length - 1));
  }

  @override
  void onClose() {
    unawaited(session.value?.dispose());
    pageController.dispose();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.onClose();
  }
}
