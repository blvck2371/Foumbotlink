import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pro_listing.dart';

/// Annuaire des professionnels — `directory/{ownerUid}`.
///
/// Sous-collections :
/// - `contact/main` : téléphone et WhatsApp, lisibles des seuls comptes
///   connectés ;
/// - `contactedBy/{uid}` : trace d'une prise de contact, qui ouvre le
///   droit de laisser un avis ;
/// - `reviews/{uid}` : un avis par personne. Les moyennes et le score de
///   classement sont recalculés par `onProReviewWritten`.
class DirectoryService {
  final _db = FirebaseFirestore.instance;

  /// Taille maximale de l'annuaire chargé d'un coup. À l'échelle d'une
  /// commune, tout tient en une requête : filtres par métier et
  /// recherche se font ensuite en mémoire, sans index composite ni
  /// aller-retour réseau à chaque frappe.
  static const fetchLimit = 500;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('directory');

  DocumentReference<Map<String, dynamic>> _contactRef(String proUid) =>
      _col.doc(proUid).collection('contact').doc('main');

  CollectionReference<Map<String, dynamic>> _reviews(String proUid) =>
      _col.doc(proUid).collection('reviews');

  /// Annuaire complet, du mieux classé au moins bien classé. À score
  /// égal, le plus d'avis passe devant.
  Future<List<ProListing>> fetchAll() async {
    final snap = await _col
        .orderBy('rankScore', descending: true)
        .limit(fetchLimit)
        .get();
    final list = snap.docs.map(ProListing.fromDoc).toList();
    list.sort(compareRank);
    return list;
  }

  static int compareRank(ProListing a, ProListing b) {
    final byScore = b.rankScore.compareTo(a.rankScore);
    if (byScore != 0) return byScore;
    return b.ratingCount.compareTo(a.ratingCount);
  }

  Future<ProListing?> fetch(String proUid) async {
    final doc = await _col.doc(proUid).get();
    return doc.exists ? ProListing.fromDoc(doc) : null;
  }

  Future<ProContact> contact(String proUid) async {
    final doc = await _contactRef(proUid).get();
    return ProContact.fromMap(doc.data());
  }

  /// Crée ou met à jour la fiche du compte courant. La réputation n'est
  /// posée qu'à la création : une mise à jour ne touche jamais aux notes.
  Future<void> save(ProListing listing, ProContact contact) async {
    final ref = _col.doc(listing.id);
    final exists = (await ref.get()).exists;
    final batch = _db.batch();
    if (exists) {
      batch.update(ref, listing.toEditableMap());
    } else {
      batch.set(ref, listing.toCreateMap());
    }
    batch.set(_contactRef(listing.id), contact.toMap());
    await batch.commit();
  }

  /// Retire la fiche de l'annuaire. Les avis restent en base (ils
  /// reviendraient avec une nouvelle fiche) mais ne sont plus visibles.
  Future<void> delete(String proUid) async {
    final batch = _db.batch()
      ..delete(_contactRef(proUid))
      ..delete(_col.doc(proUid));
    await batch.commit();
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

  Future<bool> canReview({required String proUid, required String myUid}) async {
    if (myUid.isEmpty || myUid == proUid) return false;
    try {
      final doc = await _col
          .doc(proUid)
          .collection('contactedBy')
          .doc(myUid)
          .get();
      return doc.exists;
    } on FirebaseException catch (_) {
      return false;
    }
  }

  Future<List<ProReview>> reviews(String proUid, {int limit = 30}) async {
    final snap = await _reviews(
      proUid,
    ).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(ProReview.fromDoc).toList();
  }

  Future<ProReview?> myReview({
    required String proUid,
    required String myUid,
  }) async {
    if (myUid.isEmpty) return null;
    final doc = await _reviews(proUid).doc(myUid).get();
    return doc.exists ? ProReview.fromDoc(doc) : null;
  }

  Future<void> submitReview({
    required String proUid,
    required ProReview review,
  }) => _reviews(proUid).doc(review.reviewerUid).set(review.toMap());

  Future<void> deleteReview({required String proUid, required String myUid}) =>
      _reviews(proUid).doc(myUid).delete();
}
