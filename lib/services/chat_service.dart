import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';

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
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      replyToId: replyToId,
      replyToSenderUid: replyToSenderUid,
      replyToText: replyToText,
      statusRef: statusRef,
    );

    // Un message rattaché à un statut s'annonce comme tel dans la liste
    // des conversations : « ❤️ A aimé votre statut » se comprend d'un
    // coup d'œil, là où un cœur seul laisserait perplexe.
    final lastMsgPreview = statusRef != null
        ? (statusRef.isLike
            ? '❤️ A aimé votre statut'
            : '💬 ${content.length > 70 ? '${content.substring(0, 70)}…' : content}')
        : switch (type) {
            MessageType.voice => '🎤 Message vocal',
            MessageType.image => '📷 Photo',
            MessageType.document => fileName ?? '📎 Document',
            MessageType.sticker => content,
            MessageType.text =>
              content.length > 80 ? '${content.substring(0, 80)}…' : content,
          };

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
            // Compteur dénormalisé par participant — affiché dans la liste
            // des conversations (badge façon WhatsApp). Écrit comme map
            // imbriquée, et non via la clé pointée `unreadCounts.$uid` :
            // contrairement à `update()`, `set()` ne lit pas le point comme
            // un chemin de champ et créait un champ de premier niveau
            // littéralement nommé « unreadCounts.<uid> ». Les règles le
            // voyaient donc dans `affectedKeys()` hors de la liste
            // autorisée → PERMISSION_DENIED, et `Conversation.fromDoc` ne
            // trouvait jamais la map qu'il lit. Avec `merge: true`, une map
            // imbriquée fusionne clé par clé : le compteur de l'autre
            // participant est préservé.
            'unreadCounts': {recipientUid: FieldValue.increment(1)},
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

    await _msgRef(conversationId).doc(message.id).update({
      'deleted': true,
      'content': '',
      'fileName': FieldValue.delete(),
      'durationMs': FieldValue.delete(),
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

    // Remise à zéro du badge : hors du batch, pour la même raison que dans
    // [sendMessage] — un refus sur le document `conversations` ne doit pas
    // emporter avec lui les accusés de lecture des messages.
    unawaited(
      clearUnread(conversationId, readerUid).catchError((Object e) {
        developer.log(
          'clearUnread failed for $conversationId',
          name: 'ChatService',
          error: e,
        );
      }),
    );

    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(_msgRef(conversationId).doc(id), {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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

  void markInFlight(String conversationId, ChatMessage message) {
    (_inFlight[conversationId] ??= {})[message.id] = message;
  }

  void clearInFlight(String conversationId, String messageId) {
    final pending = _inFlight[conversationId];
    if (pending == null) return;
    pending.remove(messageId);
    if (pending.isEmpty) _inFlight.remove(conversationId);
  }

  Future<String> uploadVoice(String filePath, String conversationId) async {
    final fileName = '${_uuid.v4()}.m4a';
    final ref = _storage.ref('chat/$conversationId/voice/$fileName');
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }

  Future<String> uploadImage(String filePath, String conversationId) async {
    final ext = filePath.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    final ref = _storage.ref('chat/$conversationId/images/$fileName');
    // Type MIME explicite : `putFile` n'en devine aucun côté Android, et
    // une pièce jointe servie en `application/octet-stream` est traitée
    // comme un fichier binaire (téléchargement) par tout ce qui n'est pas
    // l'app elle-même. ImagePicker recompresse en JPEG (voir
    // `ChatController.pickImage`).
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
    final ref = _storage.ref(
      'chat/$conversationId/docs/${_uuid.v4()}_$originalName',
    );
    await ref.putFile(File(filePath));
    return ref.getDownloadURL();
  }
}
