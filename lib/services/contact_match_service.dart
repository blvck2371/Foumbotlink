import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_contacts/flutter_contacts.dart';

import '../models/phone_contact.dart';

/// Un habitant retrouvé dans le répertoire du téléphone.
class ContactMatch {
  const ContactMatch({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.verified = false,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final bool verified;

  factory ContactMatch.fromMap(Map<String, dynamic> d) => ContactMatch(
    uid: d['uid'] as String? ?? '',
    displayName: d['displayName'] as String? ?? 'Habitant',
    photoUrl: d['photoUrl'] as String?,
    verified: d['verified'] == true,
  );
}

/// Pourquoi un rapprochement n'a rien donné — de quoi afficher autre
/// chose qu'une liste vide sans explication.
enum ContactMatchFailure {
  permissionRefusee,
  repertoireVide,
  erreurReseau,

  /// Plafond journalier atteint — voir `MAX_CONTACT_HASHES_PER_DAY` côté
  /// fonction. Distingué d'une panne réseau : il n'y a rien à réessayer
  /// tout de suite, et le dire évite qu'on s'acharne.
  quotaAtteint,

  /// Navigateur : aucun accès au répertoire du téléphone.
  indisponibleSurLeWeb,
}

/// Résultat d'un rapprochement : les comptes trouvés, ou la raison de
/// l'échec.
class ContactMatchResult {
  const ContactMatchResult.success(this.matches, {required this.scanned})
    : failure = null;
  const ContactMatchResult.failed(this.failure)
    : matches = const [],
      scanned = 0;

  final List<ContactMatch> matches;

  /// Nombre de numéros exploitables lus dans le répertoire — permet de
  /// dire « 214 contacts parcourus, 3 sont sur Foumbot Link ».
  final int scanned;

  final ContactMatchFailure? failure;

  bool get ok => failure == null;
}

/// Retrouve, parmi les contacts du téléphone, ceux qui ont un compte.
///
/// **Aucun numéro ne quitte l'appareil.** Les numéros sont mis en forme
/// puis réduits à une empreinte SHA-256 localement (voir
/// [PhoneContact]) ; seules ces empreintes partent vers la Cloud
/// Function `matchContacts`, qui renvoie les comptes correspondants.
///
/// Le répertoire lui-même n'est ni stocké ni envoyé : il est lu, haché,
/// et oublié à la fin de l'appel.
class ContactMatchService {
  /// Plafond imposé par la fonction serveur. Un répertoire plus fourni
  /// est découpé en autant d'appels.
  static const _batchSize = 500;

  Future<ContactMatchResult> findFriends() async {
    if (kIsWeb) {
      return const ContactMatchResult.failed(
        ContactMatchFailure.indisponibleSurLeWeb,
      );
    }
    try {
      // Lecture seule : l'app n'a aucune raison d'écrire dans le
      // répertoire, et c'est ce que la demande de permission annonce.
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      final granted =
          status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
      if (!granted) {
        return const ContactMatchResult.failed(
          ContactMatchFailure.permissionRefusee,
        );
      }

      // Seuls les numéros sont demandés — ni noms, ni e-mails, ni
      // adresses, ni photos. On ne lit que ce qu'on a besoin de hacher.
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );

      final hashes = PhoneContact.hashAll(
        contacts.expand((c) => c.phones).map((p) => p.number),
      );
      if (hashes.isEmpty) {
        return const ContactMatchResult.failed(
          ContactMatchFailure.repertoireVide,
        );
      }

      final functions = FirebaseFunctions.instance;
      final matches = <String, ContactMatch>{};

      for (var i = 0; i < hashes.length; i += _batchSize) {
        final slice = hashes.sublist(
          i,
          (i + _batchSize).clamp(0, hashes.length),
        );
        final response = await functions
            .httpsCallable('matchContacts')
            .call<Map<String, dynamic>>({'hashes': slice});

        for (final raw in (response.data['matches'] as List<dynamic>? ?? [])) {
          final match = ContactMatch.fromMap(
            Map<String, dynamic>.from(raw as Map),
          );
          if (match.uid.isNotEmpty) matches[match.uid] = match;
        }
      }

      return ContactMatchResult.success(
        matches.values.toList(),
        scanned: hashes.length,
      );
    } on FirebaseFunctionsException catch (e) {
      developer.log(
        'findFriends (${e.code})',
        name: 'ContactMatchService',
        error: e,
      );
      return ContactMatchResult.failed(
        e.code == 'resource-exhausted'
            ? ContactMatchFailure.quotaAtteint
            : ContactMatchFailure.erreurReseau,
      );
    } catch (e) {
      developer.log('findFriends', name: 'ContactMatchService', error: e);
      return const ContactMatchResult.failed(ContactMatchFailure.erreurReseau);
    }
  }
}
