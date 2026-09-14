import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/seller_review.dart';

/// Avis sur les vendeurs — `users/{sellerUid}/reviews/{reviewerUid}`.
///
/// Rien ne sécurise une transaction ici : pas de paiement, pas de
/// séquestre, tout se règle en main propre. La réputation du vendeur est
/// donc la seule information sur laquelle un acheteur peut s'appuyer
/// avant de se déplacer — d'où le soin mis à ce qu'elle ne soit pas
/// falsifiable : un avis exige d'avoir réellement pris contact
/// (`users/{sellerUid}/contactedBy/{moi}`, vérifié par les règles).
class SellerReviewService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String sellerUid) =>
      _db.collection('users').doc(sellerUid).collection('reviews');

  Future<List<SellerReview>> fetch(String sellerUid, {int limit = 20}) async {
    final snap = await _ref(
      sellerUid,
    ).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(SellerReview.fromDoc).toList();
  }

  /// Résumé affiché sur la fiche vendeur. Les agrégats sont maintenus par
  /// `onSellerReviewWritten` ; les relire ici depuis `users/{uid}` évite
  /// de charger tous les avis à chaque ouverture d'annonce.
  Future<SellerReputation> reputation(String sellerUid) async {
    try {
      final doc = await _db.collection('users').doc(sellerUid).get();
      final d = doc.data() ?? const {};
      return SellerReputation(
        ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
        ratingAvg: (d['ratingAvg'] as num?)?.toDouble() ?? 0,
        listingsCount: (d['listingsCount'] as num?)?.toInt() ?? 0,
        memberSince: _parseDate(d['createdAt']),
      );
    } on FirebaseException catch (_) {
      return const SellerReputation();
    }
  }

  /// `createdAt` du profil est un ISO 8601 (voir UserProfile.toMap), mais
  /// d'autres écritures ont pu poser un Timestamp — on accepte les deux
  /// plutôt que de perdre l'ancienneté du compte, qui est justement un
  /// signal de confiance.
  static DateTime? _parseDate(Object? raw) => switch (raw) {
    Timestamp t => t.toDate(),
    String s => DateTime.tryParse(s),
    _ => null,
  };

  /// L'utilisateur a-t-il le droit de noter ce vendeur ? Mêmes conditions
  /// que les règles, vérifiées d'avance pour ne pas proposer un bouton
  /// qui échouera.
  Future<bool> canReview({
    required String sellerUid,
    required String myUid,
  }) async {
    if (myUid.isEmpty || myUid == sellerUid) return false;
    try {
      final doc = await _db
          .collection('users')
          .doc(sellerUid)
          .collection('contactedBy')
          .doc(myUid)
          .get();
      return doc.exists;
    } on FirebaseException catch (_) {
      return false;
    }
  }

  /// Avis déjà laissé par l'utilisateur courant, s'il existe — l'écran
  /// s'ouvre alors pré-rempli, et publier écrase l'ancien.
  Future<SellerReview?> myReview({
    required String sellerUid,
    required String myUid,
  }) async {
    if (myUid.isEmpty) return null;
    final doc = await _ref(sellerUid).doc(myUid).get();
    return doc.exists ? SellerReview.fromDoc(doc) : null;
  }

  Future<void> submit({
    required String sellerUid,
    required SellerReview review,
  }) => _ref(sellerUid).doc(review.reviewerUid).set(review.toMap());

  Future<void> delete({required String sellerUid, required String myUid}) =>
      _ref(sellerUid).doc(myUid).delete();
}
