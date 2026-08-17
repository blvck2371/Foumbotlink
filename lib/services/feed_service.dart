import '../models/feed_item.dart';

/// Source locale (mock) pour le fil — pagination + likes / commentaires.
class FeedService {
  static const pageSize = 8;

  final Map<String, FeedItem> _store = {};

  Future<List<FeedItem>> fetchPage({
    required int page,
    FeedFilter filter = FeedFilter.all,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 420));

    final generated = List<FeedItem>.generate(pageSize, (i) {
      final index = page * pageSize + i;
      return _buildItem(index: index, filter: filter);
    });

    return generated.map((item) {
      final existing = _store[item.id];
      if (existing != null) return existing;
      _store[item.id] = item;
      return item;
    }).toList();
  }

  FeedItem? getById(String id) => _store[id];

  FeedItem? toggleLike(String id) {
    final item = _store[id];
    if (item == null) return null;
    final liked = !item.likedByMe;
    final updated = item.copyWith(
      likedByMe: liked,
      likesCount: (item.likesCount + (liked ? 1 : -1)).clamp(0, 999999),
    );
    _store[id] = updated;
    return updated;
  }

  /// Fil imbriqué à profondeur illimitée (façon TikTok) : un commentaire
  /// peut être posté à la racine, ou en réponse à N'IMPORTE QUEL
  /// commentaire existant — racine ou réponse déjà elle-même imbriquée.
  /// La réponse est alors attachée directement sous le commentaire ciblé,
  /// pas "remontée" vers la racine du fil.
  FeedItem? addComment(String postId, String text, {String? parentCommentId}) {
    final item = _store[postId];
    final trimmed = text.trim();
    if (item == null || trimmed.isEmpty) return null;

    if (parentCommentId == null) {
      final comment = FeedComment(
        id: _nextCommentId(postId),
        authorName: 'Vous',
        text: trimmed,
        createdAt: DateTime.now(),
      );
      // Le nouveau commentaire apparaît en tête, immédiatement visible
      // (comme quand on publie un commentaire sur TikTok/Facebook).
      final updated = item.copyWith(comments: [comment, ...item.comments]);
      _store[postId] = updated;
      return updated;
    }

    final parent = _find(item.comments, parentCommentId);
    if (parent == null) return null;

    final comment = FeedComment(
      id: _nextCommentId(postId),
      authorName: 'Vous',
      text: trimmed,
      createdAt: DateTime.now(),
      replyToName: parent.authorName,
    );

    final comments = _insertReply(item.comments, parentCommentId, comment);
    if (comments == null) return null;

    final updated = item.copyWith(comments: comments);
    _store[postId] = updated;
    return updated;
  }

  FeedItem? toggleCommentLike(String postId, String commentId) {
    final item = _store[postId];
    if (item == null) return null;

    final comments = _updateOne(item.comments, commentId, _toggled);
    if (comments == null) return null;

    final updated = item.copyWith(comments: comments);
    _store[postId] = updated;
    return updated;
  }

  /// Cherche un commentaire par id, à n'importe quelle profondeur.
  FeedComment? _find(List<FeedComment> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _find(node.replies, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Retourne une nouvelle liste où le commentaire `id` a été remplacé par
  /// `transform(commentaire)`, en descendant récursivement dans les
  /// réponses si besoin. `null` si l'id est introuvable dans cette liste.
  List<FeedComment>? _updateOne(
    List<FeedComment> nodes,
    String id,
    FeedComment Function(FeedComment) transform,
  ) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.id == id) {
        return [...nodes]..[i] = transform(node);
      }
      final updatedReplies = _updateOne(node.replies, id, transform);
      if (updatedReplies != null) {
        return [...nodes]..[i] = node.copyWith(replies: updatedReplies);
      }
    }
    return null;
  }

  /// Insère `reply` sous le commentaire `parentId`, à n'importe quelle
  /// profondeur. `null` si `parentId` est introuvable dans cette liste.
  List<FeedComment>? _insertReply(
    List<FeedComment> nodes,
    String parentId,
    FeedComment reply,
  ) {
    return _updateOne(
      nodes,
      parentId,
      (node) => node.copyWith(replies: [...node.replies, reply]),
    );
  }

  FeedComment _toggled(FeedComment c) {
    final liked = !c.likedByMe;
    return c.copyWith(
      likedByMe: liked,
      likesCount: (c.likesCount + (liked ? 1 : -1)).clamp(0, 999999),
    );
  }

  int _commentSeq = 0;

  String _nextCommentId(String postId) => 'c_${postId}_${_commentSeq++}';

  FeedItem _buildItem({
    required int index,
    required FeedFilter filter,
  }) {
    final type = switch (filter) {
      FeedFilter.infos => FeedType.info,
      FeedFilter.annonces => FeedType.annonce,
      FeedFilter.population => FeedType.post,
      FeedFilter.all => switch (index % 5) {
          0 => FeedType.annonce,
          1 || 2 => FeedType.post,
          _ => FeedType.info,
        },
    };

    final id = 'feed_${filter.name}_$index';
    final publishedAt =
        DateTime.now().subtract(Duration(hours: index * 4 + 1));

    switch (type) {
      case FeedType.annonce:
        return FeedItem(
          id: id,
          type: type,
          title: _annonceTitles[index % _annonceTitles.length],
          body: _annonceBodies[index % _annonceBodies.length],
          authorName: 'Mairie de Foumbot',
          authorSubtitle: 'Annonce officielle',
          publishedAt: publishedAt,
          likesCount: 12 + (index % 40),
          imageUrls: _seedImages(id, index),
          comments: _seedComments(id, index, official: true),
        );
      case FeedType.info:
        return FeedItem(
          id: id,
          type: type,
          title: _infoTitles[index % _infoTitles.length],
          body: _infoBodies[index % _infoBodies.length],
          authorName: 'Commune de Foumbot',
          authorSubtitle: 'Information municipale',
          publishedAt: publishedAt,
          likesCount: 8 + (index % 25),
          imageUrls: _seedImages(id, index),
          comments: _seedComments(id, index, official: true),
        );
      case FeedType.post:
        final author = _citizenNames[index % _citizenNames.length];
        return FeedItem(
          id: id,
          type: type,
          title: _postTitles[index % _postTitles.length],
          body: _postBodies[index % _postBodies.length],
          authorName: author,
          authorSubtitle: 'Habitant·e de Foumbot',
          publishedAt: publishedAt,
          likesCount: 3 + (index % 18),
          imageUrls: _seedImages(id, index),
          comments: _seedComments(id, index, official: false),
        );
    }
  }

  /// Le fil est un vrai mixte, comme sur Facebook : la majorité des
  /// publications sont purement textuelles, une minorité porte 1 à 3
  /// photos. URLs déterministes (basées sur l'id du post) pour que la
  /// même publication affiche toujours la même image. Les formats
  /// couvrent paysage, portrait, carré et portrait "story" pour exercer
  /// le rendu quel que soit le sens de la photo d'origine.
  static const _seedImageSizes = [
    (900, 600), // paysage 3:2
    (600, 900), // portrait 2:3
    (800, 800), // carré
    (720, 1280), // portrait 9:16 (style story)
    (1280, 720), // paysage 16:9
  ];

  List<String> _seedImages(String postId, int index) {
    // Sur 7 publications : 4 sans photo, 1 avec une, 1 avec deux, 1 avec
    // trois — la majorité reste du texte pur.
    final photoCount = switch (index % 7) {
      2 => 1,
      4 => 2,
      6 => 3,
      _ => 0,
    };
    if (photoCount == 0) return [];
    return List.generate(photoCount, (i) {
      final (w, h) = _seedImageSizes[(index + i) % _seedImageSizes.length];
      return 'https://picsum.photos/seed/$postId-$i/$w/$h';
    });
  }

  List<FeedComment> _seedComments(
    String postId,
    int index, {
    required bool official,
  }) {
    final count = index % 4;
    if (count == 0) return [];
    return List.generate(count, (i) {
      final commentId = '${postId}_seed_$i';
      final author = _citizenNames[(index + i + 1) % _citizenNames.length];
      final replyAuthor = _citizenNames[(index + 3) % _citizenNames.length];
      final nestedAuthor = _citizenNames[(index + 5) % _citizenNames.length];
      // Le premier commentaire de chaque post porte un fil à 3 niveaux
      // (commentaire → réponse → réponse-à-la-réponse) pour illustrer
      // l'imbrication à profondeur illimitée.
      final replies = i == 0
          ? [
              FeedComment(
                id: '${commentId}_r0',
                authorName: replyAuthor,
                text: 'Je suis d’accord avec toi.',
                createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
                likesCount: 1 + (index % 3),
                replies: [
                  FeedComment(
                    id: '${commentId}_r0_r0',
                    authorName: nestedAuthor,
                    text: 'Exactement, merci pour le rappel.',
                    createdAt:
                        DateTime.now().subtract(const Duration(minutes: 22)),
                    replyToName: replyAuthor,
                    likesCount: index % 4,
                  ),
                ],
              ),
              FeedComment(
                id: '${commentId}_r1',
                authorName: author,
                text: 'On se tient au courant.',
                createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
              ),
            ]
          : <FeedComment>[];
      return FeedComment(
        id: commentId,
        authorName: author,
        text: official
            ? _officialReplies[i % _officialReplies.length]
            : _citizenReplies[i % _citizenReplies.length],
        createdAt: DateTime.now().subtract(Duration(hours: i + 1)),
        likesCount: 2 + ((index + i) % 8),
        replies: replies,
      );
    });
  }

  static const _citizenNames = [
    'Amina N.',
    'Jean-Paul T.',
    'Christelle M.',
    'Ibrahim K.',
    'Sandrine F.',
    'Paul D.',
  ];

  static const _postTitles = [
    'Idée : marché de nuit le week-end',
    'Merci aux voisins du quartier Est',
    'Proposition d’éclairage près de l’école',
    'Recherche covoiturage vers Bafoussam',
    'Grande collecte de livres pour la jeunesse',
  ];

  static const _postBodies = [
    'Et si on organisait un petit marché de nuit le samedi ? Ça dynamiserait le centre-ville.',
    'Un grand merci à ceux qui ont aidé après la pluie d’hier. Solidarité foumbotienne !',
    'Le chemin vers l’école primaire est trop sombre le soir. Qui relayerait à la mairie ?',
    'Je pars demain matin vers Bafoussam, 2 places dispo. Écrivez-moi en commentaire.',
    'On lance une collecte de livres pour les enfants. Point de dépôt chez moi, quartier Centre.',
  ];

  static const _citizenReplies = [
    'Très bonne idée, je suis partant·e !',
    'On peut en parler au prochain conseil de quartier.',
    'Merci pour le partage 🙏',
    'Je peux aider si besoin.',
  ];

  static const _officialReplies = [
    'Merci, nous prenons note de votre retour.',
    'Plus d’informations seront publiées bientôt.',
    'Vous pouvez aussi passer à l’accueil de la mairie.',
  ];

  static const _infoTitles = [
    'Réhabilitation de la voie principale',
    'Collecte des ordures : nouveau calendrier',
    'Ouverture de la médiathèque communale',
    'Campagne de vaccination au centre de santé',
    'Réunion de quartier — secteur centre',
  ];

  static const _infoBodies = [
    'Les travaux avancent sur l’axe principal. Circulation alternée jusqu’à vendredi. Évitez les heures de pointe.',
    'Nouveaux horaires de passage dans les quartiers. Consultez le planning affiché en mairie et sur Foumbot Link.',
    'La médiathèque accueille le public du mardi au samedi, 9h–17h. Entrée libre pour tous les habitants.',
    'Vaccination gratuite pour les enfants et les personnes vulnérables ce week-end au centre de santé.',
    'Échange avec les chefs de quartier sur la sécurité et l’éclairage public. Ouvert à toutes et tous.',
  ];

  static const _annonceTitles = [
    'Avis de recrutement — services municipaux',
    'Coupure d’eau programmée — secteur Est',
    'Appel à projets jeunes de Foumbot',
    'Marché communal : modification des jours',
    'Cérémonie officielle à la mairie',
  ];

  static const _annonceBodies = [
    'La mairie recrute du personnel administratif. Dossiers à déposer avant le 30 du mois à l’accueil.',
    'Interruption du service entre 8h et 14h pour maintenance du réseau. Préparez de l’eau potable.',
    'Déposez vos idées et initiatives citoyennes à l’accueil de la mairie ou via Foumbot Link.',
    'Le grand marché se tiendra désormais les mercredis et samedis. Merci de votre compréhension.',
    'La population est invitée à la cérémonie de remise des distinctions ce samedi à 10h.',
  ];
}
