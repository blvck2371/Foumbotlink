import 'dart:convert';

import 'chat_message.dart';

/// Un média dont l'envoi n'est pas terminé, tel qu'il est gardé sur le
/// téléphone pour survivre à la fermeture de l'app.
///
/// Seuls les médias passent par ici : un texte ou un sticker est une
/// simple écriture Firestore, que le cache hors ligne de Firestore garde
/// déjà et renvoie au redémarrage. Un média, lui, doit d'abord monter vers
/// Storage — étape qui ne vivait qu'en mémoire : app fermée pendant
/// l'envoi, ou envoi raté puis app tuée, et la photo disparaissait sans un
/// mot.
class OutboxEntry {
  const OutboxEntry({
    required this.conversationId,
    required this.message,
    this.videoQuality,
  });

  final String conversationId;

  /// Le message tel qu'affiché dans la bulle locale : `content` est le
  /// chemin du fichier sur le téléphone, `thumbUrl` celui de la vignette
  /// d'une vidéo.
  final ChatMessage message;

  /// `standard` ou `hd` pour une vidéo, sinon `null`.
  final String? videoQuality;

  static bool isMedia(MessageType type) =>
      type != MessageType.text && type != MessageType.sticker;

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'id': message.id,
    'senderUid': message.senderUid,
    'type': message.type.name,
    'path': message.content,
    if (message.fileName != null) 'fileName': message.fileName,
    if (message.durationMs != null) 'durationMs': message.durationMs,
    if (message.thumbUrl != null) 'thumbPath': message.thumbUrl,
    if (message.viewOnce) 'viewOnce': true,
    'createdAt': message.createdAt.millisecondsSinceEpoch,
    if (message.expiresAt != null)
      'expiresAt': message.expiresAt!.millisecondsSinceEpoch,
    if (message.replyToId != null) 'replyToId': message.replyToId,
    if (message.replyToSenderUid != null)
      'replyToSenderUid': message.replyToSenderUid,
    if (message.replyToText != null) 'replyToText': message.replyToText,
    if (videoQuality != null) 'videoQuality': videoQuality,
  };

  /// Relit une entrée. Toujours en échec : relue au redémarrage, elle
  /// n'est par définition plus en cours d'envoi — c'est la flèche de
  /// renvoi qu'il faut montrer, pas un rond qui tourne pour rien.
  ///
  /// Renvoie `null` pour une entrée illisible ou d'un type inconnu.
  static OutboxEntry? fromJson(Map<String, dynamic> j) {
    final type = MessageType.values.where((t) => t.name == j['type']);
    final id = j['id'], conv = j['conversationId'], path = j['path'];
    if (type.isEmpty || !isMedia(type.first)) return null;
    if (id is! String || conv is! String || path is! String) return null;
    if (id.isEmpty || conv.isEmpty || path.isEmpty) return null;
    DateTime? at(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return OutboxEntry(
      conversationId: conv,
      videoQuality: j['videoQuality'] as String?,
      message: ChatMessage(
        id: id,
        senderUid: j['senderUid'] as String? ?? '',
        type: type.first,
        content: path,
        fileName: j['fileName'] as String?,
        durationMs: j['durationMs'] as int?,
        thumbUrl: j['thumbPath'] as String?,
        viewOnce: j['viewOnce'] as bool? ?? false,
        createdAt: at(j['createdAt']) ?? DateTime.now(),
        expiresAt: at(j['expiresAt']),
        replyToId: j['replyToId'] as String?,
        replyToSenderUid: j['replyToSenderUid'] as String?,
        replyToText: j['replyToText'] as String?,
        status: MessageDeliveryStatus.failed,
        hasServerTimestamp: false,
      ),
    );
  }

  static String encodeAll(Iterable<OutboxEntry> entries) =>
      jsonEncode([for (final e in entries) e.toJson()]);

  /// Tolérant : une sauvegarde abîmée (app tuée en pleine écriture, format
  /// d'une version future) ne doit jamais empêcher la discussion de
  /// s'ouvrir. Ce qui ne se relit pas est ignoré.
  static List<OutboxEntry> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) ?fromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }
}
