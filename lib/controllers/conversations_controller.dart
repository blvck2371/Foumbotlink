import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/conversation.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

/// Nombre maximum de conversations dont on surveille l'indicateur
/// « écrit / enregistre ». Chaque conversation surveillée coûte une écoute
/// Firestore ouverte ; au-delà des plus récentes, l'information n'est de
/// toute façon pas visible sans faire défiler longuement la liste.
const _maxActivityWatchers = 25;

/// Fréquence de revérification de la péremption des activités reçues —
/// l'émetteur qui disparaît (crash, réseau) n'écrit jamais « idle », il
/// faut donc réévaluer l'ancienneté sans attendre un nouveau snapshot.
const _activitySweepInterval = Duration(seconds: 3);

class ConversationsController extends GetxController {
  final conversations = <Conversation>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  /// Indicateur temps réel « en train d'écrire / d'enregistrer » de
  /// l'interlocuteur, par id de conversation — façon WhatsApp. Ne contient
  /// que les activités en cours et non périmées : une conversation absente
  /// de la map affiche son aperçu de dernier message normalement.
  ///
  /// Volontairement séparé de [conversations] : l'activité change beaucoup
  /// plus souvent que la liste elle-même, et la tuile ne réabonne qu'un
  /// petit `Obx` dessus au lieu de reconstruire toute la liste.
  final activities = <String, ChatActivity>{}.obs;

  AuthService get _auth => Get.find<AuthService>();
  ChatService get _chat => Get.find<ChatService>();

  StreamSubscription? _sub;

  /// Une écoute de `conversations/{id}/typing/{otherUid}` par conversation
  /// surveillée, plus le dernier état brut reçu et sa date de réception.
  /// On horodate à la **réception** plutôt qu'avec le `updatedAt` serveur :
  /// la péremption reste juste même si l'horloge du téléphone est décalée,
  /// et le heartbeat de l'émetteur garantit un snapshot toutes les 5 s.
  final _activitySubs = <String, StreamSubscription>{};
  final _rawActivity = <String, ChatActivity>{};
  final _activityAt = <String, DateTime>{};
  Timer? _activitySweep;

  /// Dernier snapshot Firestore reçu — `_enrich` tourne en arrière-plan et
  /// ne doit jamais réappliquer une liste périmée par-dessus des mises à
  /// jour temps réel plus récentes (ordre / dernier message).
  List<Conversation> _latestRaw = [];

  /// Noms/photos/badges des interlocuteurs, conservés d'une ouverture à
  /// l'autre : le contrôleur est recréé à chaque navigation vers Messages,
  /// et un cache d'instance obligeait donc à relire tous les profils sur le
  /// réseau avant de pouvoir afficher la moindre conversation.
  static final _profileCache = <String, _PeerProfile>{};

  List<Conversation> get filtered {
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isEmpty) return conversations;
    return conversations.where((c) {
      final name = c.otherUserName?.toLowerCase() ?? '';
      return name.contains(q);
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    if (_auth.isSignedIn) _watch();
  }

  @override
  void onClose() {
    _sub?.cancel();
    for (final sub in _activitySubs.values) {
      sub.cancel();
    }
    _activitySubs.clear();
    _activitySweep?.cancel();
    super.onClose();
  }

  void _watch() {
    _sub = _chat.watchConversations(
      myUid: _auth.uid,
      onData: (list) {
        // Affichage immédiat : le premier snapshot arrive du cache local
        // en quelques millisecondes. Compléter les noms manquants AVANT
        // de publier la liste (ce que faisait ce callback) laissait
        // l'écran sur son chargeur le temps d'un aller-retour réseau par
        // interlocuteur — plusieurs secondes sur une connexion faible.
        _latestRaw = list;
        _apply(list);
        _syncActivityWatchers(list);
        isLoading.value = false;
        _enrich(list);
      },
      onError: (_) {
        isLoading.value = false;
      },
    );
  }

  // ---------------------------------------------------------------------
  // Indicateur « en train d'écrire / d'enregistrer »
  // ---------------------------------------------------------------------

  /// Aligne les écoutes d'activité sur la liste courante : ouvre celles des
  /// conversations nouvellement visibles, ferme celles qui ont disparu (ou
  /// sont sorties des [_maxActivityWatchers] plus récentes).
  void _syncActivityWatchers(List<Conversation> raw) {
    final myUid = _auth.uid;
    final wanted = <String, String>{};
    for (final conv in raw.take(_maxActivityWatchers)) {
      final other = conv.otherUid(myUid);
      if (other.isNotEmpty) wanted[conv.id] = other;
    }

    for (final id in _activitySubs.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      _activitySubs.remove(id)?.cancel();
      _rawActivity.remove(id);
      _activityAt.remove(id);
    }

    for (final entry in wanted.entries) {
      final convId = entry.key;
      if (_activitySubs.containsKey(convId)) continue;
      _activitySubs[convId] = _chat.watchActivity(
        conversationId: convId,
        uid: entry.value,
        onData: (activity) {
          _rawActivity[convId] = activity;
          _activityAt[convId] = DateTime.now();
          _refreshActivities();
        },
      );
    }

    _refreshActivities();
  }

  /// Recalcule [activities] à partir des états bruts reçus, en écartant les
  /// signaux périmés. Ne republie la map que si elle a réellement changé :
  /// le heartbeat de l'émetteur renvoie le même état toutes les 5 s, et
  /// réassigner à l'identique reconstruirait les tuiles pour rien.
  void _refreshActivities() {
    final now = DateTime.now();
    final next = <String, ChatActivity>{};
    for (final entry in _rawActivity.entries) {
      if (entry.value == ChatActivity.idle) continue;
      final at = _activityAt[entry.key];
      if (at == null || now.difference(at) > chatActivityStaleAfter) continue;
      next[entry.key] = entry.value;
    }

    if (!mapEquals(next, activities)) activities.assignAll(next);
    _syncActivitySweep();
  }

  /// Le balayage de péremption ne tourne que tant qu'une activité est
  /// affichée — inutile de réveiller l'app toutes les 3 s quand personne
  /// n'écrit.
  void _syncActivitySweep() {
    if (activities.isEmpty) {
      _activitySweep?.cancel();
      _activitySweep = null;
      return;
    }
    _activitySweep ??= Timer.periodic(
      _activitySweepInterval,
      (_) => _refreshActivities(),
    );
  }

  void _apply(List<Conversation> raw) {
    final myUid = _auth.uid;
    conversations.assignAll(
      raw.map((conv) {
        final cached = _profileCache[conv.otherUid(myUid)];
        return conv.copyWith(
          otherUserName: cached?.name ?? 'Utilisateur',
          otherUserPhotoUrl: cached?.photoUrl,
          otherUserVerified: cached?.verified ?? false,
        );
      }).toList(),
    );
  }

  /// Complète en arrière-plan les profils encore inconnus, puis republie
  /// la liste. Ne bloque jamais l'affichage.
  Future<void> _enrich(List<Conversation> raw) async {
    final myUid = _auth.uid;
    final missing = raw
        .map((c) => c.otherUid(myUid))
        .where((uid) => uid.isNotEmpty && !_profileCache.containsKey(uid))
        .toSet();
    if (missing.isEmpty) return;

    var changed = false;
    await Future.wait(
      missing.map((uid) async {
        final profile = await _readProfile(uid);
        if (profile == null) return;
        _profileCache[uid] = profile;
        changed = true;
      }),
    );
    // Toujours republier le snapshot le plus récent : un enrichissement
    // lancé plus tôt ne doit pas écraser l'ordre ni l'aperçu d'un message
    // arrivé entre-temps.
    if (changed) _apply(_latestRaw);
  }

  /// Cache disque d'abord, réseau seulement en secours : un `get()` normal
  /// part systématiquement vers le serveur, même quand le profil est déjà
  /// connu localement.
  Future<_PeerProfile?> _readProfile(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) return _profileFrom(cached.data()!);
    } on FirebaseException catch (_) {
      // Absent du cache local : on tente le serveur juste en dessous.
    }
    try {
      final doc = await ref.get();
      return doc.exists
          ? _profileFrom(doc.data()!)
          : const _PeerProfile(name: 'Utilisateur');
    } on FirebaseException catch (_) {
      // Réseau ou permissions : on retentera à la prochaine ouverture
      // plutôt que de figer un mauvais nom dans le cache.
      return null;
    }
  }

  static _PeerProfile _profileFrom(Map<String, dynamic> data) {
    // Une chaîne vide en base doit se comporter comme une absence de photo,
    // sinon l'avatar tente de charger une URL vide au lieu d'afficher les
    // initiales.
    final photo = (data['photoUrl'] as String?)?.trim();
    return _PeerProfile(
      name: data['displayName'] as String? ?? 'Utilisateur',
      photoUrl: (photo == null || photo.isEmpty) ? null : photo,
      verified: data['verified'] as bool? ?? false,
    );
  }

  void openChat(Conversation conv) {
    Get.toNamed(
      AppRoutes.chat,
      arguments: {
        'conversationId': conv.id,
        'otherUid': conv.otherUid(_auth.uid),
      },
    );
  }

  Future<void> startNewChat() async {
    Get.toNamed(AppRoutes.community);
  }

  String timeLabel(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} j';
  }
}

/// Ce que la liste des conversations a besoin de savoir d'un interlocuteur.
class _PeerProfile {
  const _PeerProfile({
    required this.name,
    this.photoUrl,
    this.verified = false,
  });

  final String name;
  final String? photoUrl;
  final bool verified;
}
