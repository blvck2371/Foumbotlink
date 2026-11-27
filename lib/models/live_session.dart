/// Lives : ce qui circule dans la Realtime Database (`lives/{id}`,
/// `liveComments/{id}/…`, `liveViewers/{id}/…`), lu en temps réel.
///
/// La vidéo, elle, passe par LiveKit (voir `functions/lives.js`).
library;

/// Un live en cours, tel que publié dans `lives/{liveId}`.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.hostUid,
    required this.hostName,
    required this.title,
    required this.startedAt,
    this.hostPhoto,
    this.viewers = 0,
    this.likes = 0,
    this.hostOnline = true,
  });

  final String id;
  final String hostUid;
  final String hostName;
  final String? hostPhoto;
  final String title;
  final DateTime startedAt;

  /// Spectateurs présents, compté par le serveur.
  final int viewers;

  /// Cœurs reçus depuis le début.
  final int likes;

  /// Faux quand l'app de l'hôte a perdu la connexion : le live attend son
  /// retour (le serveur le clôt au-delà de 90 s).
  final bool hostOnline;

  /// `null` pour un nœud incomplet — par exemple un reste réécrit par
  /// l'`onDisconnect` d'un hôte après la fin du live. Il ne doit jamais
  /// s'afficher.
  static LiveSession? fromMap(String id, Object? raw) {
    if (raw is! Map) return null;
    final hostUid = raw['hostUid'];
    if (hostUid is! String || hostUid.isEmpty) return null;
    final started = raw['startedAt'];
    final name = raw['hostName'];
    final photo = raw['hostPhoto'];
    final title = raw['title'];
    return LiveSession(
      id: id,
      hostUid: hostUid,
      hostName: name is String && name.trim().isNotEmpty ? name : 'Habitant',
      hostPhoto: photo is String && photo.startsWith('http') ? photo : null,
      title: title is String && title.trim().isNotEmpty
          ? title
          : 'Live de ${name is String ? name : 'Habitant'}',
      startedAt: started is num
          ? DateTime.fromMillisecondsSinceEpoch(started.toInt())
          : DateTime.now(),
      viewers: _int(raw['viewers']),
      likes: _int(raw['likes']),
      hostOnline: raw['hostOnline'] != false,
    );
  }

  /// Les lives d'un instantané de `lives`, les plus regardés d'abord, puis
  /// les plus récents. Les nœuds incomplets sont écartés.
  static List<LiveSession> listFrom(Object? raw) {
    if (raw is! Map) return const [];
    final list = <LiveSession>[
      for (final e in raw.entries)
        if (e.key is String) ?LiveSession.fromMap(e.key as String, e.value),
    ];
    list.sort((a, b) {
      final byViewers = b.viewers.compareTo(a.viewers);
      return byViewers != 0 ? byViewers : b.startedAt.compareTo(a.startedAt);
    });
    return list;
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// Où en est quelqu'un avec le panel d'un live (`liveGuests/{liveId}/{uid}`).
enum LiveGuestStatus {
  /// L'hôte l'a invité : à lui d'accepter.
  invited,

  /// Il a demandé à monter : à l'hôte d'accepter.
  requested,

  /// Sur le panel : il émet image et son, comme l'hôte.
  onStage,
}

/// Une place sur le panel (ou une demande, ou une invitation). Tenu par
/// le serveur seul (fonction `liveStage`).
class LiveGuest {
  const LiveGuest({
    required this.uid,
    required this.name,
    required this.status,
    required this.at,
    this.photo,
    this.mutedByHost = false,
  });

  final String uid;
  final String name;
  final String? photo;
  final LiveGuestStatus status;
  final DateTime at;

  /// L'hôte lui a coupé le micro : il ne peut pas le rallumer lui-même.
  final bool mutedByHost;

  bool get onStage => status == LiveGuestStatus.onStage;

  static LiveGuest? fromMap(String uid, Object? raw) {
    if (raw is! Map) return null;
    final status = switch (raw['status']) {
      'invited' => LiveGuestStatus.invited,
      'requested' => LiveGuestStatus.requested,
      'onStage' => LiveGuestStatus.onStage,
      _ => null,
    };
    if (status == null) return null;
    final name = raw['name'];
    final photo = raw['photo'];
    final at = raw['at'];
    return LiveGuest(
      uid: uid,
      name: name is String && name.trim().isNotEmpty ? name : 'Habitant',
      photo: photo is String && photo.startsWith('http') ? photo : null,
      status: status,
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : DateTime.now(),
      mutedByHost: raw['mutedByHost'] == true,
    );
  }

  /// Le contenu de `liveGuests/{liveId}`, entrées invalides écartées.
  static Map<String, LiveGuest> mapFrom(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, LiveGuest>{};
    for (final e in raw.entries) {
      final g = e.key is String
          ? LiveGuest.fromMap(e.key as String, e.value)
          : null;
      if (g != null) out[g.uid] = g;
    }
    return out;
  }

  /// Invités sur le panel, dans l'ordre où ils sont montés.
  static List<LiveGuest> stageOf(Map<String, LiveGuest> all) =>
      all.values.where((g) => g.onStage).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
}

/// Un commentaire de `liveComments/{liveId}/{id}`.
class LiveComment {
  const LiveComment({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.at,
    this.photo,
  });

  final String id;
  final String uid;
  final String name;
  final String? photo;
  final String text;
  final DateTime at;

  static LiveComment? fromMap(String id, Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    final text = raw['text'];
    if (uid is! String || text is! String || text.isEmpty) return null;
    final name = raw['name'];
    final photo = raw['photo'];
    final at = raw['at'];
    return LiveComment(
      id: id,
      uid: uid,
      name: name is String && name.isNotEmpty ? name : 'Habitant',
      photo: photo is String && photo.startsWith('http') ? photo : null,
      text: text,
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : DateTime.now(),
    );
  }
}

/// Ce qui défile en bas à gauche d'un live : un commentaire, ou l'arrivée
/// d'un spectateur (« Bob a rejoint »).
sealed class LiveFeedItem {
  const LiveFeedItem();
  String get key;
}

class LiveCommentItem extends LiveFeedItem {
  const LiveCommentItem(this.comment);
  final LiveComment comment;
  @override
  String get key => 'c_${comment.id}';
}

class LiveJoinItem extends LiveFeedItem {
  const LiveJoinItem({required this.uid, required this.name, required this.at});
  final String uid;
  final String name;
  final DateTime at;
  @override
  String get key => 'j_${uid}_${at.millisecondsSinceEpoch}';
}

/// Une annonce du live : « Bob demande à rejoindre », « Bob monte sur le
/// panel ».
class LiveNoticeItem extends LiveFeedItem {
  const LiveNoticeItem({required this.text, required this.at});
  final String text;
  final DateTime at;
  @override
  String get key => 'n_${at.microsecondsSinceEpoch}_${text.hashCode}';
}

/// Règles partagées par l'écran et les tests — alignées sur
/// database.rules.json et functions/lives.js.
abstract final class LiveRules {
  static const maxTitle = 80;
  static const maxComment = 200;

  /// Invités sur le panel en plus de l'hôte (aligné sur `MAX_GUESTS` de
  /// functions/lives.js).
  static const maxGuests = 3;

  /// Cœurs envoyés d'un coup au plus : la règle RTDB refuse une hausse de
  /// plus de 30.
  static const maxLikesPerWrite = 30;

  /// Écart minimal entre deux commentaires d'un même spectateur.
  static const commentCooldown = Duration(milliseconds: 1500);

  /// Fil gardé en mémoire : au-delà, les plus anciens sortent.
  static const maxFeedItems = 80;

  /// Texte prêt à envoyer, ou `null` s'il n'y a rien à envoyer. Les
  /// espaces répétés et les retours à la ligne sont aplatis : un
  /// commentaire de live tient sur une ou deux lignes.
  static String? cleanComment(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length > maxComment ? t.substring(0, maxComment) : t;
  }

  static String cleanTitle(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maxTitle ? t.substring(0, maxTitle) : t;
  }

  /// « 7 », « 1,2 k », « 15 k », « 1,3 M ».
  static String compactCount(int n) {
    if (n < 1000) return '$n';
    String one(double v) {
      final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      return s.endsWith('.0')
          ? s.substring(0, s.length - 2)
          : s.replaceAll('.', ',');
    }

    if (n < 1000000) return '${one(n / 1000)} k';
    return '${one(n / 1000000)} M';
  }

  /// Durée d'antenne : « 0:42 », « 12:05 », « 1:03:09 ».
  static String elapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// Regroupe les cœurs tapés à la chaîne en une seule écriture : taper
/// vingt fois en deux secondes ne doit pas produire vingt écritures, et
/// la règle RTDB plafonne une hausse à [LiveRules.maxLikesPerWrite].
///
/// Sert aussi à ne pas animer deux fois ses propres cœurs : ils
/// s'affichent au toucher, puis reviennent du serveur dans le compteur.
class HeartBatcher {
  int _pending = 0;
  int _unconfirmed = 0;

  /// Un cœur de plus à envoyer.
  void tap() => _pending++;

  bool get hasPending => _pending > 0;

  /// Mes cœurs pas encore revenus du serveur : ajoutés au compteur affiché
  /// pour qu'il monte dès le toucher.
  int get outstanding => _pending + _unconfirmed;

  /// Ce qu'il faut écrire maintenant (au plus 30) ; le reste attend le
  /// prochain envoi.
  int take() {
    final n = _pending.clamp(0, LiveRules.maxLikesPerWrite);
    _pending -= n;
    _unconfirmed += n;
    return n;
  }

  /// L'écriture a échoué : ces cœurs ne reviendront pas du serveur.
  void failed(int n) => _unconfirmed = (_unconfirmed - n).clamp(0, 1 << 30);

  /// Le compteur du serveur a monté de [delta] : renvoie combien de cœurs
  /// viennent des autres (les miens ont déjà été animés).
  int othersIn(int delta) {
    if (delta <= 0) return 0;
    final mine = delta < _unconfirmed ? delta : _unconfirmed;
    _unconfirmed -= mine;
    return delta - mine;
  }
}
