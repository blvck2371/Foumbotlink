import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/user_status.dart';
import 'chat_service.dart';

/// Média trop lourd pour un statut, constaté **avant** l'envoi.
///
/// Sans cette vérification, un fichier hors plafond partait sur le réseau
/// pendant une minute pour finir refusé par les règles Storage, avec pour
/// seul indice un « unauthorized » indistinct d'un problème de droits.
class StatusMediaTooLarge implements Exception {
  const StatusMediaTooLarge({required this.bytes, required this.maxBytes});

  final int bytes;
  final int maxBytes;

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  String get sizeLabel => '${_mb(bytes)} Mo';
  String get maxLabel => '${_mb(maxBytes)} Mo';

  @override
  String toString() => 'Média de $sizeLabel, maximum $maxLabel';
}

/// Écoute groupée des statuts de plusieurs comptes.
///
/// Firestore plafonne un `whereIn` à trente valeurs : suivre davantage de
/// monde demande plusieurs requêtes, donc plusieurs abonnements à refermer
/// ensemble. Cet objet évite à l'appelant d'avoir à en tenir la liste.
class StatusFeedSubscription {
  const StatusFeedSubscription(this._subs);

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs;

  Future<void> cancel() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
  }
}

/// Statuts éphémères : publication, lecture des statuts encore vivants,
/// enregistrement des vues.
///
/// Un statut vit dans `statuses/{statusId}`, ses spectateurs dans
/// `statuses/{statusId}/views/{uid}`, et chacun garde le miroir personnel
/// de ce qu'il a vu dans `users/{uid}/statusViews/{statusId}` — même
/// découpage que les « j'aime » du fil, et pour la même raison : savoir ce
/// que *j'ai* vu tient en une requête, alors que lire la liste des
/// spectateurs de chaque statut en coûterait une par statut affiché.
class StatusService {
  /// Plafonds, tenus identiques à ceux de `storage.rules` : les vérifier
  /// ici sert à prévenir tôt et clairement, la règle serveur restant la
  /// seule autorité.
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxVideoBytes = 60 * 1024 * 1024;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _statusesRef =>
      _db.collection('statuses');

  CollectionReference<Map<String, dynamic>> _viewsRef(String statusId) =>
      _statusesRef.doc(statusId).collection('views');

  CollectionReference<Map<String, dynamic>> _myViewsRef(String uid) =>
      _db.collection('users').doc(uid).collection('statusViews');

  /// Un document par personne ayant aimé le statut — même découpage que
  /// les « j'aime » du fil : c'est *la* source de vérité, le compteur du
  /// document n'en étant que le résumé.
  CollectionReference<Map<String, dynamic>> _likesRef(String statusId) =>
      _statusesRef.doc(statusId).collection('likes');

  /// Miroir personnel `users/{uid}/statusLikes/{statusId}` : savoir ce que
  /// *j'ai* aimé tient en une requête, là où interroger chaque statut en
  /// coûterait une par statut affiché.
  CollectionReference<Map<String, dynamic>> _myLikesRef(String uid) =>
      _db.collection('users').doc(uid).collection('statusLikes');

  /// Métadonnées explicites, obligatoires : sans type MIME, l'objet arrive
  /// en `application/octet-stream` et la règle Storage — qui n'accepte que
  /// `image/*` ou `video/*` — refuse l'envoi (voir
  /// `FeedService._imageMetadata`).
  ///
  /// Le cache est court (24 h) : c'est exactement la durée de vie d'un
  /// statut, inutile de le garder plus longtemps.
  static const _cacheControl = 'public, max-age=86400';

  static final _imageMetadata = SettableMetadata(
    contentType: 'image/jpeg',
    cacheControl: _cacheControl,
  );

  /// Le type réel du fichier, pas un type supposé : sur iOS, la galerie
  /// rend le plus souvent un `.mov` (QuickTime). L'annoncer en `video/mp4`
  /// passerait la règle Storage, mais tromperait tout ce qui lit l'objet
  /// ensuite — navigateur, CDN, lecteur.
  static SettableMetadata _videoMetadataFor(String path) {
    final extension = path.toLowerCase().split('.').last;
    final type = switch (extension) {
      'mov' || 'qt' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'webm' => 'video/webm',
      _ => 'video/mp4',
    };
    return SettableMetadata(contentType: type, cacheControl: _cacheControl);
  }

  // -----------------------------------------------------------------------
  // Lecture
  // -----------------------------------------------------------------------

  /// Les statuts encore vivants de [uid], du plus ancien au plus récent —
  /// l'ordre dans lequel on les regarde.
  ///
  /// Le filtre porte sur `expiresAt` et non sur `createdAt` : c'est la
  /// borne que le document porte lui-même, donc la même que celle qu'emploie
  /// le ménage serveur. Un statut périmé que la purge n'aurait pas encore
  /// ramassé n'est pas renvoyé pour autant.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchUserStatuses({
    required String uid,
    required void Function(List<UserStatus>) onData,
    Set<String> viewedIds = const {},
    Set<String> likedIds = const {},
    void Function(Object error)? onError,
    bool includeHidden = false,
  }) {
    return _statusesRef
        .where('authorUid', isEqualTo: uid)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt')
        .limit(30)
        .snapshots()
        .listen(
          (snap) => onData(
            snap.docs
                .map(
                  (doc) => _fromDoc(
                    doc,
                    viewedIds.contains(doc.id),
                    likedByMe: likedIds.contains(doc.id),
                  ),
                )
                .where((status) => !status.isExpired)
                .where((status) => includeHidden || !status.hidden)
                .toList(),
          ),
          onError: (Object e) => onError?.call(e),
        );
  }

  /// Nombre maximal de valeurs acceptées par un `whereIn` Firestore : la
  /// liste des abonnements est découpée en autant d'écoutes.
  static const _whereInChunkSize = 30;

  /// Les statuts encore vivants des comptes suivis, tous auteurs
  /// confondus.
  ///
  /// C'est ce qui alimente la barre de statuts de l'accueil. On ne
  /// s'abonne qu'à ce que la personne suit : un statut n'est pas une
  /// publication du fil, il s'adresse à ceux qu'on a choisi de suivre.
  ///
  /// Au-delà de [_whereInChunkSize] abonnements, Firestore refuse un
  /// `whereIn` unique : on ouvre alors une écoute par tranche et on
  /// recolle les résultats à chaque arrivée. D'où l'objet renvoyé plutôt
  /// qu'un `StreamSubscription` — il y en a potentiellement plusieurs à
  /// refermer ensemble.
  StatusFeedSubscription watchFollowedStatuses({
    required Iterable<String> followingUids,
    required void Function(List<UserStatus>) onData,
    Set<String> viewedIds = const {},
    Set<String> likedIds = const {},
    void Function(Object error)? onError,
  }) {
    final uids = followingUids.toSet().toList();
    if (uids.isEmpty) {
      onData(const []);
      return const StatusFeedSubscription([]);
    }

    // Chaque tranche garde son dernier résultat connu : sans ça, la
    // réponse d'une tranche effacerait les statuts des autres à chaque
    // rafraîchissement.
    final perChunk = <int, List<UserStatus>>{};
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void publish() {
      final all = [for (final chunk in perChunk.values) ...chunk]
          .where((status) => !status.isExpired && !status.hidden)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      onData(all);
    }

    for (var i = 0; i < uids.length; i += _whereInChunkSize) {
      final index = i;
      final chunk = uids.sublist(
        i,
        i + _whereInChunkSize > uids.length ? uids.length : i + _whereInChunkSize,
      );
      subs.add(
        _statusesRef
            .where('authorUid', whereIn: chunk)
            .where('expiresAt', isGreaterThan: Timestamp.now())
            .orderBy('expiresAt')
            .limit(200)
            .snapshots()
            .listen(
              (snap) {
                perChunk[index] = snap.docs
                    .map(
                      (doc) => _fromDoc(
                        doc,
                        viewedIds.contains(doc.id),
                        likedByMe: likedIds.contains(doc.id),
                      ),
                    )
                    .toList();
                publish();
              },
              onError: (Object e) => onError?.call(e),
            ),
      );
    }

    return StatusFeedSubscription(subs);
  }

  /// Les statuts que [uid] a déjà vus, en une requête sur son miroir
  /// personnel. Borné : au-delà, un vieux statut réapparaîtrait comme non
  /// vu — sans conséquence, il aura de toute façon expiré.
  Future<Set<String>> myViewedStatusIds(String uid, {int limit = 500}) async {
    final snap = await _myViewsRef(
      uid,
    ).orderBy('viewedAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Qui a regardé le statut, du plus récent au plus ancien. Les règles
  /// réservent cette lecture à l'auteur.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchViewers({
    required String statusId,
    required void Function(List<StatusViewer>) onData,
    void Function(Object error)? onError,
  }) {
    return _viewsRef(statusId)
        .orderBy('viewedAt', descending: true)
        .limit(200)
        .snapshots()
        .listen(
          (snap) => onData(
            snap.docs.map((doc) {
              final d = doc.data();
              return StatusViewer(
                uid: doc.id,
                name: d['viewerName'] as String? ?? 'Quelqu’un',
                photoUrl: d['viewerPhotoUrl'] as String?,
                viewedAt:
                    (d['viewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList(),
          ),
          onError: (Object e) => onError?.call(e),
        );
  }

  UserStatus _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool viewedByMe, {
    bool likedByMe = false,
  }) {
    final d = doc.data()!;
    final createdAt =
        (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return UserStatus(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      createdAt: createdAt,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ??
          createdAt.add(UserStatus.lifetime),
      imageUrl: d['imageUrl'] as String?,
      videoUrl: d['videoUrl'] as String?,
      text: d['text'] as String? ?? '',
      backgroundColor:
          d['backgroundColor'] as int? ?? UserStatus.defaultBackgroundColor,
      viewsCount: d['viewsCount'] as int? ?? 0,
      viewedByMe: viewedByMe,
      likesCount: d['likesCount'] as int? ?? 0,
      likedByMe: likedByMe,
      repostOfId: d['repostOfId'] as String?,
      hidden: d['hidden'] as bool? ?? false,
      repostOfAuthorUid: d['repostOfAuthorUid'] as String?,
      repostOfAuthorName: d['repostOfAuthorName'] as String?,
    );
  }

  // -----------------------------------------------------------------------
  // Publication
  // -----------------------------------------------------------------------

  /// Publie un statut et renvoie sa version locale.
  ///
  /// [localImagePath] et [localVideoPath] s'excluent : un statut porte une
  /// photo, une vidéo, ou rien d'autre que son texte. Les deux fichiers
  /// arrivent déjà bornés par l'appelant (voir
  /// `ProfileController.pickStatusPhoto` / `pickStatusVideo`) — un statut
  /// se regarde quelques secondes, il ne justifie ni l'original de
  /// l'appareil photo ni une vidéo de plusieurs minutes.
  Future<UserStatus> createStatus({
    required String authorUid,
    required String authorName,
    String? authorPhotoUrl,
    String? localImagePath,
    String? localVideoPath,
    String text = '',
    int backgroundColor = UserStatus.defaultBackgroundColor,
  }) async {
    final docRef = _statusesRef.doc();

    // L'uid est dans le chemin : les règles Storage y lisent le
    // propriétaire sans avoir à consulter Firestore, où le document
    // n'existe pas encore à cette seconde.
    String? imageUrl;
    String? videoUrl;
    if (localVideoPath != null && localVideoPath.isNotEmpty) {
      final file = File(localVideoPath);
      await _ensureFitsUnder(file, maxVideoBytes);
      // L'extension du fichier envoyé suit celle de l'original : un `.mov`
      // stocké sous `.mp4` se lirait mal côté Android.
      final extension = localVideoPath.toLowerCase().endsWith('.mov')
          ? 'mov'
          : 'mp4';
      final ref = _storage.ref('statuses/$authorUid/${docRef.id}.$extension');
      await ref.putFile(file, _videoMetadataFor(localVideoPath));
      videoUrl = await ref.getDownloadURL();
    } else if (localImagePath != null && localImagePath.isNotEmpty) {
      final file = File(localImagePath);
      await _ensureFitsUnder(file, maxImageBytes);
      final ref = _storage.ref('statuses/$authorUid/${docRef.id}.jpg');
      await ref.putFile(file, _imageMetadata);
      imageUrl = await ref.getDownloadURL();
    }

    final now = DateTime.now();
    final expiresAt = now.add(UserStatus.lifetime);

    await docRef.set({
      'authorUid': authorUid,
      'authorName': authorName,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
      'imageUrl': ?imageUrl,
      'videoUrl': ?videoUrl,
      'text': text.trim(),
      'backgroundColor': backgroundColor,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewsCount': 0,
    });

    return UserStatus(
      id: docRef.id,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: now,
      expiresAt: expiresAt,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      text: text.trim(),
      backgroundColor: backgroundColor,
    );
  }

  /// Refuse tout de suite un fichier que les règles Storage rejetteraient
  /// de toute façon, mais après l'avoir téléversé.
  static Future<void> _ensureFitsUnder(File file, int maxBytes) async {
    final bytes = await file.length();
    if (bytes >= maxBytes) {
      throw StatusMediaTooLarge(bytes: bytes, maxBytes: maxBytes);
    }
  }

  /// Supprime un statut avant son expiration. La photo dans Storage et la
  /// sous-collection des vues sont purgées par `onStatusDeleted`
  /// (functions/index.js) — l'auteur n'a pas à attendre ce ménage.
  Future<void> deleteStatus(String statusId) => _statusesRef.doc(statusId).delete();

  /// Repartage un statut dans les siens, façon « ajouter à ma story ».
  ///
  /// Le média n'est pas renvoyé depuis le téléphone : le nouveau statut
  /// pointe d'abord sur l'URL d'origine, ce qui l'affiche immédiatement
  /// et ne coûte pas un octet de forfait. `onStatusCreated` recopie
  /// ensuite le fichier dans l'espace du repartageur et réécrit l'URL —
  /// sans quoi l'auteur d'origine supprimant son statut ferait
  /// disparaître l'image de tous les repartages.
  Future<UserStatus> repostStatus({
    required UserStatus original,
    required String authorUid,
    required String authorName,
    String? authorPhotoUrl,
    String caption = '',
  }) async {
    final docRef = _statusesRef.doc();
    final now = DateTime.now();
    final expiresAt = now.add(UserStatus.lifetime);

    // On remonte toujours à la source : repartager un repartage doit
    // créditer l'auteur d'origine, pas l'intermédiaire.
    final sourceId = original.isRepost ? original.repostOfId! : original.id;
    final sourceUid =
        original.isRepost ? original.repostOfAuthorUid! : original.authorUid;
    final sourceName = original.isRepost
        ? (original.repostOfAuthorName ?? original.authorName)
        : original.authorName;

    final text = caption.trim().isNotEmpty ? caption.trim() : original.text;

    await docRef.set({
      'authorUid': authorUid,
      'authorName': authorName,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
      if (original.imageUrl != null) 'imageUrl': original.imageUrl,
      if (original.videoUrl != null) 'videoUrl': original.videoUrl,
      'text': text,
      'backgroundColor': original.backgroundColor,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewsCount': 0,
      'likesCount': 0,
      'repostOfId': sourceId,
      'repostOfAuthorUid': sourceUid,
      'repostOfAuthorName': sourceName,
    });

    return UserStatus(
      id: docRef.id,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: now,
      expiresAt: expiresAt,
      imageUrl: original.imageUrl,
      videoUrl: original.videoUrl,
      text: text,
      backgroundColor: original.backgroundColor,
      repostOfId: sourceId,
      repostOfAuthorUid: sourceUid,
      repostOfAuthorName: sourceName,
    );
  }

  // -----------------------------------------------------------------------
  // J'aime
  // -----------------------------------------------------------------------

  /// Les statuts que [uid] a aimés, en une requête sur son miroir
  /// personnel.
  Future<Set<String>> myLikedStatusIds(String uid, {int limit = 500}) async {
    final snap = await _myLikesRef(
      uid,
    ).orderBy('likedAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Pose ou retire le « j'aime » de [uid] sur [status].
  ///
  /// Renvoie le compte à jour et, surtout, si l'état a **réellement**
  /// changé. Ce second champ n'est pas un détail : aimer un statut déjà
  /// aimé ne doit rien réécrire, et surtout pas renvoyer un second
  /// message à son auteur (voir [likeAndNotify]). Le cas se produit dès
  /// que l'écran d'où l'on vient n'a pas chargé le miroir des « j'aime »
  /// et affiche donc un cœur vide à tort.
  Future<({int count, bool changed})> setLike({
    required UserStatus status,
    required String uid,
    required bool liked,
  }) async {
    final likeRef = _likesRef(status.id).doc(uid);
    final existing = await likeRef.get();
    if (existing.exists == liked) {
      return (count: status.likesCount, changed: false);
    }

    final batch = _db.batch();
    if (liked) {
      batch
        ..set(likeRef, {'likedAt': FieldValue.serverTimestamp()})
        ..set(_myLikesRef(uid).doc(status.id), {
          'likedAt': FieldValue.serverTimestamp(),
          'authorUid': status.authorUid,
        });
    } else {
      batch
        ..delete(likeRef)
        ..delete(_myLikesRef(uid).doc(status.id));
    }
    // `increment` plutôt qu'une valeur calculée ici : deux personnes qui
    // aiment en même temps doivent compter deux fois. Les règles voient la
    // valeur résolue et vérifient qu'elle ne bouge que d'un cran.
    batch.update(_statusesRef.doc(status.id), {
      'likesCount': FieldValue.increment(liked ? 1 : -1),
    });

    await batch.commit();
    final next = status.likesCount + (liked ? 1 : -1);
    return (count: next < 0 ? 0 : next, changed: true);
  }

  // -----------------------------------------------------------------------
  // Réactions — elles atterrissent dans la discussion
  // -----------------------------------------------------------------------

  /// Aimer ou commenter un statut n'ouvre pas un fil de discussion à part :
  /// ça envoie un message à son auteur, dans la conversation qu'on a déjà
  /// avec lui. C'est le fonctionnement de WhatsApp, et c'est le bon ici :
  /// l'auteur retrouve les réactions là où il lit déjà ses messages, sans
  /// écran de plus à surveiller, et la conversation garde la trace de ce
  /// dont on a parlé une fois le statut disparu.
  ChatService get _chat => Get.find<ChatService>();

  /// Le message porte une copie du statut ([StatusRef]) : un statut vit
  /// 24 heures, la citation doit rester lisible bien après.
  StatusRef _refFor(UserStatus status, {required bool isLike}) => StatusRef(
        statusId: status.id,
        authorUid: status.authorUid,
        previewUrl: status.imageUrl,
        text: status.shortPreview,
        backgroundColor: status.backgroundColor,
        isLike: isLike,
        isVideo: status.hasVideo,
      );

  /// Envoie [content] à l'auteur du statut, avec le statut en citation.
  ///
  /// Rien n'est envoyé si l'on réagit à son propre statut : on ne
  /// s'écrit pas à soi-même.
  Future<void> _notifyAuthor({
    required UserStatus status,
    required String fromUid,
    required String content,
    required bool isLike,
  }) async {
    if (fromUid.isEmpty || fromUid == status.authorUid) return;
    final conversationId = Conversation.buildId(fromUid, status.authorUid);
    // La conversation peut ne pas exister : réagir à un statut est
    // souvent le premier message échangé.
    await _chat.getOrCreateConversation(fromUid, status.authorUid);
    await _chat.sendMessage(
      conversationId: conversationId,
      messageId: _chat.newMessageId(conversationId),
      senderUid: fromUid,
      recipientUid: status.authorUid,
      type: MessageType.text,
      content: content,
      statusRef: _refFor(status, isLike: isLike),
    );
  }

  /// Pose le « j'aime » et prévient l'auteur.
  ///
  /// Seul le fait d'aimer envoie un message : retirer son « j'aime » ne
  /// doit rien annoncer, comme partout ailleurs.
  Future<int> likeAndNotify({
    required UserStatus status,
    required String uid,
    required bool liked,
  }) async {
    final result = await setLike(status: status, uid: uid, liked: liked);
    // Le message ne part qu'à la pose effective d'un « j'aime » : retirer
    // le sien n'annonce rien, et ré-aimer ce qui l'était déjà ne doit pas
    // envoyer un second cœur dans la discussion.
    if (liked && result.changed) {
      await _notifyAuthor(
        status: status,
        fromUid: uid,
        content: '❤️',
        isLike: true,
      );
    }
    return result.count;
  }

  /// Envoie un commentaire sur le statut, dans la discussion avec son
  /// auteur.
  Future<void> commentStatus({
    required UserStatus status,
    required String uid,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _notifyAuthor(
      status: status,
      fromUid: uid,
      content: trimmed,
      isLike: false,
    );
  }

  /// Prévient l'auteur qu'on a repartagé son statut — comme Instagram
  /// signale « a ajouté votre story à la sienne ».
  Future<void> notifyRepost({
    required UserStatus status,
    required String uid,
  }) =>
      _notifyAuthor(
        status: status,
        fromUid: uid,
        content: 'a repartagé votre statut',
        isLike: false,
      );

  // -----------------------------------------------------------------------
  // Vues
  // -----------------------------------------------------------------------

  /// Enregistre que [viewerUid] a vu le statut, une seule fois.
  ///
  /// Renvoie le nouveau nombre de vues, ou `null` si rien n'a été compté —
  /// vue déjà enregistrée, ou auteur regardant son propre statut : on ne
  /// se compte pas soi-même parmi ses spectateurs.
  Future<int?> markViewed({
    required UserStatus status,
    required String viewerUid,
    required String viewerName,
    String? viewerPhotoUrl,
  }) async {
    if (viewerUid.isEmpty || viewerUid == status.authorUid) return null;

    final viewRef = _viewsRef(status.id).doc(viewerUid);
    // Une lecture avant écriture : le document de vue n'accepte que la
    // création (jamais la mise à jour), et le compteur ne doit monter
    // qu'à la première ouverture. Rouvrir un statut dix fois ne fait pas
    // dix vues.
    final existing = await viewRef.get();
    if (existing.exists) return null;

    final batch = _db.batch()
      ..set(viewRef, {
        'viewedAt': FieldValue.serverTimestamp(),
        'viewerName': viewerName,
        if (viewerPhotoUrl != null && viewerPhotoUrl.isNotEmpty)
          'viewerPhotoUrl': viewerPhotoUrl,
      })
      ..set(_myViewsRef(viewerUid).doc(status.id), {
        'viewedAt': FieldValue.serverTimestamp(),
      })
      // `increment` plutôt qu'une valeur calculée ici : deux personnes qui
      // ouvrent le statut en même temps doivent compter deux vues, pas
      // une. Les règles voient la valeur résolue et vérifient qu'elle ne
      // bouge que d'un cran.
      ..update(_statusesRef.doc(status.id), {
        'viewsCount': FieldValue.increment(1),
      });

    await batch.commit();
    return status.viewsCount + 1;
  }
}
