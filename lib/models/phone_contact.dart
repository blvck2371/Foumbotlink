import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Mise en forme et empreinte des numéros de téléphone.
///
/// Un répertoire téléphonique contient le même numéro écrit de dix
/// façons : `690 00 00 00`, `+237 690-00-00-00`, `00237690000000`,
/// `237 690 000 000`. Sans forme canonique, deux personnes qui se
/// connaissent ne se retrouveraient pas.
///
/// Rien de tout cela ne quitte le téléphone en clair : c'est
/// [hashOf] qui part au serveur, jamais le numéro.
abstract final class PhoneContact {
  /// Indicatif retenu quand le numéro est écrit en national — le cas le
  /// plus courant dans un répertoire camerounais.
  static const defaultCountryCode = '237';

  /// Longueur d'un numéro national camerounais (mobile comme fixe).
  static const _nationalLength = 9;

  /// Met un numéro sous forme E.164 (`+237690000000`), ou renvoie `null`
  /// si ce n'en est manifestement pas un.
  ///
  /// On préfère renvoyer `null` que deviner : un numéro mal reconstitué
  /// rapprocherait deux personnes qui ne se connaissent pas.
  static String? normalize(
    String raw, {
    String countryCode = defaultCountryCode,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Un `+` n'est significatif qu'en tête : ailleurs, c'est du bruit de
    // saisie (`+237 (690) 00-00-00`).
    final hasPlus = trimmed.startsWith('+');
    var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    if (!hasPlus && digits.startsWith('00')) {
      // Préfixe international composé à l'ancienne.
      digits = digits.substring(2);
    } else if (!hasPlus && digits.length == _nationalLength) {
      // Numéro national : on lui rend son indicatif.
      digits = '$countryCode$digits';
    } else if (!hasPlus &&
        digits.length == _nationalLength + 1 &&
        digits.startsWith('0')) {
      // Certains répertoires gardent un zéro de tête inutile au Cameroun.
      digits = '$countryCode${digits.substring(1)}';
    }

    // Bornes de l'E.164 : un indicatif fait 1 à 3 chiffres, le tout ne
    // dépasse jamais 15.
    if (digits.length < 8 || digits.length > 15) return null;
    return '+$digits';
  }

  /// Empreinte SHA-256 du numéro normalisé, en hexadécimal.
  ///
  /// C'est elle, et elle seule, qui traverse le réseau : le serveur
  /// compare des empreintes, il n'a jamais le répertoire de personne.
  ///
  /// Un numéro reste devinable par force brute — il n'y a que quelques
  /// dizaines de millions de numéros camerounais possibles — c'est
  /// pourquoi l'annuaire d'empreintes n'est **lisible par aucun client**
  /// et que la comparaison se fait dans une Cloud Function, bornée en
  /// nombre d'empreintes par appel.
  static String hashOf(String e164) =>
      sha256.convert(utf8.encode(e164)).toString();

  /// Empreintes d'une liste de numéros bruts, dédoublonnées, les numéros
  /// inexploitables écartés.
  static List<String> hashAll(
    Iterable<String> rawNumbers, {
    String countryCode = defaultCountryCode,
  }) {
    final hashes = <String>{};
    for (final raw in rawNumbers) {
      final e164 = normalize(raw, countryCode: countryCode);
      if (e164 != null) hashes.add(hashOf(e164));
    }
    return hashes.toList();
  }
}
