import 'package:cloud_firestore/cloud_firestore.dart';

/// Avis laissé sur un vendeur — `users/{sellerUid}/reviews/{reviewerUid}`.
///
/// Un document par personne : l'id est l'uid de l'auteur de l'avis, donc
/// on ne peut pas noter deux fois le même vendeur, et modifier son avis
/// écrase le précédent au lieu d'en ajouter un.
///
/// Écrire un avis suppose d'avoir réellement contacté le vendeur : les
/// règles exigent l'existence de `users/{sellerUid}/contactedBy/{moi}`,
/// posé au moment où le numéro est révélé ou la discussion ouverte. Sans
/// cette condition, la note d'un vendeur serait à la portée de n'importe
/// quel compte, ce qui la viderait de son sens — dans un marché où tout
/// se règle en face à face, la réputation est la seule sécurité.
class SellerReview {
  const SellerReview({
    required this.reviewerUid,
    required this.reviewerName,
    required this.rating,
    required this.createdAt,
    this.comment = '',
    this.itemId,
    this.itemTitle = '',
  });

  final String reviewerUid;
  final String reviewerName;

  /// Note de 1 à 5.
  final int rating;

  final String comment;
  final DateTime createdAt;

  /// Annonce à l'origine du contact, si connue.
  final String? itemId;
  final String itemTitle;

  factory SellerReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SellerReview(
      reviewerUid: doc.id,
      reviewerName: d['reviewerName'] as String? ?? 'Habitant·e',
      rating: (d['rating'] as num?)?.toInt().clamp(1, 5) ?? 5,
      comment: d['comment'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      itemId: d['itemId'] as String?,
      itemTitle: d['itemTitle'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'reviewerName': reviewerName,
    'rating': rating,
    'comment': comment.trim(),
    'itemId': itemId,
    'itemTitle': itemTitle,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// Résumé de réputation affiché sur une fiche vendeur. Les compteurs sont
/// tenus à jour par `onSellerReviewWritten` (Cloud Function) : les
/// recalculer côté client demanderait de lire tous les avis à chaque
/// affichage d'annonce.
class SellerReputation {
  const SellerReputation({
    this.ratingCount = 0,
    this.ratingAvg = 0,
    this.listingsCount = 0,
    this.memberSince,
  });

  final int ratingCount;
  final double ratingAvg;
  final int listingsCount;
  final DateTime? memberSince;

  bool get hasRating => ratingCount > 0;

  /// « 4,3 » — virgule décimale, une décimale.
  String get ratingLabel => ratingAvg.toStringAsFixed(1).replaceAll('.', ',');
}
