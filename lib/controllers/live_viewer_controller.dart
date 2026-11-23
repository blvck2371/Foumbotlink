import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/live_session.dart';
import '../services/auth_service.dart';
import '../services/live_service.dart';
import '../services/moderation_service.dart';
import '../services/user_profile_service.dart';
import 'live_feed.dart';

enum LiveWatchStatus { connecting, watching, ended, failed }

/// Un live regardé : la salle LiveKit (l'image et le son de l'hôte) et
/// son fil temps réel. Une seule à la fois — celle de la page affichée.
class LiveWatchSession {
  LiveWatchSession(this.initial, this.me);

  final LiveSession initial;
  final LiveMe me;

  final status = LiveWatchStatus.connecting.obs;
  final message = RxnString();
  final video = Rxn<VideoTrack>();
  final feed = Rxn<LiveFeed>();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Worker? _endedWorker;
  bool _disposed = false;

  LiveService get _service => Get.find<LiveService>();

  /// État le plus frais : le fil temps réel s'il est ouvert, sinon ce que
  /// la liste montrait.
  LiveSession get live => feed.value?.live.value ?? initial;

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
    await f.start();
    _endedWorker = ever<bool>(f.ended, (gone) {
      if (!gone) return;
      status.value = LiveWatchStatus.ended;
      video.value = null;
      unawaited(_disposeRoom());
    });
    if (_disposed) return;

    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true));
    _room = room;
    _listener = room.createListener()
      ..on<TrackSubscribedEvent>((_) => _refresh())
      ..on<TrackUnsubscribedEvent>((_) => _refresh())
      ..on<TrackMutedEvent>((_) => _refresh())
      ..on<TrackUnmutedEvent>((_) => _refresh())
      ..on<ParticipantConnectedEvent>((_) => _refresh())
      ..on<ParticipantDisconnectedEvent>((_) => _refresh())
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
    try {
      await room.connect(ticket.url, ticket.token);
      if (_disposed) return;
      // Le son d'un live sort du haut-parleur, pas de l'écouteur.
      unawaited(
        AudioManager.instance
            .setSpeakerOutputPreferred(true)
            .catchError((Object _) {}),
      );
      status.value = LiveWatchStatus.watching;
      _refresh();
    } catch (_) {
      if (_disposed) return;
      message.value = 'Connexion au live impossible.';
      status.value = LiveWatchStatus.failed;
    }
  }

  void _refresh() {
    final room = _room;
    if (room == null || _disposed) return;
    RemoteParticipant? host;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == initial.hostUid) host = p;
    }
    final pub = host?.videoTrackPublications.firstWhereOrNull(
      (p) => p.subscribed && p.track != null && !p.muted,
    );
    video.value = pub?.track;
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
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
    video.value = null;
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
