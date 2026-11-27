import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/account_type.dart';
import '../models/post_text.dart';
import '../models/pro_listing.dart';
import '../models/search_text.dart';
import '../models/user_profile.dart';
import 'directory_service.dart';
import 'moderation_service.dart';

/// Proposition affichée sous le champ quand on tape « @… ».
class MentionSuggestion {
  const MentionSuggestion({
    required this.mention,
    required this.subtitle,
    this.photoUrl,
    this.verified = false,
  });

  final PostMention mention;
  final String subtitle;
  final String? photoUrl;
  final bool verified;
}

/// Qui peut-on mentionner : comptes (habitants et structures) et fiches
/// de l'annuaire des professionnels.
///
/// Les comptes passent par l'index de recherche (`search`, débuts de mots
/// normalisés) ; l'annuaire, petit à l'échelle d'une commune, est gardé
/// en mémoire quelques minutes et filtré sur place.
class MentionService {
  static const _limit = 8;
  static const _directoryTtl = Duration(minutes: 5);

  final _db = FirebaseFirestore.instance;

  List<ProListing> _directory = const [];
  DateTime? _directoryAt;

  Future<List<ProListing>> _pros() async {
    final at = _directoryAt;
    if (at != null && DateTime.now().difference(at) < _directoryTtl) {
      return _directory;
    }
    try {
      _directory = await Get.find<DirectoryService>().watchAll().first;
      _directoryAt = DateTime.now();
    } on Object catch (e) {
      developer.log('Annuaire pour mentions', name: 'Mention', error: e);
    }
    return _directory;
  }

  Future<List<MentionSuggestion>> suggest(String query, {String? myUid}) async {
    final tokens = searchQueryTokens(query);
    final moderation = Get.isRegistered<ModerationService>()
        ? Get.find<ModerationService>()
        : null;

    final users = <MentionSuggestion>[];
    if (tokens.isNotEmpty) {
      final primary = tokens.reduce((a, b) => b.length > a.length ? b : a);
      try {
        final snap = await _db
            .collection('users')
            .where('search', arrayContains: primary)
            .limit(20)
            .get();
        for (final doc in snap.docs) {
          final UserProfile u;
          try {
            u = UserProfile.fromMap(doc.id, doc.data());
          } on Object catch (_) {
            continue;
          }
          if (u.uid == myUid || u.displayName.trim().isEmpty) continue;
          if (moderation?.hides(u.uid) ?? false) continue;
          if (matchScore(tokens, u.displayName) == 0) continue;
          users.add(
            MentionSuggestion(
              mention: PostMention(
                kind: MentionKind.user,
                id: u.uid,
                name: u.displayName.trim(),
              ),
              subtitle: u.accountType == AccountType.structure
                  ? 'Structure'
                  : 'Habitant·e',
              photoUrl: u.photoUrl,
              verified: u.verified,
            ),
          );
        }
      } on FirebaseException catch (e) {
        developer.log('Comptes pour mentions', name: 'Mention', error: e);
      }
    }

    final normalized = ProListing.normalize(query.trim());
    final pros = <MentionSuggestion>[
      for (final p in await _pros())
        if (normalized.isEmpty || p.searchText.contains(normalized))
          MentionSuggestion(
            mention: PostMention(
              kind: MentionKind.pro,
              id: p.id,
              name: p.name.trim(),
            ),
            subtitle: 'Pro · ${p.categoryLabel}',
            photoUrl: p.thumbnail,
          ),
    ];

    // Structures et comptes certifiés d'abord, puis les pros (déjà
    // classés par note), puis les habitants.
    users.sort((a, b) {
      int rank(MentionSuggestion s) =>
          (s.subtitle == 'Structure' ? 0 : 2) - (s.verified ? 1 : 0);
      return rank(a).compareTo(rank(b));
    });
    final structures = users.where((s) => s.subtitle == 'Structure');
    final people = users.where((s) => s.subtitle != 'Structure');
    return [...structures, ...pros.take(4), ...people].take(_limit).toList();
  }
}
