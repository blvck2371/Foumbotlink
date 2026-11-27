import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Métiers proposés dans l'annuaire. La clé est stockée dans Firestore
/// (`directory/{uid}.category`) : ne jamais renommer une clé existante,
/// seulement le libellé. `autre` reste en dernier ; la spécialité saisie
/// librement (`trade`) précise alors le métier.
enum ProCategory {
  frigoriste('Frigoriste', Icons.ac_unit),
  electricien('Électricien', Icons.electrical_services),
  plombier('Plombier', Icons.plumbing),
  macon('Maçon', Icons.foundation),
  menuisier('Menuisier', Icons.carpenter),
  soudeur('Soudeur', Icons.hardware),
  peintre('Peintre', Icons.format_paint),
  carreleur('Carreleur', Icons.grid_on),
  mecanicien('Mécanicien', Icons.car_repair),
  reparateur('Réparation téléphone & électronique', Icons.phone_android),
  informaticien('Informatique', Icons.computer),
  couturier('Couture', Icons.content_cut),
  coiffure('Coiffure & beauté', Icons.face_retouching_natural),
  transport('Transport & déménagement', Icons.local_shipping),
  traiteur('Traiteur & cuisine', Icons.restaurant),
  photographe('Photo & vidéo', Icons.photo_camera),
  enseignant('Cours & répétitions', Icons.school),
  sante('Santé', Icons.medical_services),
  agriculture('Agriculture & élevage', Icons.agriculture),
  autre('Autre métier', Icons.handyman);

  const ProCategory(this.label, this.icon);

  final String label;
  final IconData icon;

  static ProCategory fromKey(String? key) => ProCategory.values.firstWhere(
    (c) => c.name == key,
    orElse: () => ProCategory.autre,
  );
}

/// Fiche d'un professionnel dans l'annuaire — `directory/{ownerUid}`.
///
/// Une fiche par compte : l'id du document *est* l'uid du propriétaire.
/// Le numéro n'est pas ici (document lisible par tous, y compris sans
/// compte) mais dans `directory/{uid}/contact/main`, réservé aux comptes
/// connectés — même raisonnement que pour le marché : un document public
/// suffirait à aspirer les numéros de toute la commune.
///
/// Les champs de réputation (`ratingCount`, `ratingSum`, `ratingAvg`,
/// `rankScore`) sont écrits par `onProReviewWritten`, jamais par le
/// client (voir firestore.rules).
class ProListing {
  const ProListing({
    required this.id,
    required this.name,
    required this.category,
    this.trade = '',
    this.description = '',
    this.quartier = '',
    this.hours = '',
    this.photoUrl,
    this.ratingCount = 0,
    this.ratingAvg = 0,
    this.rankScore = rankPrior,
    this.createdAt,
  });

  /// Uid du propriétaire de la fiche.
  final String id;
  final String name;
  final ProCategory category;

  /// Spécialité en clair : « Climatisation, chambres froides ».
  final String trade;
  final String description;
  final String quartier;

  /// Horaires en texte libre : « Lun–Sam, 8 h–18 h ».
  final String hours;
  final String? photoUrl;
  final int ratingCount;
  final double ratingAvg;

  /// Score de classement — moyenne bayésienne, voir [rankPrior].
  final double rankScore;
  final DateTime? createdAt;

  /// Moyenne « neutre » d'un professionnel sans avis, et poids qu'on lui
  /// donne. Le classement utilise
  /// `(rankWeight × rankPrior + somme des notes) / (rankWeight + nombre d'avis)`
  /// : une seule note de 5 ne passe pas devant trente avis à 4,8, et un
  /// professionnel bien noté monte à mesure que ses avis s'accumulent.
  /// Doit rester aligné sur `functions/index.js` et sur firestore.rules
  /// (valeur imposée à la création).
  static const rankPrior = 3.5;
  static const rankWeight = 5;

  String get categoryLabel =>
      category == ProCategory.autre && trade.isNotEmpty
          ? trade
          : category.label;

  bool get hasRating => ratingCount > 0;

  /// « 4,3 » — virgule décimale, une décimale.
  String get ratingLabel => ratingAvg.toStringAsFixed(1).replaceAll('.', ',');

  /// Texte sur lequel porte la recherche, sans accents ni majuscules.
  String get searchText => normalize(
    '$name ${category.label} $trade $description $quartier',
  );

  /// Minuscules, sans accents : « Électricien » et « electricien » doivent
  /// se trouver l'un l'autre.
  static String normalize(String s) {
    const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      out.write(i >= 0 ? to[i] : ch);
    }
    return out.toString();
  }

  factory ProListing.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ProListing(
      id: doc.id,
      name: d['name'] as String? ?? '',
      category: ProCategory.fromKey(d['category'] as String?),
      trade: d['trade'] as String? ?? '',
      description: d['description'] as String? ?? '',
      quartier: d['quartier'] as String? ?? '',
      hours: d['hours'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
      ratingAvg: (d['ratingAvg'] as num?)?.toDouble() ?? 0,
      rankScore: (d['rankScore'] as num?)?.toDouble() ?? rankPrior,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Champs modifiables par le propriétaire — sans la réputation.
  Map<String, dynamic> toEditableMap() => {
    'ownerUid': id,
    'name': name.trim(),
    'category': category.name,
    'trade': trade.trim(),
    'description': description.trim(),
    'quartier': quartier.trim(),
    'hours': hours.trim(),
    'photoUrl': photoUrl,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Document complet d'une nouvelle fiche : réputation à zéro, score au
  /// niveau neutre (sinon `orderBy('rankScore')` l'exclurait).
  Map<String, dynamic> toCreateMap() => {
    ...toEditableMap(),
    'ratingCount': 0,
    'ratingSum': 0,
    'ratingAvg': 0,
    'rankScore': rankPrior,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// Coordonnées d'un professionnel — `directory/{uid}/contact/main`.
class ProContact {
  const ProContact({this.phone = '', this.whatsapp = ''});

  final String phone;

  /// Numéro WhatsApp s'il diffère du téléphone ; vide = même numéro.
  final String whatsapp;

  String get whatsappOrPhone => whatsapp.isNotEmpty ? whatsapp : phone;

  factory ProContact.fromMap(Map<String, dynamic>? d) => ProContact(
    phone: d?['phone'] as String? ?? '',
    whatsapp: d?['whatsapp'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'phone': phone.trim(),
    'whatsapp': whatsapp.trim(),
  };
}

/// Avis sur un professionnel — `directory/{proUid}/reviews/{reviewerUid}`.
/// Un avis par personne (l'id est l'uid de l'auteur) ; publier à nouveau
/// remplace le précédent.
class ProReview {
  const ProReview({
    required this.reviewerUid,
    required this.reviewerName,
    required this.rating,
    required this.createdAt,
    this.comment = '',
  });

  final String reviewerUid;
  final String reviewerName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  factory ProReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ProReview(
      reviewerUid: doc.id,
      reviewerName: d['reviewerName'] as String? ?? 'Habitant·e',
      rating: (d['rating'] as num?)?.toInt().clamp(1, 5) ?? 5,
      comment: d['comment'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'reviewerName': reviewerName,
    'rating': rating,
    'comment': comment.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  };
}
