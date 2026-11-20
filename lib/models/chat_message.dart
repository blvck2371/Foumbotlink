import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, voice, image, video, document, sticker }

/// Le statut auquel un message se rapporte.
///
/// Aimer ou commenter un statut n'ouvre pas un fil de discussion à part :
/// ça envoie un message dans la conversation avec son auteur, exactement
/// comme WhatsApp. Le message porte donc une copie de ce à quoi il
/// répond — vignette, texte, couleur de fond — dénormalisée au moment de
/// l'envoi : un statut vit 24 heures, la citation doit rester lisible
/// bien après sa disparition.
class StatusRef {
  const StatusRef({
    required this.statusId,
    required this.authorUid,
    this.previewUrl,
    this.text = '',
    this.backgroundColor = 0xFFEF6C00,
    this.isLike = false,
    this.isVideo = false,
  });

  final String statusId;

  /// Auteur du statut — pas forcément le destinataire du message : on
  /// peut aimer le statut de quelqu'un qui l'a lui-même repartagé.
  final String authorUid;

  /// Image du statut, quand il en a une. `null` pour un statut texte, et
  /// pour une vidéo (dont on n'extrait pas de vignette côté client).
  final String? previewUrl;

  /// Aperçu d'une ligne du statut.
  final String text;

  /// Fond d'un statut texte, en ARGB — sert à redessiner la vignette de
  /// citation à l'identique.
  final int backgroundColor;

  /// Vrai quand le message est une réaction (« ❤️ ») plutôt qu'un
  /// commentaire écrit. L'affichage annonce alors « a aimé votre statut »
  /// au lieu de présenter une réponse.
  final bool isLike;

  final bool isVideo;

  Map<String, dynamic> toMap() => {
    'statusId': statusId,
    'authorUid': authorUid,
    if (previewUrl != null) 'previewUrl': previewUrl,
    'text': text,
    'backgroundColor': backgroundColor,
    'isLike': isLike,
    'isVideo': isVideo,
  };

  static StatusRef? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final id = map['statusId'] as String?;
    if (id == null || id.isEmpty) return null;
    return StatusRef(
      statusId: id,
      authorUid: map['authorUid'] as String? ?? '',
      previewUrl: map['previewUrl'] as String?,
      text: map['text'] as String? ?? '',
      backgroundColor: (map['backgroundColor'] as num?)?.toInt() ?? 0xFFEF6C00,
      isLike: map['isLike'] as bool? ?? false,
      isVideo: map['isVideo'] as bool? ?? false,
    );
  }
}

/// État d'envoi purement local (jamais persisté) — un message lu depuis
/// Firestore existe forcément déjà côté serveur, donc toujours [sent].
/// [sending]/[failed] ne s'appliquent qu'aux messages construits en local
/// avant confirmation, le temps de l'upload/écriture (voir
/// ChatController._localMessages).
enum MessageDeliveryStatus { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.type,
    required this.content,
    this.fileName,
    this.durationMs,
    this.thumbUrl,
    this.viewOnce = false,
    this.viewOnceOpenedAt,
    this.screenshotAt,
    required this.createdAt,
    this.readAt,
    this.expiresAt,
    this.status = MessageDeliveryStatus.sent,
    this.hasServerTimestamp = true,
    this.replyToId,
    this.replyToSenderUid,
    this.replyToText,
    this.statusRef,
    this.deleted = false,
    this.reactions = const {},
    this.hiddenFor = const [],
  });

  /// Délai pendant lequel un message peut encore être retiré **à tout le
  /// monde**, à compter de son envoi.
  ///
  /// Même valeur que WhatsApp (2 jours et 12 heures). Au-delà, le message
  /// a été lu, cité, peut-être capturé : le retirer de l'écran d'en face
  /// ne le retirerait de nulle part ailleurs, et donnerait une fausse
  /// impression d'effacement. Passé ce délai, seule la suppression pour
  /// soi reste offerte.
  static const deleteForEveryoneWindow = Duration(hours: 60);

  final String id;
  final String senderUid;
  final MessageType type;
  final String content;
  final String? fileName;
  final int? durationMs;

  /// Image d'aperçu d'une vidéo, extraite du fichier à l'envoi puis
  /// stockée à côté de lui.
  ///
  /// Sans elle, la bulle ne pourrait montrer le contenu qu'en décodant la
  /// vidéo elle-même — autant de décodeurs que de vidéos à l'écran, ce
  /// qu'un téléphone d'entrée de gamme ne tient pas en défilant. Une
  /// vignette JPEG se charge et se met en cache comme une photo ordinaire.
  ///
  /// Porte le chemin du fichier **local** tant que le message n'est pas
  /// parti, l'URL Storage ensuite — même convention que [content].
  final String? thumbUrl;

  /// Message à vue unique : lisible une fois par son destinataire, puis
  /// consommé ([viewOnceOpenedAt]).
  ///
  /// Ne concerne que ce qui s'ouvre — vocal, photo, vidéo. Un texte à vue
  /// unique n'aurait pas de sens : il est lisible dans la bulle sans
  /// qu'on ait rien à ouvrir.
  final bool viewOnce;

  /// Moment où le destinataire l'a ouvert. `null` tant qu'il ne l'a pas
  /// fait. C'est **ce champ** qui interdit une seconde ouverture, pas
  /// l'effacement de [content] qui l'accompagne : si l'app meurt entre
  /// les deux, le message reste fermé.
  final DateTime? viewOnceOpenedAt;

  /// Moment où le destinataire a capturé l'écran pendant l'affichage
  /// (iOS seulement — Android bloque la capture au lieu de la signaler).
  ///
  /// Écrit par celui qui a capturé, et lu par celui qui a envoyé : c'est
  /// tout ce qu'on peut faire d'une capture, puisqu'on ne l'apprend
  /// qu'une fois qu'elle a eu lieu.
  final DateTime? screenshotAt;

  bool get wasScreenshotted => screenshotAt != null;

  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final MessageDeliveryStatus status;

  /// Réponse à un message (façon iMessage / WhatsApp). L'aperçu est
  /// dénormalisé (`replyToText`) au moment de l'envoi : la citation reste
  /// lisible même si le message d'origine est supprimé, expiré (éphémère)
  /// ou hors de la fenêtre chargée, et n'exige aucune lecture supplémentaire.
  final String? replyToId;
  final String? replyToSenderUid;
  final String? replyToText;

  bool get isReply => replyToId != null;

  /// Réaction ou commentaire sur un statut. Le message reste un message
  /// ordinaire — citable, supprimable, éphémère si la conversation l'est —
  /// il porte simplement en plus ce à quoi il répond.
  final StatusRef? statusRef;

  bool get isStatusReply => statusRef != null;

  /// Suppression douce : le message reste dans la conversation mais son
  /// contenu est effacé, et l'interface affiche « Message supprimé ».
  /// Même choix que pour les commentaires du fil ([FeedComment.deleted]) —
  /// retirer le document laisserait un trou dans les réponses qui le
  /// citent, et casserait l'ordre des accusés de lecture.
  final bool deleted;

  /// Réactions emoji, une par personne : `{uid: '👍'}`. Une carte plutôt
  /// qu'une sous-collection — c'est petit, borné par le nombre de
  /// participants, et ça arrive avec le message sans lecture de plus.
  final Map<String, String> reactions;

  /// Les personnes qui ont retiré ce message **de leur seul affichage**.
  /// Le message reste intact pour les autres — c'est la « suppression
  /// pour moi ».
  final List<String> hiddenFor;

  bool isHiddenFor(String uid) => hiddenFor.contains(uid);

  /// Vrai si [uid] peut encore retirer ce message à tout le monde : il
  /// faut en être l'auteur, qu'il ne soit pas déjà supprimé, et rester
  /// dans [deleteForEveryoneWindow].
  ///
  /// La même condition est reprise par les règles Firestore : ce contrôle
  /// décide de ce qu'on propose, pas de ce qui est permis.
  bool canDeleteForEveryone(String uid, {DateTime? now}) {
    if (deleted || senderUid != uid) return false;
    final elapsed = (now ?? DateTime.now()).difference(createdAt);
    return !elapsed.isNegative && elapsed <= deleteForEveryoneWindow;
  }

  /// Les emojis présents, avec leur nombre, du plus employé au moins.
  List<({String emoji, int count})> get reactionCounts {
    final tally = <String, int>{};
    for (final emoji in reactions.values) {
      tally[emoji] = (tally[emoji] ?? 0) + 1;
    }
    final entries = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) (emoji: e.key, count: e.value)];
  }

  /// `false` tant que `createdAt` provient de l'horloge locale (message
  /// tout juste envoyé, en attente de résolution de `FieldValue
  /// .serverTimestamp()`). Une fois le serveur passé, la valeur est
  /// remplacée par le vrai timestamp et ce drapeau devient `true`. Sert de
  /// clé de tri dans ChatController._rebuildMessages : seuls les
  /// timestamps serveur sont comparables entre deux appareils, donc les
  /// messages non encore confirmés restent en bas de la discussion.
  final bool hasServerTimestamp;

  /// Les types qui s'ouvrent, donc les seuls qui peuvent être à vue
  /// unique. Un texte ou un sticker se lit dans la bulle : il n'y a rien
  /// à « ouvrir », donc rien à consommer.
  bool get supportsViewOnce =>
      type == MessageType.image ||
      type == MessageType.video ||
      type == MessageType.voice;

  /// Déjà ouvert : il ne reste que la trace du message.
  bool get viewOnceConsumed => viewOnce && viewOnceOpenedAt != null;

  /// Vrai si [uid] peut l'ouvrir maintenant — une seule fois, et jamais
  /// pour qui l'a envoyé : l'expéditeur consommerait son propre message
  /// avant que l'autre l'ait vu.
  bool canOpenViewOnce(String uid) =>
      viewOnce && !deleted && viewOnceOpenedAt == null && senderUid != uid;

  /// Vrai pour les messages dont le contenu occupe la bulle bord à bord
  /// (photo, vidéo) : la bulle se resserre alors à 4 px au lieu de la
  /// gouttière de texte, et les éléments qui l'accompagnent — citation,
  /// réactions, heure — se décalent pour ne pas coller au média.
  /// Un média à vue unique n'en fait pas partie : tant qu'il n'est pas
  /// ouvert, sa bulle ne contient qu'une ligne de texte et son cachet —
  /// collée aux bords, elle paraîtrait rognée.
  bool get isMediaBubble =>
      (type == MessageType.image || type == MessageType.video) && !viewOnce;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isRead => readAt != null;

  ChatMessage copyWith({MessageDeliveryStatus? status}) => ChatMessage(
    id: id,
    senderUid: senderUid,
    type: type,
    content: content,
    fileName: fileName,
    durationMs: durationMs,
    thumbUrl: thumbUrl,
    viewOnce: viewOnce,
    viewOnceOpenedAt: viewOnceOpenedAt,
    screenshotAt: screenshotAt,
    createdAt: createdAt,
    readAt: readAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    hasServerTimestamp: hasServerTimestamp,
    replyToId: replyToId,
    replyToSenderUid: replyToSenderUid,
    replyToText: replyToText,
    statusRef: statusRef,
    deleted: deleted,
    reactions: reactions,
    hiddenFor: hiddenFor,
  );

  /// `m:ss` — durée d'un vocal comme d'une vidéo.
  String get durationLabel {
    if (durationMs == null) return '0:00';
    final secs = (durationMs! / 1000).round();
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Aperçu court d'une ligne, réutilisé pour la citation d'une réponse et
  /// l'aperçu de conversation.
  String get shortPreview {
    if (deleted) return 'Message supprimé';
    return _typePreview;
  }

  String get _typePreview {
    final status = statusRef;
    if (status != null) {
      return status.isLike ? '❤️ A aimé votre statut' : '💬 $_textPreview';
    }
    return _plainTypePreview;
  }

  String get _plainTypePreview {
    // Un message à vue unique ne dit pas ce qu'il contient au-delà de son
    // type : son aperçu s'affiche dans la liste des conversations et dans
    // la notification, deux endroits qu'on lit sans l'ouvrir.
    if (viewOnce && supportsViewOnce) {
      final noun = switch (type) {
        MessageType.voice => 'Message vocal',
        MessageType.video => 'Vidéo',
        _ => 'Photo',
      };
      return viewOnceConsumed ? '👁 $noun ouvert' : '👁 $noun · vue unique';
    }
    return switch (type) {
      MessageType.voice => '🎤 Message vocal',
      MessageType.image => '📷 Photo',
      MessageType.video => '🎥 Vidéo',
      MessageType.document => '📎 ${fileName ?? 'Document'}',
      MessageType.sticker => content,
      MessageType.text => _textPreview,
    };
  }

  String get _textPreview =>
      content.length > 120 ? '${content.substring(0, 120)}…' : content;

  Map<String, dynamic> toMap() => {
    'senderUid': senderUid,
    'type': type.name,
    'content': content,
    if (fileName != null) 'fileName': fileName,
    if (durationMs != null) 'durationMs': durationMs,
    if (thumbUrl != null) 'thumbUrl': thumbUrl,
    if (viewOnce) 'viewOnce': true,
    // Horodatage client immédiat : une requête `orderBy('createdAt')`
    // n'inclut pas les documents dont le champ est encore null (cas de
    // `FieldValue.serverTimestamp()` tant que l'écriture n'est pas résolue),
    // ce qui bloquait l'affichage temps réel et faisait sauter l'ordre
    // chronologique à la résolution serveur.
    'createdAt': Timestamp.fromDate(createdAt),
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    if (replyToId != null)
      'replyTo': {
        'id': replyToId,
        'senderUid': replyToSenderUid,
        'text': replyToText,
      },
    if (statusRef != null) 'statusRef': statusRef!.toMap(),
  };

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      ChatMessage.fromMap(doc.id, doc.data()!);

  /// Décodage pur, sans Firestore : c'est ce que vérifient les tests
  /// d'aller-retour (`toMap` → `fromMap`) de chaque type de message.
  factory ChatMessage.fromMap(String id, Map<String, dynamic> d) {
    return ChatMessage(
      id: id,
      senderUid: d['senderUid'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => MessageType.text,
      ),
      content: d['content'] as String? ?? '',
      fileName: d['fileName'] as String?,
      durationMs: d['durationMs'] as int?,
      thumbUrl: d['thumbUrl'] as String?,
      viewOnce: d['viewOnce'] as bool? ?? false,
      viewOnceOpenedAt: (d['viewOnceOpenedAt'] as Timestamp?)?.toDate(),
      screenshotAt: (d['screenshotAt'] as Timestamp?)?.toDate(),
      // `createdAt` (serverTimestamp) est null le temps que l'écriture
      // soit confirmée : on se rabat sur l'horodatage client pour garder
      // un ordre stable, et `hasServerTimestamp` signale lequel des deux
      // a servi (voir le champ dans ChatController._rebuildMessages).
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ??
          (d['clientCreatedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      hasServerTimestamp: d['createdAt'] != null,
      readAt: (d['readAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      replyToId: (d['replyTo'] as Map<String, dynamic>?)?['id'] as String?,
      replyToSenderUid:
          (d['replyTo'] as Map<String, dynamic>?)?['senderUid'] as String?,
      replyToText: (d['replyTo'] as Map<String, dynamic>?)?['text'] as String?,
      statusRef: StatusRef.fromMap(d['statusRef'] as Map<String, dynamic>?),
      deleted: d['deleted'] as bool? ?? false,
      reactions: Map<String, String>.from(
        (d['reactions'] as Map<String, dynamic>?) ?? const {},
      ),
      hiddenFor: List<String>.from(d['hiddenFor'] ?? const []),
    );
  }
}

/// Regroupe les photos envoyées à la suite par une même personne, comme le
/// fait WhatsApp : plutôt qu'une colonne de vignettes de 220 px, elles
/// s'affichent en un seul album.
///
/// Chaque photo reste **un message à part entière** côté serveur : c'est ce
/// qui permet de renvoyer, citer ou supprimer une photo précise, et qu'un
/// envoi raté n'emporte pas les autres. Le regroupement est purement une
/// affaire d'affichage, calculée ici pour être vérifiable sans interface.
///
/// Ne sont réunis que des messages **contigus**, du même expéditeur, de
/// type image, déjà partis ([MessageDeliveryStatus.sent]), sans citation,
/// et espacés de moins de [window]. Une photo encore en cours d'envoi ou en
/// échec reste seule le temps qu'il faut : elle porte son propre état —
/// progression, échec, bouton de renvoi — qui n'aurait nulle part où
/// s'afficher dans un album. Elle rejoint le groupe une fois partie.
///
/// [maxPerAlbum] borne la taille d'un album : au-delà, un second album
/// commence, pour qu'une rafale de photos ne produise pas une grille
/// interminable.
List<List<ChatMessage>> groupChatMessages(
  List<ChatMessage> messages, {
  Duration window = const Duration(minutes: 2),
  int maxPerAlbum = 10,
}) {
  final groups = <List<ChatMessage>>[];
  for (final message in messages) {
    final current = groups.isEmpty ? null : groups.last;
    if (current != null &&
        current.length < maxPerAlbum &&
        _groupsWith(current.last, message, window)) {
      current.add(message);
    } else {
      groups.add([message]);
    }
  }
  return groups;
}

bool _groupsWith(ChatMessage previous, ChatMessage next, Duration window) {
  if (previous.type != MessageType.image || next.type != MessageType.image) {
    return false;
  }
  if (previous.senderUid != next.senderUid) return false;
  // Une photo à vue unique n'est pas une tuile : c'est un cachet à
  // ouvrir, avec son propre état. Noyée dans une mosaïque, elle n'aurait
  // ni son libellé ni sa zone d'appui — et l'ouvrir en ouvrirait
  // l'album entier.
  if (previous.viewOnce || next.viewOnce) return false;
  // Une photo supprimée n'a plus d'URL : dans une mosaïque, elle
  // afficherait une tuile brisée — et si c'était la première du groupe,
  // son « Message supprimé » masquerait tout l'album.
  if (previous.deleted || next.deleted) return false;
  if (previous.status != MessageDeliveryStatus.sent ||
      next.status != MessageDeliveryStatus.sent) {
    return false;
  }
  if (previous.isReply || next.isReply) return false;
  return next.createdAt.difference(previous.createdAt).abs() <= window;
}
