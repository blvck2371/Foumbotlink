/// Un statut : une vidéo, une photo, ou un fond coloré porteur de texte,
/// publié depuis le profil et qui disparaît **24 heures** plus tard.
///
/// L'expiration est portée par le document lui-même ([expiresAt]) plutôt
/// que déduite de [createdAt] à la lecture : c'est ce qui permet à la
/// requête Firestore de ne ramener que les statuts encore vivants (un
/// `where('expiresAt', isGreaterThan: now)`), au ménage programmé côté
/// serveur de les retrouver, et à une éventuelle règle TTL Firestore de
/// s'appuyer dessus. Le client ne fait donc jamais confiance à l'horloge
/// de l'appareil pour décider ce qui doit encore s'afficher — il filtre en
/// plus localement, au cas où la purge serveur aurait du retard.
/// Ce qu'un statut donne à voir. Une seule forme par statut : la vidéo et
/// la photo s'excluent, le texte sert alors de légende.
enum StatusKind { text, image, video }

class UserStatus {
  UserStatus({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    required this.expiresAt,
    this.authorPhotoUrl,
    this.imageUrl,
    this.videoUrl,
    this.text = '',
    this.backgroundColor = defaultBackgroundColor,
    this.viewsCount = 0,
    this.viewedByMe = false,
    this.likesCount = 0,
    this.likedByMe = false,
    this.repostOfId,
    this.repostOfAuthorUid,
    this.repostOfAuthorName,
    this.hidden = false,
  });

  /// Durée de vie d'un statut. Une constante partagée : le client la
  /// calcule à la création, le ménage serveur s'y réfère.
  static const lifetime = Duration(hours: 24);

  /// Fond par défaut d'un statut texte (orange Foumbot).
  static const defaultBackgroundColor = 0xFFEF6C00;

  final String id;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Photo du statut. `null` pour un statut vidéo ou purement textuel.
  final String? imageUrl;

  /// Vidéo du statut. `null` pour un statut photo ou textuel.
  final String? videoUrl;

  /// Légende (statut photo ou vidéo) ou contenu (statut texte).
  final String text;

  /// Couleur de fond d'un statut texte, en ARGB.
  final int backgroundColor;

  /// Nombre de personnes distinctes ayant ouvert le statut — la vérité
  /// est la sous-collection `statuses/{id}/views/{uid}`, ce champ n'en est
  /// que le résumé, seul champ qu'un tiers peut faire bouger (d'un cran).
  final int viewsCount;

  /// Vrai si la session courante a déjà vu ce statut. Résolu localement
  /// contre le miroir personnel `users/{uid}/statusViews`, jamais lu dans
  /// le document du statut.
  final bool viewedByMe;

  /// Nombre de « j'aime ». Comme pour les vues, la vérité est la
  /// sous-collection `statuses/{id}/likes/{uid}` ; ce champ n'en est que
  /// le résumé, et ne peut bouger que d'un cran à la fois.
  final int likesCount;

  /// Vrai si la session a aimé ce statut. Résolu localement contre le
  /// miroir personnel `users/{uid}/statusLikes`, jamais lu dans le
  /// document — savoir ce que *j'ai* aimé tient en une requête, là où
  /// interroger chaque statut en coûterait une par statut affiché.
  final bool likedByMe;

  /// Statut d'origine, quand celui-ci est un repartage. Le média est
  /// recopié côté serveur dans l'espace du repartageur
  /// (`onStatusCreated`) : sans cette copie, l'auteur d'origine
  /// supprimant son statut ferait disparaître l'image de tous les
  /// repartages.
  final String? repostOfId;
  final String? repostOfAuthorUid;
  final String? repostOfAuthorName;

  /// Masqué par la modération (`onReportCreated`, au-delà du seuil de
  /// signalements). Son auteur le voit encore ; les autres, non.
  final bool hidden;

  bool get isRepost => repostOfId != null && repostOfId!.isNotEmpty;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  bool get hasMedia => hasImage || hasVideo;

  bool get hasText => text.trim().isNotEmpty;

  /// La vidéo l'emporte sur la photo : un statut ne porte jamais les deux,
  /// mais l'ordre rend la lecture déterministe si un document ancien ou
  /// bricolé en contenait deux.
  StatusKind get kind => hasVideo
      ? StatusKind.video
      : hasImage
      ? StatusKind.image
      : StatusKind.text;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  /// Ce qu'il reste à vivre au statut, jamais négatif.
  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// « il reste 5 h » / « il reste 12 min » — affiché à l'auteur, pour qui
  /// la date de disparition compte plus que la date de publication.
  String get remainingLabel {
    final left = remaining;
    if (left == Duration.zero) return 'expiré';
    if (left.inHours >= 1) return 'il reste ${left.inHours} h';
    final minutes = left.inMinutes;
    return 'il reste ${minutes < 1 ? 1 : minutes} min';
  }

  /// « à l'instant » / « il y a 3 h » — affiché aux autres.
  String get ageLabel {
    final age = DateTime.now().difference(createdAt);
    if (age.inMinutes < 1) return 'à l’instant';
    if (age.inMinutes < 60) return 'il y a ${age.inMinutes} min';
    return 'il y a ${age.inHours} h';
  }

  /// « 12 vues » — au singulier près.
  String get viewsLabel =>
      viewsCount <= 1 ? '$viewsCount vue' : '$viewsCount vues';

  /// « 3 j'aime » — au singulier près.
  String get likesLabel =>
      likesCount <= 1 ? '$likesCount j’aime' : '$likesCount j’aime';

  /// Aperçu d'une ligne, repris dans la citation d'un message de chat :
  /// c'est ce que voit l'auteur quand quelqu'un réagit à son statut.
  String get shortPreview {
    if (hasText) {
      final line = text.trim().replaceAll('\n', ' ');
      return line.length > 60 ? '${line.substring(0, 60)}…' : line;
    }
    return switch (kind) {
      StatusKind.video => '🎬 Vidéo',
      StatusKind.image => '📷 Photo',
      StatusKind.text => 'Statut',
    };
  }

  UserStatus copyWith({
    int? viewsCount,
    bool? viewedByMe,
    int? likesCount,
    bool? likedByMe,
  }) {
    return UserStatus(
      id: id,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: createdAt,
      expiresAt: expiresAt,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      text: text,
      backgroundColor: backgroundColor,
      viewsCount: viewsCount ?? this.viewsCount,
      viewedByMe: viewedByMe ?? this.viewedByMe,
      likesCount: likesCount ?? this.likesCount,
      likedByMe: likedByMe ?? this.likedByMe,
      repostOfId: repostOfId,
      repostOfAuthorUid: repostOfAuthorUid,
      repostOfAuthorName: repostOfAuthorName,
      hidden: hidden,
    );
  }
}

/// Une personne ayant regardé un statut — visible du seul auteur.
class StatusViewer {
  const StatusViewer({
    required this.uid,
    required this.name,
    required this.viewedAt,
    this.photoUrl,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final DateTime viewedAt;
}
