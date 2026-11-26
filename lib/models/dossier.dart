import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Où en est un dossier déposé auprès d'une structure.
///
/// L'ordre de l'énumération est celui du parcours normal : il sert à
/// dessiner la frise d'avancement. [complementRequis] et [rejete] en
/// sortent — ce sont des embranchements, pas des étapes.
enum DossierStatus {
  receptionne,
  enCours,
  complementRequis,
  termine,
  retire,
  rejete;

  String get label => switch (this) {
    DossierStatus.receptionne => 'Dossier réceptionné',
    DossierStatus.enCours => 'En cours de traitement',
    DossierStatus.complementRequis => 'Pièce manquante',
    DossierStatus.termine => 'Traitement terminé',
    DossierStatus.retire => 'Dossier retiré',
    DossierStatus.rejete => 'Dossier rejeté',
  };

  /// Ce que la personne doit comprendre : non pas l'état administratif,
  /// mais ce qu'elle a à faire, ou à ne pas faire.
  String get citizenHint => switch (this) {
    DossierStatus.receptionne =>
      'Votre dossier est bien arrivé. Vous n’avez rien à faire pour '
          'l’instant.',
    DossierStatus.enCours =>
      'Le service travaille sur votre dossier. Vous serez prévenu dès '
          'qu’il change d’état.',
    DossierStatus.complementRequis =>
      'Il manque une pièce. Rendez-vous au guichet pour la déposer.',
    DossierStatus.termine =>
      'C’est prêt. Vous pouvez venir le retirer au guichet.',
    DossierStatus.retire => 'Vous avez retiré ce dossier. Démarche terminée.',
    DossierStatus.rejete =>
      'Le dossier n’a pas pu aboutir. Le motif est indiqué ci-dessous.',
  };

  /// Les étapes de la frise, dans l'ordre. Les embranchements en sont
  /// absents : ils s'affichent comme une interruption sur l'étape en
  /// cours, pas comme une case de plus.
  static const timeline = [
    DossierStatus.receptionne,
    DossierStatus.enCours,
    DossierStatus.termine,
    DossierStatus.retire,
  ];

  bool get isBranch =>
      this == DossierStatus.complementRequis || this == DossierStatus.rejete;

  /// Un dossier clos ne bouge plus : ni relance, ni notification.
  bool get isClosed =>
      this == DossierStatus.retire || this == DossierStatus.rejete;

  /// Les états vers lesquels une structure peut faire passer un dossier.
  ///
  /// On ne revient jamais en arrière : un dossier annoncé « terminé » puis
  /// remis « en cours » ferait se déplacer une personne pour rien. La
  /// correction d'une erreur passe par une note, pas par un retour.
  List<DossierStatus> get nextChoices => switch (this) {
    DossierStatus.receptionne => const [
      DossierStatus.enCours,
      DossierStatus.complementRequis,
      DossierStatus.termine,
      DossierStatus.rejete,
    ],
    DossierStatus.enCours => const [
      DossierStatus.complementRequis,
      DossierStatus.termine,
      DossierStatus.rejete,
    ],
    DossierStatus.complementRequis => const [
      DossierStatus.enCours,
      DossierStatus.termine,
      DossierStatus.rejete,
    ],
    DossierStatus.termine => const [DossierStatus.retire],
    DossierStatus.retire || DossierStatus.rejete => const [],
  };

  /// Un motif est exigé là où son absence laisserait quelqu'un sans
  /// réponse : « pièce manquante » laquelle, « rejeté » pourquoi.
  bool get requiresNote =>
      this == DossierStatus.complementRequis || this == DossierStatus.rejete;
}

/// Une étape franchie, telle qu'elle s'affiche dans l'historique.
class DossierEvent {
  const DossierEvent({
    required this.status,
    required this.at,
    this.note,
    this.byName,
    this.step,
  });

  final DossierStatus status;
  final DateTime at;

  /// Étape atteinte, telle que la structure l'a nommée (« Phase de
  /// signature »). `null` pour un embranchement ou un ancien dossier.
  final String? step;

  /// Ce qu'affiche l'historique.
  String get label => step ?? status.label;

  /// Précision saisie par l'agent — obligatoire sur les embranchements.
  final String? note;

  /// Nom de la structure qui a fait l'enregistrement. Pas le nom de
  /// l'agent : c'est le service qui répond, pas la personne au guichet.
  final String? byName;

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'at': Timestamp.fromDate(at),
    if (note != null && note!.isNotEmpty) 'note': note,
    if (byName != null) 'byName': byName,
    if (step != null) 'step': step,
  };

  factory DossierEvent.fromMap(Map<String, dynamic> d) => DossierEvent(
    status: DossierStatus.values.firstWhere(
      (s) => s.name == d['status'],
      orElse: () => DossierStatus.receptionne,
    ),
    at: (d['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    note: d['note'] as String?,
    byName: d['byName'] as String?,
    step: d['step'] as String?,
  );
}

/// Un dossier déposé au guichet d'une structure et suivi par son
/// propriétaire — le cœur de la fonctionnalité.
///
/// Document `dossiers/{id}`. L'historique vit **dans** le document, dans
/// un tableau : une démarche compte quelques étapes, jamais des
/// centaines, et les lire d'un bloc avec le dossier évite une requête par
/// dossier affiché.
class Dossier {
  const Dossier({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.trackingCode,
    required this.structureUid,
    required this.structureName,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.demarcheId,
    this.reference,
    this.events = const [],
    List<String> steps = const [],
    this.stepIndex = 0,
  }) : _steps = steps;

  final String id;
  final String ownerUid;
  final String ownerName;

  /// Le code que la personne a écrit sur sa chemise. Conservé sur le
  /// dossier pour que le guichet retrouve l'un par l'autre.
  final String trackingCode;

  final String structureUid;
  final String structureName;

  /// Intitulé de la démarche, tel qu'annoncé à la personne.
  final String title;

  /// Identifiant de la démarche (`demarches/{id}`) publiée par la
  /// structure, quand l'agent l'a choisie dans sa propre liste ; `null`
  /// pour un intitulé saisi librement.
  final String? demarcheId;

  /// Référence interne du service, s'il en attribue une. Affichée telle
  /// quelle, jamais interprétée.
  final String? reference;

  final DossierStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DossierEvent> events;

  /// Étapes de suivi définies par la structure sur sa démarche, copiées
  /// à la réception : si la structure modifie sa démarche ensuite, un
  /// dossier déjà en cours garde le parcours annoncé à la personne.
  final List<String> _steps;

  /// Étape atteinte dans [steps] (voir [currentStep]).
  final int stepIndex;

  /// Les étapes du dossier : celles de la structure, ou à défaut des
  /// étapes génériques (dossier sans démarche, ou ancien dossier).
  List<String> get steps => _steps.isNotEmpty ? _steps : defaultSteps;

  /// Les étapes de la structure telles qu'enregistrées (vide si aucune).
  List<String> get definedSteps => _steps;

  static const defaultSteps = [
    'Dossier réceptionné',
    'En cours de traitement',
    'Prêt — à retirer',
  ];

  /// Étape courante, bornée : un document mal formé ne doit pas planter.
  int get currentStep {
    if (_steps.isEmpty) {
      // Anciens dossiers, sans étapes : l'étape se déduit de l'état.
      return switch (status) {
        DossierStatus.receptionne => 0,
        DossierStatus.enCours ||
        DossierStatus.complementRequis ||
        DossierStatus.rejete => 1,
        DossierStatus.termine || DossierStatus.retire => 2,
      };
    }
    return stepIndex.clamp(0, _steps.length - 1);
  }

  bool get atLastStep => currentStep == steps.length - 1;

  /// Ce que la personne lit en premier : l'étape nommée par la structure,
  /// ou l'embranchement / la clôture.
  String get currentLabel => status.isBranch || status == DossierStatus.retire
      ? status.label
      : steps[currentStep];

  /// Ce que le guichet peut faire maintenant.
  List<DossierAction> get nextActions {
    if (status.isClosed) return const [];
    final i = currentStep;
    final missing = status == DossierStatus.complementRequis;
    return [
      if (missing)
        DossierAction(
          label: 'Pièce reçue : reprendre',
          status: statusForStep(i, steps.length),
          stepIndex: i,
          step: steps[i],
        ),
      if (!atLastStep)
        DossierAction(
          label: steps[i + 1],
          status: statusForStep(i + 1, steps.length),
          stepIndex: i + 1,
          step: steps[i + 1],
          isStep: true,
        ),
      if (atLastStep && !missing)
        DossierAction(
          label: DossierStatus.retire.label,
          status: DossierStatus.retire,
          stepIndex: i,
        ),
      if (!missing)
        DossierAction(
          label: DossierStatus.complementRequis.label,
          status: DossierStatus.complementRequis,
          stepIndex: i,
        ),
      DossierAction(
        label: 'Rejeter le dossier',
        status: DossierStatus.rejete,
        stepIndex: i,
      ),
    ];
  }

  /// L'état « technique » d'une étape, qui sert aux couleurs et aux
  /// règles : la première est la réception, la dernière l'aboutissement,
  /// les autres du traitement.
  static DossierStatus statusForStep(int index, int count) => index <= 0
      ? DossierStatus.receptionne
      : index >= count - 1
      ? DossierStatus.termine
      : DossierStatus.enCours;

  /// La dernière note saisie, si l'état courant en portait une.
  String? get currentNote {
    for (final event in events.reversed) {
      if (event.status == status) return event.note;
    }
    return null;
  }

  /// Position dans la frise, ou `null` pour un embranchement — qui
  /// s'affiche sur l'étape en cours plutôt que comme une case de plus.
  int? get timelineIndex {
    final index = DossierStatus.timeline.indexOf(status);
    return index < 0 ? null : index;
  }

  Dossier copyWith({DossierStatus? status, List<DossierEvent>? events}) =>
      Dossier(
        id: id,
        ownerUid: ownerUid,
        ownerName: ownerName,
        trackingCode: trackingCode,
        structureUid: structureUid,
        structureName: structureName,
        title: title,
        demarcheId: demarcheId,
        reference: reference,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        events: events ?? this.events,
        steps: _steps,
        stepIndex: stepIndex,
      );

  factory Dossier.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Dossier(
      id: doc.id,
      ownerUid: d['ownerUid'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? '',
      trackingCode: d['trackingCode'] as String? ?? '',
      structureUid: d['structureUid'] as String? ?? '',
      structureName: d['structureName'] as String? ?? '',
      title: d['title'] as String? ?? 'Démarche',
      demarcheId: d['demarcheId'] as String?,
      reference: d['reference'] as String?,
      status: DossierStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => DossierStatus.receptionne,
      ),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      events: [
        for (final e in (d['events'] as List<dynamic>? ?? const []))
          DossierEvent.fromMap(Map<String, dynamic>.from(e as Map)),
      ],
      steps: [
        for (final e in (d['steps'] as List<dynamic>? ?? const []))
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
      ],
      stepIndex: (d['stepIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Un geste possible au guichet sur un dossier.
class DossierAction {
  const DossierAction({
    required this.label,
    required this.status,
    required this.stepIndex,
    this.step,
    this.isStep = false,
  });

  final String label;
  final DossierStatus status;
  final int stepIndex;

  /// Nom de l'étape atteinte, inscrit dans l'historique.
  final String? step;

  /// Passage à l'étape suivante définie par la structure.
  final bool isStep;

  bool get requiresNote => status.requiresNote;
}

/// Fabrique et vérifie les codes de suivi.
///
/// Le code est **écrit à la main sur une chemise cartonnée**, puis relu
/// et retapé par quelqu'un d'autre au guichet. Tout le dessin de
/// l'alphabet vient de là.
abstract final class TrackingCode {
  /// Sept caractères : assez pour que deux habitants ne se télescopent
  /// pas (31⁷ ≈ 27 milliards de combinaisons), assez court pour être
  /// recopié sans faute.
  static const length = 7;

  /// Alphabet sans `I`, `L`, `O`, `0`, `1` : manuscrits, ces caractères
  /// se confondent deux à deux, et une seule confusion envoie le dossier
  /// sur le compte de quelqu'un d'autre — ou nulle part.
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static final _random = Random.secure();

  static String generate() => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
  ]);

  /// Remet un code saisi au guichet dans sa forme canonique : majuscules,
  /// sans les espaces, tirets et points qu'on ajoute spontanément en
  /// recopiant sept caractères.
  ///
  /// Les caractères ambigus sont **conservés**, pas corrigés : puisque
  /// l'alphabet exclut aussi bien `O` que `0`, un glyphe lu « O » ne
  /// correspond à rien de valide et deviner à sa place enverrait le
  /// dossier sur le compte de quelqu'un d'autre. [describeProblem] le
  /// signale à l'agent, qui a la chemise sous les yeux et peut relire.
  static String normalize(String input) {
    const separators = {' ', '-', '_', '.', '/'};
    return input
        .toUpperCase()
        .split('')
        .where((c) => !separators.contains(c))
        .join();
  }

  /// Préfixe du QR code affiché par l'habitant : le guichet le scanne au
  /// lieu de recopier le code.
  static const qrPrefix = 'FOUMBOT-SUIVI:';

  static String qrPayload(String code) => '$qrPrefix$code';

  /// Le code lu dans un QR code (le nôtre, ou un QR qui ne contient que
  /// le code). `null` si ce n'est pas un code de suivi.
  static String? fromScan(String raw) {
    var text = raw.trim();
    if (text.toUpperCase().startsWith(qrPrefix)) {
      text = text.substring(qrPrefix.length);
    }
    final code = normalize(text);
    return isValid(code) ? code : null;
  }

  /// Vrai si [code] normalisé peut être un code émis par l'app.
  static bool isValid(String code) {
    if (code.length != length) return false;
    return code.split('').every(alphabet.contains);
  }

  /// Le défaut à signaler à l'agent, ou `null` si le code est utilisable.
  static String? describeProblem(String raw) {
    final code = normalize(raw);
    if (code.isEmpty) return 'Saisissez le code inscrit sur la chemise.';
    // Ces cinq-là sont absents de l'alphabet précisément parce qu'ils se
    // confondent deux à deux une fois écrits à la main. En trouver un
    // signifie que la lecture est douteuse, pas que le code est faux.
    const ambiguous = {'O', '0', 'I', 'L', '1'};
    final found = code.split('').where(ambiguous.contains).toSet();
    if (found.isNotEmpty) {
      return 'Un code ne contient jamais ${found.join(', ')} — ces '
          'caractères sont exclus car ils se confondent à l’écriture. '
          'Relisez la chemise.';
    }
    if (code.length != length) {
      return 'Un code de suivi compte $length caractères, celui-ci en a '
          '${code.length}.';
    }
    if (!isValid(code)) return 'Ce code contient un caractère inattendu.';
    return null;
  }
}
