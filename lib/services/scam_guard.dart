/// Détection des schémas d'arnaque les plus courants sur un marché local.
///
/// Le principe de l'app est la mise en relation : la transaction se fait
/// en main propre, hors application. Elle ne peut donc pas *empêcher* une
/// arnaque — mais elle peut prévenir au moment exact où le risque
/// apparaît, c'est-à-dire quand quelqu'un réclame de l'argent avant toute
/// rencontre.
///
/// Volontairement simple et local (aucun appel réseau) : une liste de
/// formulations, testée sur le texte normalisé. Mieux vaut un rappel de
/// bon sens affiché au bon moment qu'un modèle sophistiqué qu'on ne
/// pourrait ni expliquer ni corriger depuis Foumbot.
library;

import '../models/market_text.dart';

/// Nature du signal détecté — sert à formuler l'avertissement.
enum ScamSignal {
  avance,
  transfert,
  livraisonDistante,
  donneesPersonnelles,
  urgence;

  String get warning => switch (this) {
    ScamSignal.avance =>
      'On vous demande de payer avant d’avoir vu l’article. '
          'Ne versez jamais d’acompte : voyez l’article d’abord.',
    ScamSignal.transfert =>
      'On vous demande un transfert d’argent. Un paiement se fait en '
          'main propre, au moment de la remise.',
    ScamSignal.livraisonDistante =>
      'On propose un envoi à distance. Foumbot Link ne gère aucune '
          'livraison : préférez une remise en main propre.',
    ScamSignal.donneesPersonnelles =>
      'On vous demande un code ou vos identifiants. Ne les '
          'communiquez à personne, jamais.',
    ScamSignal.urgence =>
      'On vous met la pression pour décider vite. Prenez le temps de '
          'vérifier — l’urgence est un outil d’arnaque.',
  };
}

/// Formulations déclenchant chaque signal, en texte normalisé (minuscules
/// sans accents — voir [normalizeSearch]).
const _patterns = <ScamSignal, List<String>>{
  ScamSignal.avance: [
    'acompte',
    'avance',
    'payer avant',
    'paye avant',
    'payez avant',
    'verser avant',
    'versez',
    'caution',
    'reservation',
    'frais de dossier',
    'frais de reservation',
  ],
  ScamSignal.transfert: [
    'mobile money',
    'momo',
    'orange money',
    'om',
    'western union',
    'moneygram',
    'transfert',
    'envoie l argent',
    'envoyer l argent',
    'code de retrait',
    'numero mtn',
    'numero orange',
  ],
  ScamSignal.livraisonDistante: [
    'je suis en voyage',
    'je suis a l etranger',
    'expedier',
    'expedition',
    'agence de voyage',
    'transporteur',
    'livraison a distance',
    'envoyer par bus',
  ],
  ScamSignal.donneesPersonnelles: [
    'code otp',
    'code de verification',
    'mot de passe',
    'ton code',
    'votre code',
    'code secret',
    'pin',
  ],
  ScamSignal.urgence: [
    'urgent urgent',
    'dernier delai',
    'tout de suite sinon',
    'depeche toi',
    'avant ce soir sinon',
  ],
};

/// Certains mots ne sont pertinents qu'isolés : « om » ou « pin » se
/// retrouvent dans des mots courants. Ceux-là sont cherchés comme mots
/// entiers, pas en sous-chaîne, sans quoi l'avertissement se
/// déclencherait sur « pinceau » ou « ombre » et perdrait tout crédit.
const _wholeWordOnly = {'om', 'momo', 'pin', 'avance', 'versez'};

abstract final class ScamGuard {
  /// Signaux repérés dans [text], sans doublon. Vide = rien à signaler.
  static List<ScamSignal> analyze(String text) {
    if (text.trim().isEmpty) return const [];
    final normalized = normalizeSearch(text);
    final words = normalized.split(RegExp(r'[^a-z0-9]+')).toSet();

    final found = <ScamSignal>[];
    for (final entry in _patterns.entries) {
      final hit = entry.value.any((pattern) {
        if (_wholeWordOnly.contains(pattern)) return words.contains(pattern);
        return normalized.contains(pattern);
      });
      if (hit) found.add(entry.key);
    }
    return found;
  }

  static bool isSuspicious(String text) => analyze(text).isNotEmpty;

  /// Message d'avertissement complet pour [text], ou `null` si rien n'a
  /// été repéré. On n'affiche que les deux premiers signaux : au-delà,
  /// l'alerte devient un pavé que plus personne ne lit.
  static String? warningFor(String text) {
    final signals = analyze(text);
    if (signals.isEmpty) return null;
    return signals.take(2).map((s) => s.warning).join('\n\n');
  }
}

/// Les conseils permanents affichés sur une annonce et en tête de
/// discussion. Courts et concrets : trois phrases qu'on lit, plutôt
/// qu'une page de conditions que personne n'ouvre.
const kSafetyTips = <String>[
  'Voyez l’article avant de payer, jamais l’inverse.',
  'Retrouvez-vous dans un lieu public et fréquenté.',
  'Ne versez ni acompte ni « frais » par Mobile Money.',
];
