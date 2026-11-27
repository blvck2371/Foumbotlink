import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/pro_listing.dart';
import '../utils/local_media.dart';

/// Annuaire des professionnels — `directory/{ownerUid}`.
///
/// Sous-collections :
/// - `contact/main` : téléphone et WhatsApp, lisibles des seuls comptes
///   connectés ;
/// - `contactedBy/{uid}` : trace d'une prise de contact, qui ouvre le
///   droit de laisser un avis ;
/// - `reviews/{uid}` : un avis par personne. Les moyennes et le score de
///   classement sont recalculés par `onProReviewWritten`.
///
/// Les lectures affichées passent par des flux (`snapshots`) : Firestore
/// sert d'abord son cache local — l'annuaire s'ouvre sans attendre le
/// réseau — puis pousse chaque changement (nouvel avis, note recalculée,
/// fiche modifiée) sans rechargement.
class DirectoryService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  /// Taille maximale de l'annuaire suivi. À l'échelle d'une commune, tout
  /// tient en un flux : filtres par métier et recherche se font ensuite
  /// en mémoire, sans index composite ni aller-retour réseau.
  static const fetchLimit = 500;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('directory');

  DocumentReference<Map<String, dynamic>> _contactRef(String proUid) =>
      _col.doc(proUid).collection('contact').doc('main');

  CollectionReference<Map<String, dynamic>> _reviews(String proUid) =>
      _col.doc(proUid).collection('reviews');

  /// Annuaire complet, du mieux classé au moins bien classé.
  Stream<List<ProListing>> watchAll() => _col
      .orderBy('rankScore', descending: true)
      .limit(fetchLimit)
      .snapshots()
      .map((snap) => snap.docs.map(ProListing.fromDoc).toList()
        ..sort(compareRank));

  /// À score égal, le plus d'avis passe devant.
  static int compareRank(ProListing a, ProListing b) {
    final byScore = b.rankScore.compareTo(a.rankScore);
    if (byScore != 0) return byScore;
    return b.ratingCount.compareTo(a.ratingCount);
  }

  /// Une fiche, `null` si elle n'existe pas (ou plus).
  Stream<ProListing?> watch(String proUid) => _col
      .doc(proUid)
      .snapshots()
      .map((doc) => doc.exists ? ProListing.fromDoc(doc) : null);

  Future<ProListing?> fetch(String proUid) async {
    final doc = await _col.doc(proUid).get();
    return doc.exists ? ProListing.fromDoc(doc) : null;
  }

  Future<ProContact> contact(String proUid) async {
    final doc = await _contactRef(proUid).get();
    return ProContact.fromMap(doc.data());
  }

  /// Avis récents. Un avis qu'on vient de publier y apparaît aussitôt
  /// (écriture locale en attente), avant même la confirmation serveur.
  Stream<List<ProReview>> watchReviews(String proUid, {int limit = 50}) =>
      _reviews(proUid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots(includeMetadataChanges: false)
          .map((snap) => snap.docs.map(ProReview.fromDoc).toList());

  /// L'utilisateur a-t-il contacté ce professionnel ? Suivi en direct :
  /// le bouton « Noter » s'active dès l'appel ou le message.
  Stream<bool> watchCanReview({
    required String proUid,
    required String myUid,
  }) {
    if (myUid.isEmpty || myUid == proUid) return Stream.value(false);
    return _col
        .doc(proUid)
        .collection('contactedBy')
        .doc(myUid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((Object _) => false);
  }

  /// Crée ou met à jour la fiche du compte courant.
  ///
  /// [photos] mélange URLs déjà en ligne et fichiers locaux à envoyer ;
  /// l'ordre est conservé. Les photos retirées par rapport à
  /// [previousPhotos] sont effacées du stockage.
  Future<ProListing> save(
    ProListing listing,
    ProContact contact, {
    List<String> photos = const [],
    List<String> previousPhotos = const [],
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    // En série : en parallèle, chaque envoi n'a qu'une fraction du débit
    // et un envoi à plusieurs photos échoue là où une seule passe.
    for (var i = 0; i < photos.length && i < ProListing.maxPhotos; i++) {
      final p = photos[i];
      if (!LocalMedia.isLocal(p)) {
        urls.add(p);
        continue;
      }
      final ref = _storage.ref('directory/${listing.id}/${stamp}_$i.jpg');
      await (await LocalMedia.upload(ref, p, _imageMetadata));
      urls.add(await ref.getDownloadURL());
    }
    final saved = listing.copyWith(photos: urls);

    final ref = _col.doc(listing.id);
    final exists = (await ref.get()).exists;
    final batch = _db.batch();
    if (exists) {
      batch.update(ref, saved.toEditableMap());
    } else {
      batch.set(ref, saved.toCreateMap());
    }
    batch.set(_contactRef(listing.id), contact.toMap());
    await batch.commit();

    for (final old in previousPhotos) {
      if (!urls.contains(old)) await _deletePhoto(old);
    }
    return saved;
  }

  /// Sans type MIME, l'objet arriverait en `application/octet-stream` et
  /// la règle Storage `contentType.matches('image/.*')` refuserait l'envoi.
  static final _imageMetadata = SettableMetadata(
    contentType: 'image/jpeg',
    cacheControl: 'public, max-age=31536000, immutable',
  );

  Future<void> _deletePhoto(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } on Object catch (_) {
      // Fichier déjà absent : sans conséquence.
    }
  }

  /// Retire la fiche de l'annuaire et ses photos. Les avis restent en base
  /// (ils reviendraient avec une nouvelle fiche) mais ne sont plus visibles.
  Future<void> delete(String proUid) async {
    final current = await fetch(proUid);
    final batch = _db.batch()
      ..delete(_contactRef(proUid))
      ..delete(_col.doc(proUid));
    await batch.commit();
    for (final url in current?.photos ?? const <String>[]) {
      await _deletePhoto(url);
    }
  }

  /// Trace une prise de contact (appel, WhatsApp, message). C'est elle qui
  /// autorise ensuite à noter le professionnel.
  Future<void> recordContact({
    required String proUid,
    required String myUid,
    required String channel,
  }) async {
    if (myUid.isEmpty || myUid == proUid) return;
    try {
      await _col.doc(proUid).collection('contactedBy').doc(myUid).set({
        'channel': channel,
        'at': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (_) {
      // Le contact lui-même ne doit pas échouer pour une trace manquée.
    }
  }

  /// Publie l'avis sans attendre le serveur : le flux des avis l'affiche
  /// aussitôt depuis le cache local. Une erreur de règles remonte quand
  /// même au [Future].
  Future<void> submitReview({
    required String proUid,
    required ProReview review,
  }) => _reviews(proUid).doc(review.reviewerUid).set(review.toMap());

  Future<void> deleteReview({required String proUid, required String myUid}) =>
      _reviews(proUid).doc(myUid).delete();
}
