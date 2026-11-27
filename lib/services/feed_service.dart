import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/feed_item.dart';
import '../models/post_text.dart';
import '../utils/local_media.dart';

class FeedService {
  static const pageSize = 8;

  /// Taille de la première page, volontairement plus large que les
  /// suivantes.
  ///
  /// C'est la fenêtre sur laquelle porte la rotation du fil (voir
  /// `HomeController`) : mélanger huit publications ne se remarque pas,
  /// et surtout le haut du fil resterait occupé par les huit mêmes à
  /// chaque ouverture. Sur une vingtaine, l'ordre change réellement d'une
  /// visite à l'autre — pour une seule requête, à peine plus coûteuse.
  static const firstPageSize = 24;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _postsRef =>
      _db.collection('posts');

  /// Un document par personne ayant aimé : `posts/{id}/likes/{uid}`.
  /// Remplace le tableau `likedBy` qui vivait dans le document du post —
  /// celui-ci était réécrit en entier à chaque « j'aime », plafonnait avec
  /// la taille du document et sérialisait tous les likes d'un post sur une
  /// seule écriture.
  CollectionReference<Map<String, dynamic>> _likesRef(String postId) =>
      _postsRef.doc(postId).collection('likes');

  /// Miroir personnel : `users/{uid}/likes/{postId}`. La liste des likes
  /// d'une personne est petite et lui appartient, contrairement à celle
  /// d'un post ; la charger d'un coup évite une lecture par post affiché.
  CollectionReference<Map<String, dynamic>> _myLikesRef(String uid) =>
      _db.collection('users').doc(uid).collection('likes');

  /// Miroir des posts enregistrés — `users/{uid}/saved/{postId}`, calqué
  /// sur [_myLikesRef]. Strictement personnel : contrairement au like, un
  /// enregistrement n'a pas de contrepartie publique côté post, personne
  /// n'a à savoir qui a mis quoi de côté.
  CollectionReference<Map<String, dynamic>> _mySavedRef(String uid) =>
      _db.collection('users').doc(uid).collection('saved');

  DocumentSnapshot? _lastDoc;
  int _lastPageRawCount = 0;
  int _lastPageLimit = pageSize;

  /// Vrai tant que la dernière page lue était pleine — donc qu'il reste
  /// probablement des posts à charger. À distinguer de la longueur de la
  /// liste rendue : les posts masqués par la modération sont retirés après
  /// la requête, et une page filtrée plus courte que la limite demandée ne
  /// signifie pas qu'on a atteint la fin du fil.
  ///
  /// La comparaison porte sur la limite réellement employée, pas sur
  /// `pageSize` : la première page en demande davantage
  /// ([firstPageSize]), et la mesurer contre `pageSize` ferait croire à
  /// une page pleine alors que le fil est déjà épuisé.
  bool get lastPageWasFull => _lastPageRawCount >= _lastPageLimit;

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  /// [preferCache] : sert la page depuis le cache local quand elle s'y
  /// trouve, sans attendre le réseau. Réservé au tout premier affichage
  /// d'une liste — l'écoute temps réel (`watchPosts`) recale le contenu
  /// dès que le serveur répond. À laisser à `false` pour un vrai
  /// rafraîchissement demandé par l'utilisateur, qui doit interroger le
  /// serveur.
  /// [likedPostIds] : les posts déjà aimés par la session, tels que
  /// [myLikedPostIds] les a chargés. `likedByMe` ne se lit plus dans le
  /// document du post, il se résout localement contre cet ensemble.
  /// [limit] : nombre de documents demandés. Par défaut [pageSize] ;
  /// la première page en demande davantage pour donner de la matière à la
  /// rotation du fil (voir [firstPageSize]).
  Future<List<FeedItem>> fetchPage({
    FeedFilter filter = FeedFilter.all,
    bool reset = false,
    Set<String> likedPostIds = const {},
    bool preferCache = false,
    int? limit,
  }) async {
    if (reset) _lastDoc = null;

    Query<Map<String, dynamic>> query = _postsRef.orderBy(
      'publishedAt',
      descending: true,
    );

    if (filter != FeedFilter.all && filter != FeedFilter.venteAchat) {
      final typeName = switch (filter) {
        FeedFilter.population => 'post',
        _ => '',
      };
      query = query.where('type', isEqualTo: typeName);
    }

    if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);
    _lastPageLimit = limit ?? pageSize;
    final paged = query.limit(_lastPageLimit);
    final snapshot =
        (preferCache ? await _fromCache(paged) : null) ?? await paged.get();
    if (snapshot.docs.isNotEmpty) _lastDoc = snapshot.docs.last;
    _lastPageRawCount = snapshot.docs.length;

    return snapshot.docs
        .map((doc) => _itemFromDoc(doc, likedPostIds.contains(doc.id)))
        .where((item) => !item.hidden)
        .toList();
  }

  /// Lecture d'une requête dans le cache local, ou `null` si le cache ne
  /// peut pas y répondre (vide, ou Firestore refuse de servir hors ligne).
  static Future<QuerySnapshot<Map<String, dynamic>>?> _fromCache(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      final snap = await query.get(const GetOptions(source: Source.cache));
      return snap.docs.isEmpty ? null : snap;
    } on FirebaseException catch (_) {
      return null;
    }
  }

  /// Fenêtre de fraîcheur des publications d'abonnements mises en avant.
  /// Au-delà, la publication n'est plus remontée en tête : elle reprend sa
  /// place normale dans le fil, classée par date comme le reste.
  static const followingHighlightWindow = Duration(hours: 24);

  /// Nombre maximal de valeurs acceptées par un `whereIn` Firestore : la
  /// liste des abonnements est découpée en autant de requêtes.
  static const _whereInChunkSize = 30;

  /// La dernière publication de chaque compte suivi, à condition qu'elle
  /// date de moins de [window] — mélangée, pour que le haut du fil ne soit
  /// pas toujours occupé par les mêmes comptes.
  ///
  /// Une seule publication par compte : c'est « quoi de neuf chez les gens
  /// que je suis », pas la reprise de tout leur mur. Les publications plus
  /// anciennes ne sont pas renvoyées ici — la pagination chronologique de
  /// [fetchPage] s'en charge, à leur date.
  ///
  /// Le filtre de type est appliqué côté client : la requête porte déjà un
  /// `whereIn` et une borne de date, y ajouter `type` demanderait un index
  /// composite de plus pour un volume qui tient dans une poignée de
  /// documents.
  Future<List<FeedItem>> fetchFollowingHighlights({
    required Iterable<String> followingUids,
    FeedFilter filter = FeedFilter.all,
    Set<String> likedPostIds = const {},
    Duration window = followingHighlightWindow,
    Random? random,
  }) async {
    if (filter == FeedFilter.venteAchat) return [];
    final uids = followingUids.toSet().toList();
    if (uids.isEmpty) return [];

    final cutoff = Timestamp.fromDate(DateTime.now().subtract(window));
    final fresh = <FeedItem>[];

    for (var i = 0; i < uids.length; i += _whereInChunkSize) {
      final chunk = uids.sublist(i, min(i + _whereInChunkSize, uids.length));
      try {
        final snap = await _postsRef
            .where('authorUid', whereIn: chunk)
            .where('publishedAt', isGreaterThanOrEqualTo: cutoff)
            .orderBy('publishedAt', descending: true)
            .limit(chunk.length * 3)
            .get();
        fresh.addAll(
          snap.docs.map(
            (doc) => _itemFromDoc(doc, likedPostIds.contains(doc.id)),
          ),
        );
      } on FirebaseException catch (_) {
        // Index manquant, hors ligne, règles : la mise en avant est un
        // bonus, son échec ne doit pas priver de fil. On retombe sur le
        // classement chronologique seul.
        return [];
      }
    }

    return shuffledLatestPerAuthor(fresh, filter: filter, random: random);
  }

  /// Une publication par auteur — la plus récente —, filtrée sur [filter] et
  /// rendue dans un ordre aléatoire.
  ///
  /// Séparée de la requête pour être vérifiable sans Firestore : c'est elle
  /// qui décide de ce qui ouvre le fil.
  static List<FeedItem> shuffledLatestPerAuthor(
    Iterable<FeedItem> posts, {
    FeedFilter filter = FeedFilter.all,
    Random? random,
  }) {
    final wantedType = _typeForFilter(filter);
    final latestByAuthor = <String, FeedItem>{};
    for (final item in posts) {
      if (item.hidden) continue;
      if (wantedType != null && item.type != wantedType) continue;
      final kept = latestByAuthor[item.authorUid];
      // Les documents arrivent déjà du plus récent au plus ancien, mais la
      // comparaison explicite rend le résultat indépendant de l'ordre
      // d'entrée — plusieurs requêtes sont concaténées ici.
      if (kept == null || item.publishedAt.isAfter(kept.publishedAt)) {
        latestByAuthor[item.authorUid] = item;
      }
    }
    return latestByAuthor.values.toList()..shuffle(random ?? Random());
  }

  /// Fenêtre pendant laquelle une publication reste en tête du fil, à sa
  /// place chronologique. Au-delà, elle entre dans la rotation.
  static const freshWindow = Duration(hours: 24);

  /// Ordonne un lot de publications : les récentes d'abord, par date, puis
  /// les autres dans un ordre tiré au sort.
  ///
  /// Le fil était strictement chronologique, donc identique à chaque
  /// ouverture : sans nouvelle publication, rien ne bougeait, et les mêmes
  /// comptes occupaient le haut en permanence. Mélanger tout serait pire —
  /// on ne verrait plus ce qui vient d'être publié. D'où ce partage : ce
  /// qui date de moins de [freshWindow] garde son ordre et sa place en
  /// tête, le reste tourne.
  ///
  /// [random] rend le tirage reproductible : le contrôleur passe une
  /// graine stable pour toute la session, afin que l'ordre ne se remette
  /// pas à bouger sous les doigts pendant qu'on fait défiler.
  ///
  /// Fonction pure, pour être vérifiable sans Firestore.
  static List<FeedItem> rotate(
    Iterable<FeedItem> posts, {
    Duration freshWindow = freshWindow,
    Random? random,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(freshWindow);
    final fresh = <FeedItem>[];
    final rest = <FeedItem>[];
    for (final post in posts) {
      (post.publishedAt.isAfter(cutoff) ? fresh : rest).add(post);
    }
    fresh.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    rest.shuffle(random ?? Random());
    return [...fresh, ...rest];
  }

  static FeedType? _typeForFilter(FeedFilter filter) => switch (filter) {
    FeedFilter.population => FeedType.post,
    _ => null,
  };

  Future<FeedItem?> getById(String id, {bool likedByMe = false}) async {
    final doc = await _postsRef.doc(id).get();
    if (!doc.exists) return null;
    return _itemFromDoc(doc, likedByMe);
  }

  /// Les posts aimés par [uid], lus en une requête sur son miroir
  /// personnel. Borné à [limit] : au-delà, les plus anciens likes
  /// n'apparaîtront pas cochés tant que la personne n'y retouche pas — un
  /// compromis assumé face à une requête sans limite.
  Future<Set<String>> myLikedPostIds(String uid, {int limit = 1000}) async {
    final snap = await _myLikesRef(
      uid,
    ).orderBy('likedAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Décode un document de publication avec les mêmes règles que le fil
  /// — public pour la recherche globale.
  FeedItem parseDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool likedByMe = false,
  }) => _itemFromDoc(doc, likedByMe);

  FeedItem _itemFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    bool likedByMe,
  ) {
    final d = doc.data()!;
    return FeedItem(
      id: doc.id,
      type: FeedType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => FeedType.post,
      ),
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      authorSubtitle: d['authorSubtitle'] as String? ?? '',
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      authorVerified: d['authorVerified'] as bool? ?? false,
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      repostOfId: d['repostOfId'] as String?,
      repostOfAuthorUid: d['repostOfAuthorUid'] as String?,
      repostOfAuthorName: d['repostOfAuthorName'] as String?,
      repostOfAuthorPhotoUrl: d['repostOfAuthorPhotoUrl'] as String?,
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
      likesCount: d['likesCount'] as int? ?? 0,
      likedByMe: likedByMe,
      commentsCount: d['commentsCount'] as int? ?? 0,
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
      commentsDisabled: d['commentsDisabled'] as bool? ?? false,
      hidden: d['hidden'] as bool? ?? false,
      videoUrl: d['videoUrl'] as String?,
      videoThumbUrl: d['videoThumbUrl'] as String?,
      videoDurationMs: (d['videoDurationMs'] as num?)?.toInt(),
      videoAspectRatio: (d['videoAspectRatio'] as num?)?.toDouble(),
      mentions: [
        for (final m in (d['mentions'] as List? ?? const []))
          if (m is Map) PostMention.fromMap(Map<String, dynamic>.from(m)),
      ],
      hashtags: List<String>.from(d['hashtags'] ?? const []),
    );
  }

  /// Publications portant un hashtag (forme normalisée, sans « # »), les
  /// plus récentes d'abord. Trié ici plutôt que par `orderBy` : pas
  /// d'index composite à maintenir pour un volume de commune.
  Future<List<FeedItem>> postsByHashtag(String tag, {int limit = 60}) async {
    final normalized = normalizeHashtag(tag);
    if (normalized.isEmpty) return const [];
    final snap = await _postsRef
        .where('hashtags', arrayContains: normalized)
        .limit(limit)
        .get();
    final posts = [
      for (final doc in snap.docs) _itemFromDoc(doc, false),
    ]..removeWhere((p) => p.hidden);
    posts.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return posts;
  }

  /// Champs vidéo d'un document.
  static Map<String, dynamic> _videoFields(UploadedVideo? v) => v == null
      ? const {}
      : {
          'videoUrl': v.url,
          'videoThumbUrl': v.thumbUrl,
          'videoDurationMs': v.durationMs,
          'videoAspectRatio': v.aspectRatio,
        };

  // -----------------------------------------------------------------------
  // Créer un post (avec upload d'images vers Storage)
  // -----------------------------------------------------------------------

  Future<FeedItem> createPost({
    required FeedType type,
    required String title,
    required String body,
    required String authorUid,
    required String authorName,
    required String authorSubtitle,
    bool authorVerified = false,
    String? authorPhotoUrl,
    List<String> localImagePaths = const [],
    PostVideoDraft? video,
    List<PostMention> mentions = const [],
    void Function(double progress)? onVideoProgress,
  }) async {
    final docRef = _postsRef.doc();

    // L'uid de l'auteur ouvre le chemin : c'est lui que les règles
    // Storage lisent pour autoriser l'envoi (voir storage.rules).
    final imageUrls = await _uploadImages(
      localImagePaths,
      'posts/$authorUid/${docRef.id}',
    );
    final uploadedVideo = video == null
        ? null
        : await _uploadVideo(
            video,
            'posts/$authorUid/${docRef.id}',
            onVideoProgress,
          );
    final keptMentions = mentionsStillIn(body, mentions);
    final hashtags = extractHashtags('$title $body');

    final now = DateTime.now();
    await docRef.set({
      'type': type.name,
      'title': title.trim(),
      'body': body.trim(),
      'authorUid': authorUid,
      'authorName': authorName,
      'authorSubtitle': authorSubtitle,
      'authorVerified': authorVerified,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
      'publishedAt': Timestamp.fromDate(now),
      'imageUrls': imageUrls,
      ..._videoFields(uploadedVideo),
      'mentions': [for (final m in keptMentions) m.toMap()],
      'hashtags': hashtags,
      'likesCount': 0,
      'commentsCount': 0,
      'commentsDisabled': false,
      'hidden': false,
      'reportsCount': 0,
    });

    return FeedItem(
      id: docRef.id,
      type: type,
      title: title.trim(),
      body: body.trim(),
      authorUid: authorUid,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      authorVerified: authorVerified,
      authorPhotoUrl: authorPhotoUrl,
      publishedAt: now,
      imageUrls: imageUrls,
      videoUrl: uploadedVideo?.url,
      videoThumbUrl: uploadedVideo?.thumbUrl,
      videoDurationMs: uploadedVideo?.durationMs,
      videoAspectRatio: uploadedVideo?.aspectRatio,
      mentions: keptMentions,
      hashtags: hashtags,
    );
  }

  /// Republication dans le fil : nouveau document dont l'auteur est
  /// l'utilisateur courant, avec le contenu (texte + URLs d'images) de
  /// l'original — pas de re-upload des photos, seulement une référence
  /// vers la publication source.
  Future<FeedItem> repostPost({
    required FeedItem original,
    required String authorUid,
    required String authorName,
    required String authorSubtitle,
    bool authorVerified = false,
    String? authorPhotoUrl,
  }) async {
    final sourceId = original.repostOfId ?? original.id;
    final sourceAuthorUid = original.repostOfAuthorUid ?? original.authorUid;
    final sourceAuthorName = original.repostOfAuthorName ?? original.authorName;
    final sourceAuthorPhoto =
        original.repostOfAuthorPhotoUrl ?? original.authorPhotoUrl;

    final docRef = _postsRef.doc();
    final now = DateTime.now();
    await docRef.set({
      'type': original.type.name,
      'title': original.title,
      'body': original.body,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorSubtitle': authorSubtitle,
      'authorVerified': authorVerified,
      if (authorPhotoUrl != null && authorPhotoUrl.isNotEmpty)
        'authorPhotoUrl': authorPhotoUrl,
      'publishedAt': Timestamp.fromDate(now),
      'imageUrls': original.imageUrls,
      if (original.hasVideo) ...{
        'videoUrl': original.videoUrl,
        'videoThumbUrl': original.videoThumbUrl,
        'videoDurationMs': original.videoDurationMs,
        'videoAspectRatio': original.videoAspectRatio,
      },
      'mentions': [for (final m in original.mentions) m.toMap()],
      'hashtags': original.hashtags,
      'repostOfId': sourceId,
      'repostOfAuthorUid': sourceAuthorUid,
      'repostOfAuthorName': sourceAuthorName,
      if (sourceAuthorPhoto != null && sourceAuthorPhoto.isNotEmpty)
        'repostOfAuthorPhotoUrl': sourceAuthorPhoto,
      'likesCount': 0,
      'commentsCount': 0,
      'commentsDisabled': false,
      'hidden': false,
      'reportsCount': 0,
    });

    return FeedItem(
      id: docRef.id,
      type: original.type,
      title: original.title,
      body: original.body,
      authorUid: authorUid,
      authorName: authorName,
      authorSubtitle: authorSubtitle,
      authorVerified: authorVerified,
      authorPhotoUrl: authorPhotoUrl,
      repostOfId: sourceId,
      repostOfAuthorUid: sourceAuthorUid,
      repostOfAuthorName: sourceAuthorName,
      repostOfAuthorPhotoUrl: sourceAuthorPhoto,
      publishedAt: now,
      imageUrls: List<String>.from(original.imageUrls),
      videoUrl: original.videoUrl,
      videoThumbUrl: original.videoThumbUrl,
      videoDurationMs: original.videoDurationMs,
      videoAspectRatio: original.videoAspectRatio,
      mentions: original.mentions,
      hashtags: original.hashtags,
    );
  }

  // -----------------------------------------------------------------------
  // Éditer un post
  // -----------------------------------------------------------------------

  /// Applique une édition et renvoie le post à jour.
  ///
  /// [keptImageUrls] est la liste des images d'origine que l'auteur a
  /// conservées, dans l'ordre voulu ; celles de [original] qui n'y figurent
  /// plus sont effacées de Storage. [newLocalImagePaths] sont les fichiers
  /// ajoutés pendant l'édition, uploadés puis concaténés à la suite.
  Future<FeedItem> updatePost({
    required FeedItem original,
    required FeedType type,
    required String title,
    required String body,
    required List<String> keptImageUrls,
    List<String> newLocalImagePaths = const [],
    bool keepVideo = true,
    PostVideoDraft? newVideo,
    List<PostMention> mentions = const [],
    void Function(double progress)? onVideoProgress,
  }) async {
    final ref = _postsRef.doc(original.id);
    final folder = 'posts/${original.authorUid}/${original.id}';

    final uploaded = await _uploadImages(newLocalImagePaths, folder);
    final imageUrls = [...keptImageUrls, ...uploaded];
    final uploadedVideo = newVideo == null
        ? null
        : await _uploadVideo(newVideo, folder, onVideoProgress);
    final dropOldVideo =
        original.hasVideo && (!keepVideo || uploadedVideo != null);
    final keptMentions = mentionsStillIn(body, mentions);
    final hashtags = extractHashtags('$title $body');

    final now = DateTime.now();
    await ref.update({
      'type': type.name,
      'title': title.trim(),
      'body': body.trim(),
      'imageUrls': imageUrls,
      if (uploadedVideo != null)
        ..._videoFields(uploadedVideo)
      else if (dropOldVideo) ...{
        'videoUrl': FieldValue.delete(),
        'videoThumbUrl': FieldValue.delete(),
        'videoDurationMs': FieldValue.delete(),
        'videoAspectRatio': FieldValue.delete(),
      },
      'mentions': [for (final m in keptMentions) m.toMap()],
      'hashtags': hashtags,
      'editedAt': Timestamp.fromDate(now),
    });

    // Après l'update seulement : tant que le document référence encore une
    // image, une suppression ratée laisse un lien mort dans le fil.
    final removed = original.imageUrls.where(
      (url) => !keptImageUrls.contains(url),
    );
    await _deleteImagesByUrl([
      ...removed,
      if (dropOldVideo) ...[
        original.videoUrl!,
        if (original.videoThumbUrl != null) original.videoThumbUrl!,
      ],
    ]);

    final base = original.copyWith(
      type: type,
      title: title.trim(),
      body: body.trim(),
      imageUrls: imageUrls,
      editedAt: now,
      mentions: keptMentions,
      hashtags: hashtags,
      clearVideo: dropOldVideo && uploadedVideo == null,
    );
    return uploadedVideo == null
        ? base
        : base.copyWith(
            videoUrl: uploadedVideo.url,
            videoThumbUrl: uploadedVideo.thumbUrl,
            videoDurationMs: uploadedVideo.durationMs,
            videoAspectRatio: uploadedVideo.aspectRatio,
          );
  }

  /// Ouvre ou ferme les commentaires d'une publication.
  Future<void> setCommentsDisabled(String postId, bool disabled) {
    return _postsRef.doc(postId).update({'commentsDisabled': disabled});
  }

  // -----------------------------------------------------------------------
  // Supprimer un post
  // -----------------------------------------------------------------------

  /// Supprime une publication et ses images.
  ///
  /// Les commentaires sont purgés côté serveur (`onPostDeleted` dans
  /// functions/index.js) : le client ne peut pas les effacer lui-même, les
  /// règles ne l'autorisant que pour ses propres commentaires — l'auteur du
  /// post n'a aucun droit sur ceux des autres. Firestore ne supprimant pas
  /// les sous-collections en cascade, sans cette fonction les commentaires
  /// resteraient orphelins en base indéfiniment.
  ///
  /// Les images sont en revanche retirées ici, tant que le document existe
  /// encore : les règles Storage vérifient `authorUid` sur le document
  /// Firestore, qui doit donc être supprimé en dernier.
  Future<void> deletePost(FeedItem post) async {
    await _deleteImagesByUrl([
      ...post.imageUrls,
      // Une republication pointe sur la vidéo de l'original : ne pas
      // l'effacer sous ses pieds.
      if (post.hasVideo && !post.isRepost) ...[
        post.videoUrl!,
        if (post.videoThumbUrl != null) post.videoThumbUrl!,
      ],
    ]);
    await _postsRef.doc(post.id).delete();
  }

  // -----------------------------------------------------------------------
  // Commentaires
  // -----------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) =>
      _postsRef.doc(postId).collection('comments');

  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorName,
    required String text,
    String? authorPhotoUrl,
    String? parentCommentId,
    String? replyToName,
  }) async {
    await _commentsRef(postId).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'text': text.trim(),
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'parentCommentId': parentCommentId,
      'replyToName': replyToName,
      'likesCount': 0,
      'likedBy': <String>[],
      'deleted': false,
    });
    await _postsRef.doc(postId).update({
      'commentsCount': FieldValue.increment(1),
    });
  }

  Future<void> updateComment({
    required String postId,
    required String commentId,
    required String text,
  }) {
    return _commentsRef(postId).doc(commentId).update({
      'text': text.trim(),
      'editedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Supprime un commentaire et décrémente le compteur du post.
  ///
  /// Un commentaire qui porte des réponses est vidé plutôt qu'effacé :
  /// les réponses sont rattachées par `parentCommentId`, et `_buildTree`
  /// ne raccroche que les nœuds dont le parent existe — supprimer un
  /// parent ferait donc disparaître silencieusement tout son sous-arbre,
  /// pourtant toujours présent en base.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    final ref = _commentsRef(postId).doc(commentId);
    final snap = await ref.get();
    if (!snap.exists) return;
    // Déjà supprimé (double tap, deux appareils) : ne pas décrémenter deux
    // fois le compteur du post.
    if (snap.data()?['deleted'] == true) return;

    final hasReplies =
        (await _commentsRef(
              postId,
            ).where('parentCommentId', isEqualTo: commentId).limit(1).get())
            .docs
            .isNotEmpty;

    if (hasReplies) {
      await ref.update({
        'text': '',
        'deleted': true,
        'likedBy': <String>[],
        'likesCount': 0,
        'editedAt': Timestamp.fromDate(DateTime.now()),
      });
    } else {
      await ref.delete();
    }

    await _decrementCommentsCount(postId);
  }

  /// Décrémente `commentsCount` sans jamais passer sous zéro — un compteur
  /// négatif s'afficherait tel quel dans le fil et ne se corrigerait plus.
  Future<void> _decrementCommentsCount(String postId) async {
    final ref = _postsRef.doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final current = snap.data()?['commentsCount'] as int? ?? 0;
      tx.update(ref, {'commentsCount': current > 0 ? current - 1 : 0});
    });
  }

  Future<List<FeedComment>> fetchComments(
    String postId, {
    String? currentUid,
  }) async {
    final snapshot = await _commentsRef(postId).orderBy('createdAt').get();
    return _buildTree(
      snapshot.docs.map((doc) => _commentEntry(doc, currentUid)).toList(),
    );
  }

  ({FeedComment comment, String? parentId}) _commentEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String? currentUid,
  ) {
    final d = doc.data();
    final likedBy = List<String>.from(d['likedBy'] ?? []);
    return (
      comment: FeedComment(
        id: doc.id,
        authorUid: d['authorUid'] as String? ?? '',
        authorName: d['authorName'] as String? ?? '',
        authorPhotoUrl: d['authorPhotoUrl'] as String?,
        text: d['text'] as String? ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        parentCommentId: d['parentCommentId'] as String?,
        replyToName: d['replyToName'] as String?,
        likesCount: d['likesCount'] as int? ?? 0,
        likedByMe: currentUid != null && likedBy.contains(currentUid),
        editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
        deleted: d['deleted'] as bool? ?? false,
      ),
      parentId: d['parentCommentId'] as String?,
    );
  }

  List<FeedComment> _buildTree(
    List<({FeedComment comment, String? parentId})> flat,
  ) {
    final childrenOf = <String?, List<FeedComment>>{};
    final knownIds = flat.map((e) => e.comment.id).toSet();

    for (final entry in flat) {
      // Un parent absent (supprimé avant l'ajout de la suppression douce,
      // ou hors de la fenêtre `limit`) remonterait sinon dans un seau
      // jamais parcouru : la réponse disparaîtrait du fil. On la remonte à
      // la racine plutôt que de la perdre.
      final parentId =
          entry.parentId != null && knownIds.contains(entry.parentId)
          ? entry.parentId
          : null;
      childrenOf.putIfAbsent(parentId, () => []).add(entry.comment);
    }

    FeedComment attach(FeedComment c) {
      final children = childrenOf[c.id];
      if (children == null || children.isEmpty) return c;
      return c.copyWith(replies: children.map(attach).toList());
    }

    return (childrenOf[null] ?? []).map(attach).toList();
  }

  Future<LikeState> setCommentLike(
    String postId,
    String commentId,
    String uid,
    bool liked,
  ) {
    return _applyLike(_commentsRef(postId).doc(commentId), uid, liked);
  }

  // -----------------------------------------------------------------------
  // Publications enregistrées
  // -----------------------------------------------------------------------

  /// Les posts enregistrés par [uid]. Comme [myLikedPostIds], borné : la
  /// liste sert à cocher un signet dans le fil, pas à tout restituer.
  Future<Set<String>> mySavedPostIds(String uid, {int limit = 500}) async {
    final snap = await _mySavedRef(
      uid,
    ).orderBy('savedAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Pose ou retire le signet. Une seule écriture, sur un document que
  /// l'utilisateur seul peut lire et écrire — pas de compteur à tenir, donc
  /// pas de transaction : l'existence du document est toute la vérité.
  Future<void> setSaved(String postId, String uid, bool saved) {
    final ref = _mySavedRef(uid).doc(postId);
    return saved
        ? ref.set({'postId': postId, 'savedAt': FieldValue.serverTimestamp()})
        : ref.delete();
  }

  /// Les publications enregistrées, les plus récemment mises de côté
  /// d'abord.
  ///
  /// Une lecture par post : le miroir ne stocke que des identifiants, pour
  /// qu'un post modifié ou supprimé après coup ne laisse pas une copie
  /// périmée dans la liste. C'est acceptable ici — l'écran est ouvert
  /// rarement et la liste est bornée — là où ça ne le serait pas dans le
  /// fil, parcouru en continu.
  ///
  /// Les identifiants dont le post n'existe plus sont nettoyés au passage,
  /// et les publications masquées par la modération écartées.
  Future<List<FeedItem>> fetchSavedPosts(
    String uid, {
    Set<String> likedPostIds = const {},
    int limit = 100,
  }) async {
    final snap = await _mySavedRef(
      uid,
    ).orderBy('savedAt', descending: true).limit(limit).get();

    final docs = await Future.wait(
      snap.docs.map((d) => _postsRef.doc(d.id).get()),
    );

    final items = <FeedItem>[];
    final stale = <String>[];
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (!doc.exists) {
        stale.add(snap.docs[i].id);
        continue;
      }
      final item = _itemFromDoc(doc, likedPostIds.contains(doc.id));
      if (!item.hidden) items.add(item);
    }

    if (stale.isNotEmpty) {
      final batch = _db.batch();
      for (final id in stale) {
        batch.delete(_mySavedRef(uid).doc(id));
      }
      // Sans importance pour l'affichage : si le ménage échoue, la liste
      // est déjà correcte et il sera retenté à la prochaine ouverture.
      unawaited(batch.commit().catchError((Object _) {}));
    }

    return items;
  }

  // -----------------------------------------------------------------------
  // Likes
  // -----------------------------------------------------------------------

  /// Pose ou retire le « j'aime » de [uid] et renvoie l'état **faisant
  /// autorité** après l'opération. L'appelant doit adopter cette valeur
  /// plutôt que d'incrémenter son compteur local : un client qui croyait
  /// à tort ne pas avoir aimé gonflait son compteur à chaque appui sans
  /// que rien ne le recale.
  ///
  /// Trois écritures dans une seule transaction : le like lui-même
  /// (`posts/{id}/likes/{uid}`), son miroir personnel
  /// (`users/{uid}/likes/{id}`) et le compteur du post, en `increment`.
  /// L'existence du document de like est la seule vérité — le compteur
  /// n'en est qu'un résumé, ce qui rend l'opération idempotente : aimer
  /// deux fois n'écrit rien la seconde fois.
  Future<LikeState> setLike(String postId, String uid, bool liked) {
    final postRef = _postsRef.doc(postId);
    final likeRef = _likesRef(postId).doc(uid);
    final mirrorRef = _myLikesRef(uid).doc(postId);

    return _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) {
        return const LikeState(likesCount: 0, likedByMe: false);
      }
      final likeSnap = await tx.get(likeRef);
      final count = (postSnap.data()?['likesCount'] as int?) ?? 0;
      if (liked == likeSnap.exists) {
        return LikeState(likesCount: count, likedByMe: likeSnap.exists);
      }

      if (liked) {
        final at = FieldValue.serverTimestamp();
        tx.set(likeRef, {'uid': uid, 'likedAt': at});
        tx.set(mirrorRef, {'postId': postId, 'likedAt': at});
      } else {
        tx.delete(likeRef);
        tx.delete(mirrorRef);
      }
      tx.update(postRef, {'likesCount': FieldValue.increment(liked ? 1 : -1)});

      // Le compteur renvoyé anticipe l'`increment` côté serveur ; l'écoute
      // temps réel apportera la valeur définitive juste après.
      return LikeState(
        likesCount: (count + (liked ? 1 : -1)).clamp(0, 1 << 30),
        likedByMe: liked,
      );
    });
  }

  /// Les likes de commentaire restent un tableau `likedBy` dans le
  /// document : bornés par nature (un commentaire n'attire pas le volume
  /// d'un post), ils n'ont pas le problème d'échelle qui a fait sortir
  /// ceux des posts. `likesCount` y est toujours déduit de `likedBy`, et
  /// réécrit même quand l'appartenance ne change pas : un compteur déjà
  /// désynchronisé se répare à la première interaction.
  Future<LikeState> _applyLike(
    DocumentReference<Map<String, dynamic>> ref,
    String uid,
    bool liked,
  ) {
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return const LikeState(likesCount: 0, likedByMe: false);
      final data = snap.data() ?? const <String, dynamic>{};
      final likedBy = List<String>.from(data['likedBy'] ?? []);
      final alreadyLiked = likedBy.contains(uid);
      if (liked && !alreadyLiked) likedBy.add(uid);
      if (!liked && alreadyLiked) likedBy.remove(uid);
      final count = likedBy.length;
      if (liked != alreadyLiked || data['likesCount'] != count) {
        tx.update(ref, {'likedBy': likedBy, 'likesCount': count});
      }
      return LikeState(likesCount: count, likedByMe: liked);
    });
  }

  // -----------------------------------------------------------------------
  // Temps réel
  // -----------------------------------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchPosts({
    required bool Function(String postId) isLikedByMe,
    required void Function(FeedItem item) onAdded,
    required void Function(FeedItem item) onModified,
    required void Function(String id) onRemoved,
  }) {
    // Borné : ce flux ne sert qu'à répercuter en direct les posts récents
    // (nouveaux / likes / commentaires) au-dessus de la liste paginée. Sans
    // `.limit`, il streamait toute la collection `posts` en mémoire et la
    // rechargeait du cache local à chaque ouverture.
    return _postsRef
        .orderBy('publishedAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            switch (change.type) {
              case DocumentChangeType.added:
                final item = _itemFromDoc(
                  change.doc,
                  isLikedByMe(change.doc.id),
                );
                if (item.hidden) continue;
                onAdded(item);
              case DocumentChangeType.modified:
                final item = _itemFromDoc(
                  change.doc,
                  isLikedByMe(change.doc.id),
                );
                // Un post masqué par la modération quitte le fil comme s'il
                // avait été supprimé.
                if (item.hidden) {
                  onRemoved(item.id);
                } else {
                  onModified(item);
                }
              case DocumentChangeType.removed:
                onRemoved(change.doc.id);
            }
          }
        });
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchComments(
    String postId, {
    String? currentUid,
    required void Function(List<FeedComment> comments) onData,
  }) {
    return _commentsRef(
      postId,
    ).orderBy('createdAt').limit(300).snapshots().listen((snapshot) {
      onData(
        _buildTree(
          snapshot.docs.map((doc) => _commentEntry(doc, currentUid)).toList(),
        ),
      );
    });
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> watchPost(
    String postId, {
    required bool Function(String postId) isLikedByMe,
    required void Function(FeedItem? item) onData,
  }) {
    return _postsRef.doc(postId).snapshots().listen((doc) {
      if (!doc.exists) {
        onData(null);
        return;
      }
      final item = _itemFromDoc(doc, isLikedByMe(doc.id));
      onData(item.hidden ? null : item);
    });
  }

  // -----------------------------------------------------------------------
  // Images
  // -----------------------------------------------------------------------

  /// Métadonnées explicites, obligatoires : `putFile` sans métadonnées
  /// n'envoie aucun type MIME côté Android (le SDK natif ne le devine pas
  /// d'après le chemin du fichier), l'objet arrive donc en
  /// `application/octet-stream` — et les règles Storage, qui exigent
  /// `request.resource.contentType.matches('image/.*')`, refusent l'écriture.
  /// C'est ce qui empêchait toute publication de photo.
  ///
  /// `cacheControl` : le nom de fichier porte un horodatage unique, son
  /// contenu ne changera jamais. Le laisser en cache un an côté CDN et
  /// navigateur supprime les re-téléchargements et raccourcit d'autant
  /// l'affichage des photos déjà vues.
  static final _imageMetadata = SettableMetadata(
    contentType: 'image/jpeg',
    cacheControl: 'public, max-age=31536000, immutable',
  );

  /// Les noms de fichier portent un horodatage : à l'édition d'un post, des
  /// noms indexés à partir de 0 écraseraient les images conservées, qui
  /// vivent dans le même dossier `posts/{postId}/`.
  ///
  /// Les envois sont menés de front : en série, cinq photos additionnent
  /// cinq allers-retours réseau avant que la publication n'apparaisse.
  /// `Future.wait` conserve l'ordre des résultats, donc celui des photos.
  Future<List<String>> _uploadImages(
    List<String> localPaths,
    String storagePath,
  ) async {
    if (localPaths.isEmpty) return [];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // Un envoi après l'autre, pas tous en parallèle : sur une connexion
    // mobile, N envois simultanés se partagent la même bande passante,
    // chacun devient N fois plus lent et finit par buter sur le délai de
    // nouvelle tentative de Storage — d'où des publications à plusieurs
    // photos qui échouaient là où une seule photo passait. En série,
    // chaque photo dispose de tout le débit et le temps total est le
    // même, à l'échec près.
    final urls = <String>[];
    for (var i = 0; i < localPaths.length; i++) {
      urls.add(
        await _uploadImage(localPaths[i], '$storagePath/${stamp}_$i.jpg'),
      );
    }
    return urls;
  }

  Future<String> _uploadImage(String localPath, String fullPath) async {
    final ref = _storage.ref(fullPath);
    await (await LocalMedia.upload(ref, localPath, _imageMetadata));
    return ref.getDownloadURL();
  }

  /// Envoie la vidéo (déjà compressée si besoin) et sa vignette.
  Future<UploadedVideo> _uploadVideo(
    PostVideoDraft video,
    String folder,
    void Function(double progress)? onProgress,
  ) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // L'extension suit le fichier réel : un `.mov` stocké sous `.mp4` se
    // lit mal côté Android.
    final ext = video.path.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    final ref = _storage.ref('$folder/video_$stamp.$ext');
    final task = await LocalMedia.upload(
      ref,
      video.path,
      SettableMetadata(
        contentType: ext == 'mov' ? 'video/quicktime' : 'video/mp4',
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    final sub = onProgress == null
        ? null
        : task.snapshotEvents.listen((s) {
            if (s.totalBytes > 0) {
              onProgress(s.bytesTransferred / s.totalBytes);
            }
          }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub?.cancel();
    }
    final url = await ref.getDownloadURL();

    String? thumbUrl;
    final thumb = video.thumbPath;
    if (thumb != null) {
      try {
        thumbUrl = await _uploadImage(thumb, '$folder/video_${stamp}_thumb.jpg');
      } on Object catch (_) {
        // Sans vignette, la carte affiche une tuile : pas de quoi échouer.
      }
    }
    return UploadedVideo(
      url: url,
      thumbUrl: thumbUrl,
      durationMs: video.durationMs,
      aspectRatio: video.aspectRatio,
    );
  }

  /// Effacement au mieux : une image déjà absente (double suppression,
  /// purge serveur passée avant) ne doit pas faire échouer l'opération
  /// utilisateur qui l'a déclenchée.
  Future<void> _deleteImagesByUrl(Iterable<String> urls) async {
    for (final url in urls) {
      try {
        await _storage.refFromURL(url).delete();
      } on FirebaseException catch (_) {
        // Fichier introuvable ou droits insuffisants — la purge serveur
        // (onPostDeleted) rattrapera le cas échéant.
      }
    }
  }
}

/// État d'un « j'aime » tel que le serveur l'a réellement enregistré.
/// Renvoyé par [FeedService.setLike] pour que l'interface se recale sur la
/// vérité plutôt que sur un compteur local incrémenté à l'aveugle.
class LikeState {
  const LikeState({required this.likesCount, required this.likedByMe});

  final int likesCount;
  final bool likedByMe;
}

/// Vidéo choisie pour une publication, prête à partir (déjà compressée si
/// elle dépassait le seuil).
class PostVideoDraft {
  const PostVideoDraft({
    required this.path,
    this.thumbPath,
    this.durationMs,
    this.aspectRatio,
  });

  final String path;
  final String? thumbPath;
  final int? durationMs;
  final double? aspectRatio;
}

/// Vidéo envoyée : ce qu'on écrit dans le document.
class UploadedVideo {
  const UploadedVideo({
    required this.url,
    this.thumbUrl,
    this.durationMs,
    this.aspectRatio,
  });

  final String url;
  final String? thumbUrl;
  final int? durationMs;
  final double? aspectRatio;
}
