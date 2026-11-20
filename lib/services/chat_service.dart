import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/outbox_entry.dart';

/// Vidéo refusée avant même de partir, parce qu'elle dépasse le plafond
/// de [ChatService.maxVideoBytes].
///
/// Un type à part plutôt qu'un message brut : `_uploadAndSend` remonte
/// `toString()` tel quel dans l'alerte d'échec, et « Vidéo de 78 Mo »
/// se comprend là où un `unauthorized` de Storage n'apprend rien.
class ChatVideoTooLarge implements Exception {
  const ChatVideoTooLarge({required this.bytes, required this.maxBytes});

  final int bytes;
  final int maxBytes;

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  String get sizeLabel => '${_mb(bytes)} Mo';
  String get maxLabel => '${_mb(maxBytes)} Mo';

  @override
  String toString() =>
      'Vidéo de $sizeLabel : le maximum est $maxLabel. Filmez plus court, '
      'ou envoyez-la en document depuis un autre appareil.';
}

/// État affiché en direct à l'autre participant, façon WhatsApp — écrit
/// dans `conversations/{id}/typing/{uid}` (voir [ChatService.setActivity]
/// et [ChatService.watchActivity]).
enum ChatActivity { idle, typing, recording }

/// Au-delà de cette ancienneté, l'activité reçue d'un participant est
/// traitée comme [ChatActivity.idle] — filet de sécurité si son app a
/// planté ou perdu la connexion en pleine saisie, sans avoir eu le temps
/// d'écrire « idle ». Doit rester supérieure à l'intervalle de
/// rafraîchissement côté émetteur (voir `_activityHeartbeatInterval`).
/// Partagée par l'en-tête de la discussion et par la liste des
/// conversations, qui doivent afficher/masquer l'indicateur ensemble.
const chatActivityStaleAfter = Duration(seconds: 8);

class ChatService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> get _convRef =>
      _db.collection('conversations');

  CollectionReference<Map<String, dynamic>> _msgRef(String convId) =>
      _convRef.doc(convId).collection('messages');

  /// Génère à l'avance l'id du prochain message d'une conversation, pour
  /// que l'appelant puisse afficher une bulle optimiste avec ce même id
  /// avant même que [sendMessage] n'ait terminé (façon WhatsApp) — quand
  /// le document Firestore arrive via [watchMessages], il porte le même
  /// id et remplace naturellement la version locale en attente.
  String newMessageId(String conversationId) =>
      _msgRef(conversationId).doc().id;

  /// Renvoie la conversation et indique si elle vient d'être **créée** —
  /// seul cas où les écoutes déjà ouvertes sur ses sous-collections
  /// doivent être relancées (voir `ChatController._ensureConversation`).
  Future<({Conversation conversation, bool created})> getOrCreateConversation(
    String myUid,
    String targetUid,
  ) async {
    final convId = Conversation.buildId(myUid, targetUid);
    final ref = _convRef.doc(convId);

    // Cache local d'abord : une conversation déjà ouverte une fois est
    // connue hors ligne. Un `get()` normal part toujours vers le serveur
    // et faisait attendre l'écran de discussion un aller-retour réseau
    // complet avant d'être considéré comme prêt.
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        return (
          conversation: Conversation.fromDoc(cached, myUid: myUid),
          created: false,
        );
      }
    } on FirebaseException catch (_) {
      // Pas encore en cache : on interroge le serveur juste en dessous.
    }

    final doc = await ref.get();
    if (doc.exists) {
      return (
        conversation: Conversation.fromDoc(doc, myUid: myUid),
        created: false,
      );
    }

    await ref.set({
      'participants': [myUid, targetUid],
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return (
      conversation: Conversation(
        id: convId,
        participants: [myUid, targetUid],
        createdAt: DateTime.now(),
      ),
      created: true,
    );
  }

  Future<void> sendMessage({
    required String conversationId,
    required String messageId,
    required String senderUid,
    required String recipientUid,
    required MessageType type,
    required String content,
    String? fileName,
    int? durationMs,
    String? thumbUrl,
    bool viewOnce = false,
    int? ephemeralSeconds,
    String? replyToId,
    String? replyToSenderUid,
    String? replyToText,
    StatusRef? statusRef,
  }) async {
    DateTime? expiresAt;
    if (ephemeralSeconds != null && ephemeralSeconds > 0) {
      expiresAt = DateTime.now().add(Duration(seconds: ephemeralSeconds));
    }

    final msg = ChatMessage(
      id: messageId,
      senderUid: senderUid,
      type: type,
      content: content,
      fileName: fileName,
      durationMs: durationMs,
      thumbUrl: thumbUrl,
      viewOnce: viewOnce,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      replyToId: replyToId,
      replyToSenderUid: replyToSenderUid,
      replyToText: replyToText,
      statusRef: statusRef,
    );

    // Un message rattaché à un statut s'annonce comme tel (« ❤️ A aimé
    // votre statut »), un message éphémère ou à vue unique ne livre pas son
    // contenu : voir ChatMessage.listPreview.
    final lastMsgPreview = msg.listPreview;

    // Métadonnées de la liste des conversations (aperçu + badge non lu) :
    // envoyées en parallèle et sans `await`, hors du chemin critique. Elles
    // partageaient avant un `WriteBatch` avec le message lui-même ; un batch
    // étant tout-ou-rien, un refus des règles sur le document `conversations`
    // (ex. `unreadCounts` pas encore autorisé côté serveur) annulait aussi
    // l'écriture du message — la bulle s'affichait puis disparaissait du fil.
    // La discussion doit survivre à l'échec d'un simple aperçu.
    unawaited(
      _convRef
          .doc(conversationId)
          .set({
            'lastMessage': lastMsgPreview,
            'lastMessageType': type.name,
            // Même logique que `createdAt` sur le message : un timestamp
            // client immédiat pour que la conversation remonte en tête de
            // liste sans attendre la résolution serveur.
            'lastMessageAt': Timestamp.fromDate(DateTime.now()),
            'lastMessageSenderUid': senderUid,
            // Le badge non lu du destinataire n'est plus écrit ici : le
            // serveur le compte (`onMessageCreated`), et les règles
            // refusent désormais qu'un participant touche à celui de
            // l'autre.
          }, SetOptions(merge: true))
          .catchError((Object e) {
            developer.log(
              'conversation metadata update failed for $conversationId',
              name: 'ChatService',
              error: e,
            );
          }),
    );

    // Seule écriture dont dépend l'affichage du message, donc seule attendue.
    await _msgRef(conversationId).doc(messageId).set(msg.toMap());
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchConversations({
    required String myUid,
    required void Function(List<Conversation>) onData,
    void Function(Object error)? onError,
  }) {
    return _convRef
        .where('participants', arrayContains: myUid)
        .orderBy('lastMessageAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
          onData(
            snap.docs
                .map((doc) => Conversation.fromDoc(doc, myUid: myUid))
                .toList(),
          );
        }, onError: onError ?? (_) {});
  }

  /// Les conversations de [uid], lues une fois — de la plus récente à la
  /// plus ancienne. Sert au choix d'une destination pour un transfert :
  /// une écoute temps réel serait inutile pour une feuille qu'on ouvre et
  /// referme.
  ///
  /// Les noms et photos des interlocuteurs ne sont pas dans ces documents
  /// (`ConversationsController` les hydrate depuis les profils) : la
  /// feuille de transfert les résout de son côté.
  Future<List<Conversation>> recentConversations(
    String uid, {
    int limit = 30,
  }) async {
    final snap = await _convRef
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => Conversation.fromDoc(d, myUid: uid)).toList();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMessages({
    required String conversationId,
    required void Function(List<ChatMessage>) onData,
    void Function(Object error)? onError,
    int limit = 50,
  }) {
    return _msgRef(conversationId)
        .orderBy('createdAt', descending: false)
        .limitToLast(limit)
        .snapshots()
        .listen(
          (snap) {
            final messages = snap.docs
                .map(ChatMessage.fromDoc)
                .where((m) => !m.isExpired)
                .toList();
            onData(messages);
          },
          onError:
              onError ??
              (e) {
                developer.log(
                  'watchMessages error',
                  name: 'ChatService',
                  error: e,
                );
              },
        );
  }

  /// Page d'historique **antérieure** à [before], du plus ancien au plus
  /// récent.
  ///
  /// L'écoute temps réel ([watchMessages]) ne porte que sur les derniers
  /// messages : au-delà de sa fenêtre, la conversation était simplement
  /// inatteignable depuis l'app. Cette lecture ponctuelle remonte le fil,
  /// page par page, sans élargir l'abonnement — un `limitToLast` qui
  /// grandirait rechargerait toute la discussion à chaque nouveau message.
  ///
  /// Renvoie une liste vide quand il n'y a plus rien avant [before].
  Future<List<ChatMessage>> loadOlderMessages({
    required String conversationId,
    required DateTime before,
    int limit = 50,
  }) async {
    final snap = await _msgRef(conversationId)
        .orderBy('createdAt', descending: true)
        .where('createdAt', isLessThan: Timestamp.fromDate(before))
        .limit(limit)
        .get();

    return snap.docs
        .map(ChatMessage.fromDoc)
        .where((m) => !m.isExpired)
        .toList()
        .reversed
        .toList();
  }

  /// « Supprimer pour moi » : le message disparaît de l'affichage de
  /// [uid] seul, et reste intact pour l'autre participant.
  ///
  /// L'appartenance est marquée sur le message plutôt que dans une liste
  /// personnelle à part : elle arrive ainsi avec le message, sans lecture
  /// supplémentaire à chaque ouverture de discussion. Les règles
  /// n'autorisent chacun qu'à s'ajouter ou se retirer lui-même.
  Future<void> hideMessageForMe({
    required String conversationId,
    required String messageId,
    required String uid,
  }) async {
    await _msgRef(conversationId).doc(messageId).update({
      'hiddenFor': FieldValue.arrayUnion([uid]),
    });
  }

  /// Suppression douce : le document reste, vidé de son contenu.
  ///
  /// L'effacer pour de bon laisserait un trou dans les réponses qui le
  /// citent et dans l'aperçu de la conversation. Le fichier joint, lui,
  /// est bel et bien retiré de Storage — c'est tout l'intérêt de pouvoir
  /// Marque un message à vue unique comme ouvert, et lui retire son
  /// contenu.
  ///
  /// Les deux vont ensemble mais ne protègent pas la même chose :
  /// `viewOnceOpenedAt` interdit une seconde ouverture — c'est lui que
  /// l'app regarde — tandis que vider `content` retire l'URL de la base,
  /// pour qu'elle ne soit plus lisible par qui saurait aller l'y chercher.
  ///
  /// Le fichier lui-même part plus tard ([deleteViewOnceFile]), une fois
  /// la visionneuse refermée : le supprimer maintenant couperait l'image
  /// sous les yeux de qui vient de l'ouvrir.
  Future<void> consumeViewOnce({
    required String conversationId,
    required String messageId,
  }) async {
    await _msgRef(conversationId).doc(messageId).update({
      'viewOnceOpenedAt': FieldValue.serverTimestamp(),
      'content': '',
      'thumbUrl': FieldValue.delete(),
    });
  }

  /// Signale que le destinataire a capturé l'écran pendant l'affichage.
  ///
  /// Écrit une fois, par celui qui a capturé. On ne peut pas l'empêcher —
  /// iOS ne prévient qu'après coup — mais l'expéditeur a le droit de le
  /// savoir : c'est la seule chose qu'une détection puisse apporter.
  ///
  /// L'échec est avalé : une capture non signalée reste préférable à une
  /// alerte d'erreur en pleine consultation.
  Future<void> reportScreenshot({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await _msgRef(conversationId).doc(messageId).update({
        'screenshotAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      developer.log(
        'Signalement de capture d’écran',
        name: 'ChatService',
        error: e,
      );
    }
  }

  /// Retire de Storage le fichier d'un message à vue unique déjà consommé.
  ///
  /// Au mieux : si l'app meurt entre l'ouverture et la fermeture, le
  /// fichier reste — mais le message, lui, est déjà marqué ouvert et ne
  /// se rouvrira pas. Le ménage manqué coûte de l'espace, pas le secret.
  Future<void> deleteViewOnceFile(String url) async {
    if (!url.startsWith('http')) return;
    try {
      await _storage.refFromURL(url).delete();
    } on FirebaseException catch (e) {
      developer.log(
        'Ménage du fichier à vue unique',
        name: 'ChatService',
        error: e,
      );
    }
  }

  /// supprimer une photo envoyée par erreur.
  Future<void> deleteMessage({
    required String conversationId,
    required ChatMessage message,
  }) async {
    // Le fichier joint part d'abord : une fois `content` vidé, plus rien
    // ne dit où il se trouvait.
    if (message.type != MessageType.text &&
        message.type != MessageType.sticker &&
        message.content.startsWith('http')) {
      try {
        await _storage.refFromURL(message.content).delete();
      } on FirebaseException catch (e) {
        // Fichier déjà absent ou droits insuffisants : on continue, le
        // message doit disparaître de la conversation de toute façon.
        developer.log(
          'Suppression du fichier joint',
          name: 'ChatService',
          error: e,
        );
      }
    }

    // La vignette d'une vidéo est un second fichier : la laisser derrière
    // ferait de l'espace occupé par un message qui n'existe plus.
    final thumb = message.thumbUrl;
    if (thumb != null && thumb.startsWith('http')) {
      try {
        await _storage.refFromURL(thumb).delete();
      } on FirebaseException catch (e) {
        developer.log(
          'Suppression de la vignette',
          name: 'ChatService',
          error: e,
        );
      }
    }

    await _msgRef(conversationId).doc(message.id).update({
      'deleted': true,
      'content': '',
      'fileName': FieldValue.delete(),
      'durationMs': FieldValue.delete(),
      'thumbUrl': FieldValue.delete(),
      'reactions': <String, String>{},
    });
  }

  /// Pose ou retire la réaction de [uid]. Une seule par personne : la
  /// reposer avec le même emoji l'enlève, avec un autre la remplace.
  Future<void> setReaction({
    required String conversationId,
    required String messageId,
    required String uid,
    required String? emoji,
  }) async {
    await _msgRef(
      conversationId,
    ).doc(messageId).update({'reactions.$uid': emoji ?? FieldValue.delete()});
  }

  Future<void> markAsRead(
    String conversationId,
    List<String> messageIds,
    String readerUid,
  ) async {
    if (messageIds.isEmpty) return;

    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(_msgRef(conversationId).doc(id), {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // Remise à zéro du badge **après** les accusés de lecture, et hors du
    // batch : un refus sur le document `conversations` ne doit pas
    // emporter les accusés. L'ordre compte — le serveur ne compte pas un
    // message déjà marqué lu (voir `countUnread`), si bien qu'un message
    // arrivé discussion ouverte ne laisse pas de « 1 » derrière lui.
    unawaited(
      clearUnread(conversationId, readerUid).catchError((Object e) {
        developer.log(
          'clearUnread failed for $conversationId',
          name: 'ChatService',
          error: e,
        );
      }),
    );
  }

  /// Remet à zéro le badge non lu dès l'ouverture d'une discussion.
  /// N'utilise que `update` sur un document existant : un `set(merge)`
  /// sur une conversation pas encore créée déclenchait une `create`
  /// sans `participants` → permission refusée (voir ChatController.onInit).
  Future<void> clearUnread(String conversationId, String readerUid) async {
    final ref = _convRef.doc(conversationId);
    final snap = await ref.get();
    if (!snap.exists) return;
    await ref.update({'unreadCounts.$readerUid': 0});
  }

  Future<void> setEphemeral(String conversationId, int? seconds) async {
    await _convRef.doc(conversationId).set({
      'ephemeralSeconds': seconds,
    }, SetOptions(merge: true));
  }

  // -----------------------------------------------------------------------
  // Indicateur "en train d'écrire" / "en train d'enregistrer"
  // -----------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _activityRef(
    String conversationId,
    String uid,
  ) => _convRef.doc(conversationId).collection('typing').doc(uid);

  Future<void> setActivity(
    String conversationId,
    String uid,
    ChatActivity activity,
  ) async {
    await _activityRef(
      conversationId,
      uid,
    ).set({'state': activity.name, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Suit l'activité d'un participant en direct. La péremption d'un signal
  /// est calculée par l'appelant à partir de **l'instant de réception** et
  /// non du `updatedAt` serveur : l'horloge du téléphone qui lit peut être
  /// décalée de plusieurs minutes par rapport au serveur, ce qui figeait
  /// l'indicateur (toujours périmé, ou jamais). Le heartbeat de l'émetteur
  /// garantit un snapshot régulier tant qu'il écrit — voir
  /// [chatActivityStaleAfter].
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> watchActivity({
    required String conversationId,
    required String uid,
    required void Function(ChatActivity activity) onData,
  }) {
    return _activityRef(conversationId, uid).snapshots().listen((doc) {
      if (!doc.exists) {
        onData(ChatActivity.idle);
        return;
      }
      final activity = ChatActivity.values.firstWhere(
        (s) => s.name == doc.data()!['state'],
        orElse: () => ChatActivity.idle,
      );
      onData(activity);
    }, onError: (_) {});
  }

  // -----------------------------------------------------------------------
  // Envois de médias encore en vol
  // -----------------------------------------------------------------------

  /// Les messages dont l'envoi (upload + écriture) n'est pas terminé, par
  /// conversation.
  ///
  /// Ils vivaient dans le contrôleur de l'écran, détruit dès qu'on quitte
  /// la discussion : partir pendant l'envoi d'une photo la faisait
  /// disparaître de l'affichage sans rien dire, alors que l'envoi, lui,
  /// continuait. Le service est permanent (`Get.put(..., permanent: true)`),
  /// il survit à l'écran : la bulle « en cours d'envoi » se retrouve donc
  /// telle quelle en revenant.
  final _inFlight = <String, Map<String, ChatMessage>>{};

  Map<String, ChatMessage> inFlightFor(String conversationId) =>
      Map.unmodifiable(_inFlight[conversationId] ?? const {});

  void markInFlight(
    String conversationId,
    ChatMessage message, {
    String? videoQuality,
  }) {
    (_inFlight[conversationId] ??= {})[message.id] = message;
    if (videoQuality != null) _outboxQuality[message.id] = videoQuality;
    if (OutboxEntry.isMedia(message.type)) _saveOutbox();
  }

  void clearInFlight(String conversationId, String messageId) {
    final pending = _inFlight[conversationId];
    if (pending == null) return;
    final removed = pending.remove(messageId);
    if (pending.isEmpty) _inFlight.remove(conversationId);
    _outboxQuality.remove(messageId);
    if (removed != null && OutboxEntry.isMedia(removed.type)) _saveOutbox();
  }

  // -----------------------------------------------------------------------
  // File d'envoi persistante (médias)
  // -----------------------------------------------------------------------
  //
  // Les envois de médias survivent à la fermeture de l'app : la file est
  // recopiée sur le téléphone à chaque changement, et les fichiers mis à
  // l'abri dans un dossier privé de l'app — le système vide sans prévenir
  // les dossiers temporaires où la galerie et le micro les déposent.

  static const _outboxKey = 'chat_outbox_v1';
  final _outboxQuality = <String, String>{};
  Future<void> _outboxWrites = Future.value();
  Future<void>? _outboxRestore;

  /// Qualité choisie pour une vidéo de la file (`standard` / `hd`).
  String? outboxQualityFor(String messageId) => _outboxQuality[messageId];

  /// Entrées d'un autre compte connecté auparavant sur ce téléphone :
  /// conservées telles quelles, pour qu'il les retrouve à sa reconnexion.
  final _foreignOutbox = <OutboxEntry>[];

  void _saveOutbox() {
    final entries = [
      for (final e in _inFlight.entries)
        for (final m in e.value.values)
          if (OutboxEntry.isMedia(m.type))
            OutboxEntry(
              conversationId: e.key,
              message: m,
              videoQuality: _outboxQuality[m.id],
            ),
      ..._foreignOutbox,
    ];
    final raw = OutboxEntry.encodeAll(entries);
    // Écritures en file : deux sauvegardes rapprochées ne se croisent pas,
    // la dernière l'emporte toujours.
    _outboxWrites = _outboxWrites.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_outboxKey, raw);
      } catch (e) {
        developer.log('Sauvegarde de la file', name: 'ChatService', error: e);
      }
    });
  }

  /// Recharge, une fois par lancement, les envois interrompus de [myUid].
  /// Ils reviennent en échec, prêts à être renvoyés. Ceux dont le fichier
  /// a disparu sont abandonnés — il n'y a plus rien à envoyer.
  Future<void> restoreOutbox(String myUid) =>
      _outboxRestore ??= _restoreOutbox(myUid);

  Future<void> _restoreOutbox(String myUid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = OutboxEntry.decodeAll(prefs.getString(_outboxKey));
      for (final entry in entries) {
        final m = entry.message;
        if (m.senderUid != myUid) continue;
        if (_inFlight[entry.conversationId]?.containsKey(m.id) ?? false) {
          continue; // déjà en mémoire : envoi en cours dans ce lancement
        }
        if (!await File(m.content).exists()) continue;
        (_inFlight[entry.conversationId] ??= {})[m.id] = m;
        final q = entry.videoQuality;
        if (q != null) _outboxQuality[m.id] = q;
      }
      // Les entrées d'autres comptes restent sauvegardées pour eux.
      _foreignOutbox
        ..clear()
        ..addAll(entries.where((e) => e.message.senderUid != myUid));
      _saveOutbox();
      await _purgeOrphanFiles({
        for (final e in entries) ...[e.message.content, ?e.message.thumbUrl],
        for (final conv in _inFlight.values)
          for (final m in conv.values) ...[m.content, ?m.thumbUrl],
      });
    } catch (e) {
      developer.log('Relecture de la file', name: 'ChatService', error: e);
    }
  }

  Future<Directory> _outboxDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/chat_outbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Met le fichier à l'abri dans le dossier privé de la file et renvoie
  /// le nouveau chemin. En cas d'échec de la copie, l'original sert tel
  /// quel : l'envoi immédiat marche toujours, seule la reprise après
  /// fermeture est perdue.
  Future<String> keepForOutbox(
    String path,
    String messageId, {
    String suffix = '',
  }) async {
    try {
      final dir = await _outboxDir();
      if (path.startsWith(dir.path)) return path;
      final ext = ChatAttachment.extensionOf(path);
      final dest =
          '${dir.path}/$messageId$suffix${ext.isEmpty ? '' : '.$ext'}';
      await File(path).copy(dest);
      return dest;
    } catch (e) {
      developer.log('Copie pour la file', name: 'ChatService', error: e);
      return path;
    }
  }

  /// Supprime une copie de la file. Ne touche jamais un fichier situé
  /// ailleurs : l'original appartient à la galerie de la personne.
  Future<void> releaseOutboxFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final dir = await _outboxDir();
      if (!path.startsWith(dir.path)) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Retire du dossier de la file les fichiers qu'aucun envoi n'attend
  /// plus (envoi abouti juste avant une fermeture, par exemple).
  Future<void> _purgeOrphanFiles(Set<String> referenced) async {
    final dir = await _outboxDir();
    await for (final f in dir.list()) {
      if (f is File && !referenced.contains(f.path)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Refuse avant l'envoi un fichier que la règle Storage refuserait
  /// après l'avoir laissé monter en entier.
  static Future<File> _checkedFile(
    String filePath, {
    required String what,
    int maxBytes = ChatAttachment.maxFileBytes,
  }) async {
    final file = File(filePath);
    final bytes = await file.length();
    if (bytes >= maxBytes) {
      throw ChatFileTooLarge(bytes: bytes, maxBytes: maxBytes, what: what);
    }
    return file;
  }

  Future<String> uploadVoice(String filePath, String conversationId) async {
    final file = await _checkedFile(filePath, what: 'Message vocal');
    final ref = _storage.ref('chat/$conversationId/voice/${_uuid.v4()}.m4a');
    // Sans type, le vocal était servi en `application/octet-stream` : le
    // lecteur iOS (AVPlayer) refuse alors parfois de le lire en flux.
    await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'audio/mp4',
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    return ref.getDownloadURL();
  }

  Future<String> uploadImage(String filePath, String conversationId) async {
    final file = await _checkedFile(filePath, what: 'Photo');
    final ext = ChatAttachment.extensionOf(filePath);
    final fileName = '${_uuid.v4()}.${ext.isEmpty ? 'jpg' : ext}';
    final ref = _storage.ref('chat/$conversationId/images/$fileName');
    // Type MIME explicite : `putFile` n'en devine aucun côté Android, et
    // une pièce jointe servie en `application/octet-stream` est traitée
    // comme un fichier binaire. Le type suit l'extension : le sélecteur
    // recompresse en JPEG, mais une capture d'écran reste en PNG.
    await ref.putFile(
      file,
      SettableMetadata(
        contentType: ChatAttachment.imageContentTypeFor(filePath),
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    return ref.getDownloadURL();
  }

  /// Plafond d'une vidéo envoyée en discussion. Aligné sur celui des
  /// statuts (`StatusService.maxVideoBytes`) et sur la règle Storage : au
  /// même endroit, un seul chiffre à retenir. Les autres pièces jointes
  /// restent à 20 Mo — c'est déjà beaucoup pour une photo ou un document,
  /// et une vidéo est le seul fichier qui pèse légitimement plus lourd.
  static const maxVideoBytes = ChatAttachment.maxVideoBytes;

  /// Le type réel du fichier, pas un type supposé : sur iOS, la galerie
  /// rend le plus souvent un `.mov` (QuickTime). L'annoncer en `video/mp4`
  /// passerait la règle Storage, mais tromperait tout ce qui lit l'objet
  /// ensuite — navigateur, CDN, lecteur. Même raisonnement que
  /// `StatusService._videoMetadataFor`.
  static SettableMetadata _videoMetadataFor(String path) {
    final type = switch (path.toLowerCase().split('.').last) {
      'mov' || 'qt' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'webm' => 'video/webm',
      _ => 'video/mp4',
    };
    return SettableMetadata(
      contentType: type,
      cacheControl: 'public, max-age=31536000, immutable',
    );
  }

  /// Vidéo de discussion. La taille est vérifiée **avant** de commencer
  /// l'envoi : la règle Storage refuserait de toute façon, mais après
  /// avoir fait grimper tout le fichier sur le réseau de la personne, et
  /// avec un « unauthorized » qui ne dit pas pourquoi.
  Future<String> uploadVideo(
    String filePath,
    String conversationId, {
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    final bytes = await file.length();
    if (bytes >= maxVideoBytes) {
      throw ChatVideoTooLarge(bytes: bytes, maxBytes: maxVideoBytes);
    }
    // L'extension de l'original est conservée : un `.mov` stocké sous
    // `.mp4` se lirait mal côté Android.
    final extension = filePath.toLowerCase().split('.').last;
    final safeExtension = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension)
        ? extension
        : 'mp4';
    final ref = _storage.ref(
      'chat/$conversationId/videos/${_uuid.v4()}.$safeExtension',
    );
    final task = ref.putFile(file, _videoMetadataFor(filePath));
    // Une vidéo met de longues secondes à monter sur un réseau mobile :
    // sans progression, la bulle semble figée.
    final sub = onProgress == null
        ? null
        : task.snapshotEvents.listen((snap) {
            if (snap.totalBytes > 0) {
              onProgress(snap.bytesTransferred / snap.totalBytes);
            }
          }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub?.cancel();
    }
    return ref.getDownloadURL();
  }

  /// Vignette d'une vidéo. Une image parmi d'autres côté Storage : même
  /// type, même cache, même règle de taille que les photos.
  Future<String> uploadVideoThumb(
    String filePath,
    String conversationId,
  ) async {
    final ref = _storage.ref(
      'chat/$conversationId/videos/${_uuid.v4()}_thumb.jpg',
    );
    await ref.putFile(
      File(filePath),
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    return ref.getDownloadURL();
  }

  Future<String> uploadDocument(
    String filePath,
    String conversationId,
    String originalName,
  ) async {
    final file = await _checkedFile(filePath, what: 'Document');
    // Le nom d'origine reste dans le message (`fileName`) ; le chemin, lui,
    // n'en garde qu'une version sûre — un `#` ou un `?` y cassait l'URL.
    final ref = _storage.ref(
      'chat/$conversationId/docs/${_uuid.v4()}_'
      '${ChatAttachment.safeStorageName(originalName)}',
    );
    // Type réel et nom d'origine : sans eux, le téléphone d'en face
    // recevait un fichier binaire anonyme au lieu d'un PDF qu'il sait
    // ouvrir.
    await ref.putFile(
      file,
      SettableMetadata(
        contentType: ChatAttachment.contentTypeFor(originalName),
        contentDisposition: ChatAttachment.contentDispositionFor(originalName),
        cacheControl: 'private, max-age=31536000',
      ),
    );
    return ref.getDownloadURL();
  }
}
