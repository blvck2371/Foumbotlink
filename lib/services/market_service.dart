import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/market_filters.dart';
import '../models/market_item.dart';
import '../models/market_text.dart';

/// Accès Firestore/Storage du marché.
///
/// ## Pourquoi une « fenêtre » plutôt qu'une pagination par curseur
///
/// L'affichage par défaut est aléatoire (voir [MarketSort]). Un ordre
/// aléatoire et une pagination par curseur ne peuvent pas coexister : le
/// curseur suppose un ordre stable côté serveur, que le mélange détruit —
/// une annonce réapparaîtrait page 3 pendant qu'une autre disparaîtrait.
///
/// On charge donc une **fenêtre** d'au plus [windowSize] annonces en une
/// requête, et la pagination devient locale (le contrôleur découpe la
/// liste mélangée). À l'échelle d'une commune c'est la bonne forme :
/// une seule requête, tout est filtrable et triable sans index
/// supplémentaire, et ça fonctionne depuis le cache quand le réseau est
/// mauvais. Au-delà de quelques milliers d'annonces il faudrait passer à
/// un champ `random` interrogé par plages — prématuré aujourd'hui.
class MarketService {
  /// Nombre maximum d'annonces chargées en une fois.
  static const windowSize = 150;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _marketRef =>
      _db.collection('market');

  DocumentReference<Map<String, dynamic>> _contactRef(String itemId) =>
      _marketRef.doc(itemId).collection('contact').doc('info');

  // -----------------------------------------------------------------------
  // Lecture
  // -----------------------------------------------------------------------

  /// Charge la fenêtre d'annonces correspondant à [filters].
  ///
  /// Seuls la catégorie, le type et la recherche partent au serveur ; le
  /// prix, l'état et le lieu sont appliqués par le contrôleur sur le
  /// résultat, pour ne pas multiplier les index composites par
  /// combinaison de filtres.
  ///
  /// [sellerUid] non nul = « Mes annonces » : on renvoie alors *tout* ce
  /// qu'a publié la personne, y compris ses annonces vendues et expirées,
  /// qu'elle doit pouvoir relancer ou remettre en vente.
  ///
  /// [preferCache] sert le premier affichage depuis le cache local pour
  /// que la grille apparaisse sans aller-retour réseau ; un
  /// rafraîchissement demandé par l'utilisateur ne doit jamais l'utiliser.
  Future<List<MarketItem>> fetchWindow({
    MarketFilters filters = const MarketFilters(),
    String? sellerUid,
    bool preferCache = false,
  }) async {
    final tokens = searchTokens(filters.query);
    final mine = sellerUid != null;

    Query<Map<String, dynamic>> q = _marketRef;

    if (mine) {
      // « Mes annonces » : un seul index (sellerUid + bumpedAt), les
      // filtres de catégorie/type s'appliquent côté client.
      q = q.where('sellerUid', isEqualTo: sellerUid);
    } else {
      if (filters.category != null) {
        q = q.where('category', isEqualTo: filters.category!.name);
      }
      if (filters.listingType != null) {
        q = q.where('listingType', isEqualTo: filters.listingType!.name);
      }
      if (tokens.isNotEmpty) {
        // Recherche serveur : le premier jeton filtre, les suivants
        // affinent côté client (Firestore n'accepte qu'un
        // `array-contains` par requête).
        q = q.where('keywords', arrayContains: tokens.first);
      } else {
        // Hors recherche, on écarte les annonces vendues dès la requête
        // — elles ne doivent plus apparaître du tout.
        q = q.where('sold', isEqualTo: false);
      }
    }

    q = q.orderBy('bumpedAt', descending: true).limit(windowSize);

    final snapshot =
        (preferCache ? await _fromCache(q) : null) ?? await q.get();
    var results = snapshot.docs.map(_itemFromDoc).toList();

    if (!mine) {
      results = results.where((e) => e.isPublic).toList();
      if (tokens.length > 1) {
        final rest = tokens.skip(1);
        results = results
            .where((e) => rest.every((t) => e.keywords.contains(t)))
            .toList();
      }
    }

    return results;
  }

  /// Lecture d'une requête dans le cache local, ou `null` si le cache ne
  /// peut pas y répondre.
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

  /// Les autres annonces **encore en vente** d'un vendeur, hors celle
  /// qu'on est en train de regarder.
  ///
  /// Répond au réflexe « qu'est-ce qu'il vend d'autre ? », qui n'avait
  /// aucune réponse dans l'app : il fallait retourner au marché et
  /// chercher son nom à la main.
  ///
  /// Les annonces vendues, expirées ou masquées sont écartées : proposer
  /// ce qui n'est plus disponible ferait perdre un aller-retour à
  /// l'acheteur et une explication au vendeur. On lit un peu plus large
  /// que [limit] pour que ce tri local ne vide pas la liste.
  Future<List<MarketItem>> otherListingsBySeller({
    required String sellerUid,
    required String excludeId,
    int limit = 8,
  }) async {
    if (sellerUid.isEmpty) return const [];
    try {
      final snap = await _marketRef
          .where('sellerUid', isEqualTo: sellerUid)
          .orderBy('bumpedAt', descending: true)
          .limit(limit * 3)
          .get();

      return snap.docs
          .map(_itemFromDoc)
          .where((e) => e.id != excludeId && e.isPublic)
          .take(limit)
          .toList();
    } on FirebaseException catch (e) {
      // Section d'appoint : son échec ne doit pas abîmer la fiche.
      developer.log(
        'otherListingsBySeller',
        name: 'MarketService',
        error: e,
      );
      return const [];
    }
  }

  /// Les annonces qui ressemblent à [to], classées par pertinence.
  ///
  /// Un vivier est lu par catégorie — le seul filtre que Firestore sait
  /// appliquer utilement ici — puis classé localement par
  /// [marketSimilarityScore]. Lire large et trier ensuite coûte une
  /// requête, là où reproduire ce classement côté serveur en demanderait
  /// plusieurs sans être plus juste.
  ///
  /// Les annonces du même vendeur sont écartées : elles ont déjà leur
  /// propre section sur la fiche, les répéter ici ne ferait qu'occuper la
  /// place de vraies suggestions.
  Future<List<MarketItem>> similarListings({
    required MarketItem to,
    int limit = 8,
    int poolSize = 40,
  }) async {
    try {
      final snap = await _marketRef
          .where('category', isEqualTo: to.category.name)
          .where('sold', isEqualTo: false)
          .orderBy('bumpedAt', descending: true)
          .limit(poolSize)
          .get();

      final scored =
          snap.docs
              .map(_itemFromDoc)
              .where(
                (e) =>
                    e.id != to.id &&
                    e.sellerUid != to.sellerUid &&
                    e.isPublic,
              )
              .map((e) => (item: e, score: marketSimilarityScore(to, e)))
              .where((e) => e.score > 0)
              .toList()
            // À score égal, la plus récemment relancée d'abord : c'est
            // celle dont le vendeur est le plus probablement joignable.
            ..sort((a, b) {
              final byScore = b.score.compareTo(a.score);
              return byScore != 0
                  ? byScore
                  : b.item.bumpedAt.compareTo(a.item.bumpedAt);
            });

      return scored.take(limit).map((e) => e.item).toList();
    } on FirebaseException catch (e) {
      developer.log('similarListings', name: 'MarketService', error: e);
      return const [];
    }
  }

  Future<MarketItem?> getById(String id) async {
    final doc = await _marketRef.doc(id).get();
    if (!doc.exists) return null;
    return _itemFromDoc(doc);
  }

  /// Construit un [MarketItem] depuis un document brut. Public parce que
  /// les favoris relisent les annonces par lots d'ids (voir
  /// `MarketFavoritesService.fetchFavorites`) et doivent les décoder avec
  /// exactement les mêmes règles de repli que la grille.
  MarketItem? parseDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      doc.exists ? _itemFromDoc(doc) : null;

  MarketItem _itemFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final createdAt =
        (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return MarketItem(
      id: doc.id,
      listingType: MarketListingType.parse(d['listingType'] as String?),
      category: MarketCategory.parse(d['category'] as String?),
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      price: (d['price'] as num?)?.toInt() ?? 0,
      negotiable: d['negotiable'] as bool? ?? false,
      priceOnRequest: d['priceOnRequest'] as bool? ?? false,
      condition: ItemCondition.parse(d['condition'] as String?),
      sellerUid: d['sellerUid'] as String? ?? '',
      sellerName: d['sellerName'] as String? ?? '',
      location: d['location'] as String? ?? '',
      createdAt: createdAt,
      // Annonces d'avant la relance : `bumpedAt` absent, on retombe sur
      // la date de publication.
      bumpedAt: (d['bumpedAt'] as Timestamp?)?.toDate() ?? createdAt,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      sold: d['sold'] as bool? ?? false,
      soldAt: (d['soldAt'] as Timestamp?)?.toDate(),
      hasPhone:
          d['hasPhone'] as bool? ??
          (d['sellerPhone'] as String? ?? '').trim().isNotEmpty,
      legacyPhone: d['sellerPhone'] as String? ?? '',
      hidden: d['hidden'] as bool? ?? false,
      viewsCount: (d['viewsCount'] as num?)?.toInt() ?? 0,
      favoritesCount: (d['favoritesCount'] as num?)?.toInt() ?? 0,
      contactsCount: (d['contactsCount'] as num?)?.toInt() ?? 0,
      imageUrls: List<String>.from(d['imageUrls'] ?? const []),
      keywords: List<String>.from(d['keywords'] ?? const []),
    );
  }

  // -----------------------------------------------------------------------
  // Numéro du vendeur
  // -----------------------------------------------------------------------

  /// Récupère le numéro de l'annonce, ou `null` s'il n'y en a pas.
  ///
  /// Le numéro n'est **jamais** dans le document public : il vit dans
  /// `market/{id}/contact/info`, réservé aux comptes connectés. La
  /// contrepartie est cette lecture supplémentaire, faite seulement quand
  /// l'acheteur appuie sur « Afficher le numéro ».
  Future<String?> fetchPhone(MarketItem item) async {
    if (item.legacyPhone.trim().isNotEmpty) return item.legacyPhone.trim();
    if (!item.hasPhone) return null;
    try {
      final doc = await _contactRef(item.id).get();
      final phone = (doc.data()?['phone'] as String?)?.trim();
      return (phone == null || phone.isEmpty) ? null : phone;
    } on FirebaseException catch (_) {
      return null;
    }
  }

  /// Enregistre qu'un acheteur a pris contact : compteur sur l'annonce et
  /// trace `users/{sellerUid}/contactedBy/{buyerUid}`, qui conditionne le
  /// droit de laisser un avis sur ce vendeur (voir firestore.rules).
  Future<void> recordContact({
    required MarketItem item,
    required String buyerUid,
  }) async {
    if (buyerUid.isEmpty || buyerUid == item.sellerUid) return;
    try {
      await _db
          .collection('users')
          .doc(item.sellerUid)
          .collection('contactedBy')
          .doc(buyerUid)
          .set({
            'itemId': item.id,
            'itemTitle': item.title,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await _marketRef.doc(item.id).update({
        'contactsCount': FieldValue.increment(1),
      });
    } on FirebaseException catch (_) {
      // Un compteur d'intérêt n'est pas critique : mieux vaut laisser
      // l'acheteur appeler que bloquer l'action sur un échec d'écriture.
    }
  }

  /// Compteur de vues, incrémenté à l'ouverture du détail.
  Future<void> incrementViews(String id) async {
    try {
      await _marketRef.doc(id).update({'viewsCount': FieldValue.increment(1)});
    } on FirebaseException catch (_) {
      // idem : purement indicatif
    }
  }

  // -----------------------------------------------------------------------
  // Créer / modifier une annonce
  // -----------------------------------------------------------------------

  /// Nombre d'annonces publiées aujourd'hui par [uid] — sert au garde-fou
  /// anti-spam côté client. Le refus qui compte est côté serveur
  /// (`onMarketItemCreated`) ; ici on évite juste à l'utilisateur de
  /// remplir un formulaire pour rien.
  Future<int> countTodayListings(String uid) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final snap = await _marketRef
          .where('sellerUid', isEqualTo: uid)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .count()
          .get();
      return snap.count ?? 0;
    } on FirebaseException catch (_) {
      return 0;
    }
  }

  Future<MarketItem> createListing({
    required MarketListingType listingType,
    required MarketCategory category,
    required String title,
    required String sellerUid,
    required String sellerName,
    required String sellerPhone,
    required String location,
    String description = '',
    int price = 0,
    bool negotiable = false,
    bool priceOnRequest = false,
    ItemCondition? condition,
    List<String> localImagePaths = const [],
  }) async {
    final docRef = _marketRef.doc();
    // L'uid du vendeur ouvre le chemin : c'est lui que les règles Storage
    // lisent pour autoriser l'envoi (voir storage.rules).
    final imageUrls = await _uploadImages(
      localImagePaths,
      'market/$sellerUid/${docRef.id}',
    );

    final now = DateTime.now();
    final expiresAt = now.add(kListingLifetime);
    final phone = sellerPhone.trim();

    await docRef.set({
      'listingType': listingType.name,
      'category': category.name,
      'title': title.trim(),
      'description': description.trim(),
      'keywords': marketKeywords(title, description),
      'price': price,
      'negotiable': negotiable,
      'priceOnRequest': priceOnRequest,
      'condition': condition?.name,
      'sellerUid': sellerUid,
      'sellerName': sellerName.trim(),
      'hasPhone': phone.isNotEmpty,
      'location': location.trim(),
      'createdAt': Timestamp.fromDate(now),
      'bumpedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'sold': false,
      'hidden': false,
      'viewsCount': 0,
      'favoritesCount': 0,
      'contactsCount': 0,
      'imageUrls': imageUrls,
    });

    if (phone.isNotEmpty) {
      await _contactRef(
        docRef.id,
      ).set({'phone': phone, 'sellerUid': sellerUid});
    }

    return MarketItem(
      id: docRef.id,
      listingType: listingType,
      category: category,
      title: title.trim(),
      description: description.trim(),
      keywords: marketKeywords(title, description),
      price: price,
      negotiable: negotiable,
      priceOnRequest: priceOnRequest,
      condition: condition,
      sellerUid: sellerUid,
      sellerName: sellerName.trim(),
      hasPhone: phone.isNotEmpty,
      location: location.trim(),
      createdAt: now,
      bumpedAt: now,
      expiresAt: expiresAt,
      imageUrls: imageUrls,
    );
  }

  /// Modifie une annonce existante.
  ///
  /// [images] mélange les photos conservées (des URL https déjà en
  /// Storage) et les nouvelles (des chemins de fichiers locaux), dans
  /// l'ordre voulu par le vendeur. Les URL absentes de la liste sont
  /// supprimées de Storage.
  Future<MarketItem> updateListing({
    required MarketItem original,
    required MarketListingType listingType,
    required MarketCategory category,
    required String title,
    required String description,
    required String location,
    required String sellerPhone,
    required int price,
    required bool negotiable,
    required bool priceOnRequest,
    ItemCondition? condition,
    required List<String> images,
  }) async {
    final kept = images.where(_isRemoteImage).toList();
    final added = images.where((e) => !_isRemoteImage(e)).toList();
    final removed = original.imageUrls
        .where((url) => !kept.contains(url))
        .toList();

    final uploaded = await _uploadImages(
      added,
      'market/${original.sellerUid}/${original.id}',
    );
    // On reconstruit dans l'ordre choisi : chaque entrée locale est
    // remplacée par l'URL correspondante.
    var next = 0;
    final imageUrls = [
      for (final entry in images)
        if (_isRemoteImage(entry)) entry else uploaded[next++],
    ];

    final phone = sellerPhone.trim();
    await _marketRef.doc(original.id).update({
      'listingType': listingType.name,
      'category': category.name,
      'title': title.trim(),
      'description': description.trim(),
      'keywords': marketKeywords(title, description),
      'price': price,
      'negotiable': negotiable,
      'priceOnRequest': priceOnRequest,
      'condition': condition?.name,
      'location': location.trim(),
      'hasPhone': phone.isNotEmpty,
      'imageUrls': imageUrls,
      'updatedAt': FieldValue.serverTimestamp(),
      // Le champ hérité ne doit pas rester derrière : sinon le numéro
      // continuerait d'être lisible publiquement sur une annonce éditée.
      'sellerPhone': FieldValue.delete(),
    });

    if (phone.isNotEmpty) {
      await _contactRef(
        original.id,
      ).set({'phone': phone, 'sellerUid': original.sellerUid});
    } else {
      try {
        await _contactRef(original.id).delete();
      } on FirebaseException catch (_) {
        // déjà absent
      }
    }

    // Les photos retirées partent en dernier : les règles Storage
    // s'appuient sur le document Firestore, qui doit encore exister.
    for (final url in removed) {
      await _deleteImage(url);
    }

    return original.copyWith(
      listingType: listingType,
      category: category,
      title: title.trim(),
      description: description.trim(),
      keywords: marketKeywords(title, description),
      price: price,
      negotiable: negotiable,
      priceOnRequest: priceOnRequest,
      condition: condition,
      clearCondition: condition == null,
      location: location.trim(),
      hasPhone: phone.isNotEmpty,
      imageUrls: imageUrls,
    );
  }

  static bool _isRemoteImage(String entry) => entry.startsWith('http');

  // -----------------------------------------------------------------------
  // Gestion de son annonce (propriétaire uniquement — voir firestore.rules)
  // -----------------------------------------------------------------------

  /// Marque l'annonce vendue / la remet en vente. Une annonce vendue sort
  /// de la grille publique ; la remettre en vente lui redonne aussi une
  /// durée de vie pleine, sans quoi elle pourrait réapparaître déjà
  /// expirée.
  Future<DateTime?> setSold({required String id, required bool sold}) async {
    if (sold) {
      await _marketRef.doc(id).update({
        'sold': true,
        'soldAt': FieldValue.serverTimestamp(),
      });
      return null;
    }
    final now = DateTime.now();
    final expiresAt = now.add(kListingLifetime);
    await _marketRef.doc(id).update({
      'sold': false,
      'soldAt': FieldValue.delete(),
      'bumpedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
    return expiresAt;
  }

  /// Relance : repart pour [kListingLifetime] et remonte dans la grille.
  /// C'est le pendant gratuit de la « remontée » payante d'un boncoin —
  /// le seul geste possible ici, et il ne coûte rien.
  Future<(DateTime bumpedAt, DateTime expiresAt)> renewListing(
    String id,
  ) async {
    final now = DateTime.now();
    final expiresAt = now.add(kListingLifetime);
    await _marketRef.doc(id).update({
      'bumpedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
    return (now, expiresAt);
  }

  /// Supprime l'annonce. Les photos sont retirées d'abord, tant que le
  /// document existe encore : les règles Storage vérifient `sellerUid` sur
  /// le document Firestore, qui doit donc partir en dernier. Une photo déjà
  /// absente n'interrompt pas l'opération.
  Future<void> deleteListing(MarketItem item) async {
    for (final url in item.imageUrls) {
      await _deleteImage(url);
    }
    try {
      await _contactRef(item.id).delete();
    } on FirebaseException catch (_) {
      // pas de numéro sur cette annonce
    }
    await _marketRef.doc(item.id).delete();
  }

  // -----------------------------------------------------------------------
  // Temps réel
  // -----------------------------------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMarket({
    required void Function(MarketItem item) onAdded,
    required void Function(MarketItem item) onModified,
    required void Function(String id) onRemoved,
  }) {
    return _marketRef
        .orderBy('bumpedAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            switch (change.type) {
              case DocumentChangeType.added:
                onAdded(_itemFromDoc(change.doc));
              case DocumentChangeType.modified:
                onModified(_itemFromDoc(change.doc));
              case DocumentChangeType.removed:
                onRemoved(change.doc.id);
            }
          }
        });
  }

  // -----------------------------------------------------------------------
  // Images
  // -----------------------------------------------------------------------

  /// Les fichiers sont déjà redimensionnés et recompressés à la sélection
  /// (voir `MarketComposeController.pickImages`) : envoyer les originaux
  /// d'un appareil photo récent — plusieurs Mo par photo — coûterait au
  /// vendeur comme à chaque personne qui ouvre la grille, pour une image
  /// affichée sur 200 pixels de large.
  ///
  /// Le nom de fichier porte un horodatage : une annonce éditée plusieurs
  /// fois ne doit pas réécrire par-dessus ses propres photos.
  ///
  /// Les métadonnées sont explicites pour la même raison que côté
  /// publications (voir `FeedService._imageMetadata`) : sans type MIME,
  /// l'objet arrive en `application/octet-stream` et la règle Storage
  /// `contentType.matches('image/.*')` refuse l'envoi.
  static final _imageMetadata = SettableMetadata(
    contentType: 'image/jpeg',
    cacheControl: 'public, max-age=31536000, immutable',
  );

  Future<List<String>> _uploadImages(
    List<String> localPaths,
    String storagePath,
  ) async {
    if (localPaths.isEmpty) return [];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // En série, pour la même raison que les photos de publication (voir
    // `FeedService._uploadImages`) : en parallèle, chaque envoi n'a plus
    // qu'une fraction du débit et l'annonce à plusieurs photos échoue là
    // où une photo seule passe.
    final urls = <String>[];
    for (var i = 0; i < localPaths.length; i++) {
      urls.add(
        await _uploadImage(File(localPaths[i]), '$storagePath/${stamp}_$i.jpg'),
      );
    }
    return urls;
  }

  Future<String> _uploadImage(File file, String fullPath) async {
    final ref = _storage.ref(fullPath);
    await ref.putFile(file, _imageMetadata);
    return ref.getDownloadURL();
  }

  Future<void> _deleteImage(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } on FirebaseException catch (_) {
      // fichier introuvable ou droits insuffisants — sans conséquence
    }
  }
}
