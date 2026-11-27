import 'package:get/get.dart';
import 'package:livekit_client/livekit_client.dart';

/// Ce que la salle LiveKit montre de chaque personne qui émet dans un
/// live — l'hôte et ses invités sur le panel : son image, et si son micro
/// est coupé. Tenu à jour à chaque événement de la salle, côté hôte comme
/// côté spectateur.
class LiveStageMedia {
  /// Image de chacun, par identité LiveKit (l'uid Firebase).
  final videos = <String, VideoTrack>{}.obs;

  /// Ceux dont le micro est coupé (ou absent).
  final micOff = <String>{}.obs;

  /// Écoute [room] ; à disposer avec la salle.
  EventsListener<RoomEvent> attach(
    Room room, {
    void Function(RoomEvent event)? onEvent,
  }) {
    void refresh(RoomEvent e) {
      _refresh(room);
      onEvent?.call(e);
    }

    return room.createListener()
      ..on<TrackSubscribedEvent>(refresh)
      ..on<TrackUnsubscribedEvent>(refresh)
      ..on<TrackPublishedEvent>(refresh)
      ..on<TrackUnpublishedEvent>(refresh)
      ..on<TrackMutedEvent>(refresh)
      ..on<TrackUnmutedEvent>(refresh)
      ..on<ParticipantConnectedEvent>(refresh)
      ..on<ParticipantDisconnectedEvent>(refresh);
  }

  void refresh(Room room) => _refresh(room);

  void _refresh(Room room) {
    final v = <String, VideoTrack>{};
    final off = <String>{};
    for (final p in room.remoteParticipants.values) {
      final pub = p.videoTrackPublications.firstWhereOrNull(
        (x) => x.subscribed && x.track != null && !x.muted,
      );
      final track = pub?.track;
      if (track != null) v[p.identity] = track;
      final audio = p.audioTrackPublications;
      if (audio.isEmpty || audio.every((a) => a.muted)) off.add(p.identity);
    }
    videos.assignAll(v);
    micOff.assignAll(off);
  }

  void clear() {
    videos.clear();
    micOff.clear();
  }
}
