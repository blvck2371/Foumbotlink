enum DemarcheCategory {
  etatCivil,
  identite,
  justice,
  urbanisme,
  education;

  String get label => switch (this) {
        DemarcheCategory.etatCivil => 'État civil',
        DemarcheCategory.identite => 'Identité & voyages',
        DemarcheCategory.justice => 'Justice & légalisation',
        DemarcheCategory.urbanisme => 'Urbanisme & foncier',
        DemarcheCategory.education => 'Éducation & social',
      };

  String get icon => switch (this) {
        DemarcheCategory.etatCivil => '\u{1F4DC}',
        DemarcheCategory.identite => '\u{1FAAA}',
        DemarcheCategory.justice => '\u{2696}',
        DemarcheCategory.urbanisme => '\u{1F3D7}',
        DemarcheCategory.education => '\u{1F393}',
      };
}

class Demarche {
  const Demarche({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.documents,
    required this.lieu,
    required this.cout,
    required this.delai,
    required this.etapes,
  });

  final String id;
  final DemarcheCategory category;
  final String title;
  final String description;
  final List<String> documents;
  final String lieu;
  final String cout;
  final String delai;
  final List<String> etapes;

  static final all = <Demarche>[
    const Demarche(
      id: 'acte-naissance',
      category: DemarcheCategory.etatCivil,
      title: 'Acte de naissance',
      description:
          'Document officiel attestant la naissance d’une personne, '
          'indispensable pour toute procédure administrative.',
      documents: [
        'Certificat de naissance délivré par la maternité',
        'Carte nationale d’identité du père',
        'Carte nationale d’identité de la mère',
        'Certificat de mariage des parents (si applicable)',
      ],
      lieu: 'Mairie de Foumbot — Service de l’état civil',
      cout: 'Gratuit (dans les 90 jours) / 1 000–2 000 FCFA après',
      delai: '24 à 72 heures',
      etapes: [
        'Se rendre à la mairie avec les documents requis',
        'Remplir le formulaire de déclaration de naissance',
        'Le service enregistre la déclaration',
        'Retirer l’acte de naissance au guichet',
      ],
    ),
    const Demarche(
      id: 'acte-mariage',
      category: DemarcheCategory.etatCivil,
      title: 'Acte de mariage',
      description:
          'Document officiel certifiant l’union civile entre deux personnes.',
      documents: [
        'Acte de naissance des deux époux (moins de 3 mois)',
        'Cartes nationales d’identité des deux époux',
        'Certificat de célibat ou de non-remariage',
        'Certificat médical prénuptial',
        'Publication des bans (affichage 30 jours)',
        '4 témoins majeurs avec leurs CNI',
      ],
      lieu: 'Mairie de Foumbot — Service de l’état civil',
      cout: '10 000 à 25 000 FCFA selon les frais de cérémonie',
      delai: '30 jours après publication des bans',
      etapes: [
        'Constituer le dossier complet',
        'Déposer le dossier à la mairie',
        'Publication des bans pendant 30 jours',
        'Célébration du mariage à la mairie',
        'Délivrance de l’acte de mariage',
      ],
    ),
    const Demarche(
      id: 'acte-deces',
      category: DemarcheCategory.etatCivil,
      title: 'Acte de décès',
      description:
          'Document officiel attestant le décès d’une personne.',
      documents: [
        'Certificat médical de décès',
        'Acte de naissance du défunt',
        'CNI du défunt ou d’un membre de la famille',
        'CNI du déclarant',
      ],
      lieu: 'Mairie de Foumbot — Service de l’état civil',
      cout: 'Gratuit (dans les 30 jours)',
      delai: '24 heures',
      etapes: [
        'Obtenir le certificat médical de décès',
        'Se présenter à la mairie avec les documents',
        'Remplir le formulaire de déclaration',
        'Retirer l’acte de décès',
      ],
    ),
    const Demarche(
      id: 'certificat-residence',
      category: DemarcheCategory.etatCivil,
      title: 'Certificat de résidence',
      description:
          'Attestation prouvant que vous résidez dans la commune de Foumbot.',
      documents: [
        'Carte nationale d’identité',
        'Justificatif de domicile (facture, bail)',
        'Témoignage du chef de quartier',
      ],
      lieu: 'Mairie de Foumbot — Secrétariat général',
      cout: '500 à 1 000 FCFA',
      delai: 'Immédiat à 24 heures',
      etapes: [
        'Obtenir l’attestation du chef de quartier',
        'Se rendre à la mairie avec la CNI et le justificatif',
        'Payer les frais de timbre',
        'Retirer le certificat',
      ],
    ),
    const Demarche(
      id: 'cni',
      category: DemarcheCategory.identite,
      title: 'Carte nationale d’identité',
      description:
          'Pièce d’identité officielle obligatoire pour tout citoyen camerounais '
          'de plus de 17 ans.',
      documents: [
        'Acte de naissance (original ou copie certifiée)',
        'Certificat de nationalité camerounaise',
        '4 photos d’identité 4x4 (fond blanc)',
        'Reçu de paiement des droits de timbre',
        'Formulaire de demande rempli',
      ],
      lieu: 'Commissariat de police de Foumbot / Délégation DGSN',
      cout: '2 800 FCFA (timbre fiscal)',
      delai: '1 à 3 mois',
      etapes: [
        'Rassembler tous les documents requis',
        'Se rendre au commissariat pour la prise d’empreintes',
        'Déposer le dossier complet',
        'Patienter le délai de traitement',
        'Retirer la CNI au commissariat',
      ],
    ),
    const Demarche(
      id: 'passeport',
      category: DemarcheCategory.identite,
      title: 'Passeport',
      description:
          'Document de voyage international délivré par la Délégation Générale '
          'à la Sûreté Nationale.',
      documents: [
        'Carte nationale d’identité en cours de validité',
        'Acte de naissance (moins de 3 mois)',
        'Certificat de nationalité',
        '4 photos d’identité 4x4 (fond blanc)',
        'Reçu de paiement (timbre)',
        'Ancien passeport (si renouvellement)',
      ],
      lieu: 'Délégation DGSN de Foumbot ou Bafoussam',
      cout: '110 000 FCFA (passeport biométrique)',
      delai: '2 à 6 semaines',
      etapes: [
        'Constituer le dossier avec toutes les pièces',
        'Déposer le dossier à la délégation',
        'Prise des données biométriques',
        'Paiement des frais',
        'Retrait du passeport après notification',
      ],
    ),
    const Demarche(
      id: 'certificat-nationalite',
      category: DemarcheCategory.identite,
      title: 'Certificat de nationalité',
      description:
          'Attestation officielle de la nationalité camerounaise, '
          'nécessaire pour la CNI et le passeport.',
      documents: [
        'Acte de naissance',
        'Acte de naissance du père ou de la mère',
        'CNI d’un parent',
        '4 photos d’identité',
        'Timbre fiscal',
      ],
      lieu: 'Tribunal de première instance de Foumbot',
      cout: '1 500 FCFA',
      delai: '1 à 4 semaines',
      etapes: [
        'Se rendre au tribunal avec les documents',
        'Remplir le formulaire de demande',
        'Payer le timbre fiscal',
        'Le juge signe le certificat',
        'Retirer le certificat au greffe',
      ],
    ),
    const Demarche(
      id: 'legalisation',
      category: DemarcheCategory.justice,
      title: 'Légalisation de documents',
      description:
          'Certification officielle de la conformité d’un document ou d’une signature.',
      documents: [
        'Document original à légaliser',
        'Copie du document',
        'Carte nationale d’identité',
        'Timbre fiscal',
      ],
      lieu: 'Mairie de Foumbot — Secrétariat général',
      cout: '200 à 500 FCFA par document',
      delai: 'Immédiat',
      etapes: [
        'Se présenter avec l’original et la copie',
        'Le secrétaire vérifie la conformité',
        'Payer les frais de timbre',
        'Le document est légalisé et tamponné',
      ],
    ),
    const Demarche(
      id: 'casier-judiciaire',
      category: DemarcheCategory.justice,
      title: 'Casier judiciaire (bulletin n°3)',
      description:
          'Extrait du casier judiciaire demandé pour les concours, l’emploi '
          'ou les démarches administratives.',
      documents: [
        'Acte de naissance (moins de 3 mois)',
        'Carte nationale d’identité',
        'Timbre fiscal de 1 000 FCFA',
      ],
      lieu: 'Tribunal de première instance de Foumbot',
      cout: '1 000 FCFA',
      delai: '48 heures à 1 semaine',
      etapes: [
        'Se rendre au greffe du tribunal',
        'Remplir le formulaire de demande',
        'Présenter l’acte de naissance et la CNI',
        'Payer le timbre fiscal',
        'Retirer le bulletin au greffe',
      ],
    ),
    const Demarche(
      id: 'permis-batir',
      category: DemarcheCategory.urbanisme,
      title: 'Permis de bâtir',
      description:
          'Autorisation obligatoire avant toute construction dans la commune.',
      documents: [
        'Titre foncier ou attestation foncière',
        'Plan de construction visé par un architecte',
        'Plan de situation du terrain',
        'Carte nationale d’identité',
        'Reçu de paiement des taxes',
      ],
      lieu: 'Mairie de Foumbot — Service de l’urbanisme',
      cout: 'Variable selon la surface (50 000 FCFA et plus)',
      delai: '1 à 3 mois',
      etapes: [
        'Faire établir les plans par un architecte agréé',
        'Constituer le dossier complet',
        'Déposer à la mairie',
        'Visite du terrain par le service technique',
        'Délivrance du permis après approbation',
      ],
    ),
    const Demarche(
      id: 'titre-foncier',
      category: DemarcheCategory.urbanisme,
      title: 'Titre foncier',
      description:
          'Document officiel prouvant la propriété d’un terrain.',
      documents: [
        'Demande adressée au sous-préfet',
        'Carte nationale d’identité',
        'Plan du terrain levé par un géomètre assermenté',
        'Attestation de vente ou acte coutumier',
        'Certificat d’imposition foncière',
      ],
      lieu: 'Sous-préfecture de Foumbot / Délégation des Domaines',
      cout: 'Variable (200 000 FCFA et plus)',
      delai: '6 mois à 2 ans',
      etapes: [
        'Faire borner le terrain par un géomètre',
        'Déposer la demande à la sous-préfecture',
        'Commission consultative de bornage',
        'Publication au Journal Officiel',
        'Délivrance du titre foncier',
      ],
    ),
    const Demarche(
      id: 'bourse-scolaire',
      category: DemarcheCategory.education,
      title: 'Bourse scolaire',
      description:
          'Aide financière pour les élèves et étudiants de la commune.',
      documents: [
        'Certificat de scolarité',
        'Bulletin de notes du dernier trimestre',
        'Acte de naissance',
        'CNI du parent ou tuteur',
        'Attestation de revenus ou de non-emploi',
      ],
      lieu: 'Mairie de Foumbot — Service social',
      cout: 'Gratuit',
      delai: '2 à 4 semaines',
      etapes: [
        'Retirer le formulaire à la mairie',
        'Constituer le dossier complet',
        'Déposer le dossier au service social',
        'Commission d’attribution',
        'Notification et versement de la bourse',
      ],
    ),
  ];

  static List<Demarche> byCategory(DemarcheCategory cat) =>
      all.where((d) => d.category == cat).toList();
}
