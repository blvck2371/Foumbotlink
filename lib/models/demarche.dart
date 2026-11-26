import 'package:cloud_firestore/cloud_firestore.dart';

enum DemarcheCategory {
  etatCivil,
  identite,
  justice,
  urbanisme,
  education,
  sante,
  services,
  emploi,
  autre;

  String get label => switch (this) {
    DemarcheCategory.etatCivil => 'État civil',
    DemarcheCategory.identite => 'Identité & voyages',
    DemarcheCategory.justice => 'Justice & légalisation',
    DemarcheCategory.urbanisme => 'Urbanisme & foncier',
    DemarcheCategory.education => 'Éducation & social',
    DemarcheCategory.sante => 'Santé',
    DemarcheCategory.services => 'Services & abonnements',
    DemarcheCategory.emploi => 'Emploi & formation',
    DemarcheCategory.autre => 'Autres démarches',
  };

  String get icon => switch (this) {
    DemarcheCategory.etatCivil => '\u{1F4DC}',
    DemarcheCategory.identite => '\u{1FAAA}',
    DemarcheCategory.justice => '\u{2696}',
    DemarcheCategory.urbanisme => '\u{1F3D7}',
    DemarcheCategory.education => '\u{1F393}',
    DemarcheCategory.sante => '\u{1F3E5}',
    DemarcheCategory.services => '\u{1F50C}',
    DemarcheCategory.emploi => '\u{1F4BC}',
    DemarcheCategory.autre => '\u{1F4C1}',
  };
}

/// Une démarche telle qu'une structure la publie.
///
/// Le contenu n'est plus figé dans l'application : chaque structure
/// validée décrit **ses** démarches, avec ses pièces, ses tarifs et ses
/// délais. Une mairie, une préfecture et une sous-préfecture n'ont ni les
/// mêmes guichets ni les mêmes prix, et une liste unique codée en dur
/// donnait forcément tort à quelqu'un.
///
/// Stocké dans `demarches/{id}` — lecture publique (c'est un service au
/// public), écriture réservée à la structure propriétaire.
class Demarche {
  const Demarche({
    required this.id,
    required this.structureUid,
    required this.structureName,
    required this.category,
    required this.title,
    required this.description,
    required this.documents,
    required this.lieu,
    required this.cout,
    required this.delai,
    required this.etapes,
    this.echeanceJours,
    this.echeanceDepuis,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Compte structure qui publie la démarche — seul habilité à la
  /// modifier, et affiché à l'habitant pour qu'il sache à quel guichet
  /// il s'adresse.
  final String structureUid;
  final String structureName;

  final DemarcheCategory category;
  final String title;
  final String description;
  final List<String> documents;
  final String lieu;
  final String cout;
  final String delai;
  final List<String> etapes;

  /// Délai à respecter, fixé **par la structure** : la démarche doit être
  /// faite dans les [echeanceJours] jours suivant [echeanceDepuis] (« la
  /// naissance de l'enfant »). `null` = pas de délai. L'habitant peut alors
  /// saisir sa date et recevoir des rappels ; si la structure modifie le
  /// délai, les rappels suivent.
  final int? echeanceJours;
  final String? echeanceDepuis;

  bool get hasEcheance =>
      (echeanceJours ?? 0) > 0 && (echeanceDepuis ?? '').trim().isNotEmpty;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Demarche.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Demarche(
      id: doc.id,
      structureUid: d['structureUid'] as String? ?? '',
      structureName: d['structureName'] as String? ?? 'Structure',
      category: _categoryFrom(d['category'] as String?),
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      documents: _stringList(d['documents']),
      lieu: d['lieu'] as String? ?? '',
      cout: d['cout'] as String? ?? '',
      delai: d['delai'] as String? ?? '',
      etapes: _stringList(d['etapes']),
      echeanceJours: (d['echeanceJours'] as num?)?.toInt(),
      echeanceDepuis: d['echeanceDepuis'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'structureUid': structureUid,
    'structureName': structureName,
    'category': category.name,
    'title': title,
    'description': description,
    'documents': documents,
    'lieu': lieu,
    'cout': cout,
    'delai': delai,
    'etapes': etapes,
    if (hasEcheance) 'echeanceJours': echeanceJours,
    if (hasEcheance) 'echeanceDepuis': echeanceDepuis,
  };

  Demarche copyWith({
    String? structureName,
    DemarcheCategory? category,
    String? title,
    String? description,
    List<String>? documents,
    String? lieu,
    String? cout,
    String? delai,
    List<String>? etapes,
    int? echeanceJours,
    String? echeanceDepuis,
    bool clearEcheance = false,
  }) {
    return Demarche(
      id: id,
      structureUid: structureUid,
      structureName: structureName ?? this.structureName,
      category: category ?? this.category,
      title: title ?? this.title,
      description: description ?? this.description,
      documents: documents ?? this.documents,
      lieu: lieu ?? this.lieu,
      cout: cout ?? this.cout,
      delai: delai ?? this.delai,
      etapes: etapes ?? this.etapes,
      echeanceJours: clearEcheance ? null : echeanceJours ?? this.echeanceJours,
      echeanceDepuis: clearEcheance
          ? null
          : echeanceDepuis ?? this.echeanceDepuis,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Une catégorie inconnue (ajoutée par une version plus récente de
  /// l'app) ne doit pas faire disparaître la démarche : elle retombe sur
  /// « État civil » plutôt que de lever.
  static DemarcheCategory _categoryFrom(String? name) =>
      DemarcheCategory.values.firstWhere(
        (c) => c.name == name,
        // Catégorie inconnue (ajoutée par une version plus récente) :
        // « Autres » plutôt que de la ranger à tort dans l'état civil.
        orElse: () => DemarcheCategory.autre,
      );

  static List<String> _stringList(Object? raw) => switch (raw) {
    final List<dynamic> list =>
      list.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
    _ => const <String>[],
  };
}
