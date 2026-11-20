import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get_thumbnail_video/index.dart';
import '../services/video_compression_service.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/call.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/report.dart';
import '../models/user_profile.dart';
import '../routes/app_routes.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/report_sheet.dart';
import '../services/scam_guard.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/follow_service.dart';
import '../services/moderation_service.dart';

/// Durée d'inactivité de saisie après laquelle on repasse à "idle" côté
/// local (indépendamment du côté distant, qui a sa propre marge — voir
/// [chatActivityStaleAfter]).
const _typingIdleAfter = Duration(seconds: 3);

/// Intervalle de rafraîchissement de l'activité envoyée pendant qu'on
/// écrit/enregistre — évite qu'un `typing` de plus de quelques secondes
/// paraisse "périmé" côté distant (voir [chatActivityStaleAfter]).
const _activityHeartbeatInterval = Duration(seconds: 5);

class ChatController extends GetxController {
  final messages = <ChatMessage>[].obs;
  final otherProfile = Rxn<UserProfile>();
  final conversation = Rxn<Conversation>();
  final otherActivity = ChatActivity.idle.obs;
  final isLoading = true.obs;
  final isRecording = false.obs;
  final recordDuration = 0.obs;
  final ephemeralSeconds = Rxn<int>();

  /// « Le prochain média part à vue unique ».
  ///
  /// Armé le temps d'un envoi, puis désarmé tout seul : laissé actif, on
  /// enverrait à vue unique sans s'en rendre compte, et c'est le genre
  /// d'erreur qu'on ne peut pas rattraper. Contrairement au réglage
  /// éphémère, qui vaut pour la conversation et se négocie à deux, celui-ci
  /// est local à qui envoie et ne quitte jamais l'appareil.
  final viewOnceArmed = false.obs;

  void toggleViewOnce() => viewOnceArmed.value = !viewOnceArmed.value;

  /// Lit l'armement **et le retire**. Appelé une fois par geste d'envoi —
  /// une rafale de photos choisies ensemble compte pour un seul geste.
  bool _consumeViewOnceArm() {
    final armed = viewOnceArmed.value;
    viewOnceArmed.value = false;
    return armed;
  }

  final showStickers = false.obs;

  /// Avertissement anti-arnaque déclenché par le dernier message reçu,
  /// ou `null` si rien n'a été repéré. L'app ne gère aucun paiement : la
  /// seule protection qu'elle peut offrir est de prévenir au moment
  /// précis où quelqu'un réclame de l'argent avant toute rencontre.
  final scamWarning = RxnString();

  /// Messages dont l'avertissement a déjà été écarté — pour ne pas le
  /// faire réapparaître à chaque reconstruction du fil.
  final _dismissedScamIds = <String>{};

  /// Message auquel on est en train de répondre (bandeau au-dessus du champ
  /// de saisie), façon iMessage / WhatsApp. `null` = pas de réponse en cours.
  final replyingTo = Rxn<ChatMessage>();

  /// Message brièvement surligné après un appui sur une citation (pour le
  /// retrouver visuellement dans le fil).
  final highlightedId = RxnString();

  /// Historique antérieur à la fenêtre temps réel, du plus ancien au plus
  /// récent. Chargé page par page en remontant (voir [loadOlder]) : sans
  /// lui, tout ce qui dépassait les 50 derniers messages était
  /// inatteignable depuis l'app.
  final _olderMessages = <ChatMessage>[];

  /// Faux quand on a atteint le début de la conversation.
  final hasMoreHistory = true.obs;
  final isLoadingHistory = false.obs;

  /// Recherche dans la conversation : le texte cherché, et les
  /// identifiants des messages qui correspondent, du plus récent au plus
  /// ancien (l'ordre dans lequel on veut les parcourir).
  final searchQuery = ''.obs;
  final searchResults = <String>[].obs;
  final searchIndex = 0.obs;
  final isSearching = false.obs;

  /// Identifiant du premier message reçu non lu à l'ouverture — la barre
  /// « messages non lus » se pose juste avant. Figé au premier calcul :
  /// il ne doit pas remonter au fur et à mesure qu'on lit.
  final firstUnreadId = RxnString();
  bool _firstUnreadResolved = false;

  /// Clé du brouillon de cette discussion dans les préférences locales.
  String get _draftKey => 'chat_draft_$_conversationId';

  late final TextEditingController textController;
  late final ScrollController scrollController;
  late final FocusNode inputFocusNode;
  late final AudioRecorder _recorder;

  /// Une clé par bulle affichée — permet à [jumpToMessage] de faire défiler
  /// jusqu'au message cité via `Scrollable.ensureVisible`.
  final _bubbleKeys = <String, GlobalKey>{};
  GlobalKey bubbleKey(String id) =>
      _bubbleKeys.putIfAbsent(id, () => GlobalKey());

  Timer? _recordTimer;
  Timer? _typingIdleTimer;
  Timer? _activityHeartbeat;
  Timer? _activityStaleTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _otherProfileSub;
  StreamSubscription? _activitySub;

  String _conversationId = '';
  String _otherUid = '';

  /// Instant de réception du dernier signal d'activité de l'autre
  /// participant — base du calcul de péremption (voir
  /// [chatActivityStaleAfter] et `ChatService.watchActivity`).
  DateTime? _otherActivityAt;

  // ---------------------------------------------------------------------
  // Envoi optimiste façon WhatsApp : un message apparaît immédiatement
  // dans la conversation (état `sending`), et bascule en `failed` avec un
  // bouton de renvoi si l'upload/l'écriture échoue — voir _addLocalMessage
  // / retrySend. `_serverMessages` est la vérité Firestore ; les entrées
  // de `_localMessages` dont l'id est déjà dans `_serverMessages` sont de
  // simples doublons en attente de remplacement (même id des deux côtés,
  // voir ChatService.newMessageId) et sont purgées dans `_watchMessages`.
  final _serverMessages = <ChatMessage>[];
  final _localMessages = <String, ChatMessage>{};
  final _retryActions = <String, Future<void> Function()>{};

  /// Messages déjà marqués comme lus (voir [_batchMarkAsRead]).
  final _markedRead = <String>{};

  AuthService get _auth => Get.find<AuthService>();
  ChatService get _chat => Get.find<ChatService>();
  FollowService get _follow => Get.find<FollowService>();
  ModerationService get _moderation => Get.find<ModerationService>();

  /// J'ai bloqué mon interlocuteur : la saisie laisse place à « Débloquer ».
  /// Lu dans un `Obx`, réagit au blocage comme au déblocage.
  bool get iBlockedPeer => _moderation.isBlocked(_otherUid);

  /// Mon interlocuteur m'a bloqué : le serveur refuserait tout envoi.
  bool get peerBlockedMe => _moderation.isBlockedBy(_otherUid);

  /// Débloque l'interlocuteur depuis la discussion.
  Future<void> unblockPeer() async {
    if (_otherUid.isEmpty || !_auth.isSignedIn) return;
    try {
      await _moderation.unblockUser(myUid: _auth.uid, targetUid: _otherUid);
    } catch (e) {
      Get.snackbar('Déblocage impossible', '$e');
    }
  }

  String get myUid => _auth.uid;

  /// Uid de l'autre participant — lu par PushService pour ne pas notifier
  /// un message de la conversation déjà ouverte.
  String get peerUid => _otherUid;

  bool get isOtherOnline => otherProfile.value?.isOnline ?? false;

  @override
  void onInit() {
    super.onInit();
    textController = TextEditingController();
    scrollController = ScrollController();
    inputFocusNode = FocusNode();
    _recorder = AudioRecorder();

    final args = Get.arguments as Map<String, dynamic>;
    _otherUid = args['otherUid'] as String;
    // Message pré-rempli quand la discussion est ouverte depuis une annonce
    // du Marché (« Contacter le vendeur » / « Faire une offre ») : on remplit
    // le champ, l'utilisateur relit puis envoie.
    final prefill = (args['prefill'] as String?)?.trim() ?? '';
    if (prefill.isNotEmpty) {
      textController.text = prefill;
      textController.selection = TextSelection.collapsed(
        offset: prefill.length,
      );
    }
    textController.addListener(notifyTyping);
    // Brouillon : ce qui a été tapé sans être envoyé se retrouve en
    // revenant. Ne remplace jamais un préremplissage venu du Marché, qui
    // porte l'intention du moment.
    if (prefill.isEmpty) unawaited(_restoreDraft());
    // Calculable localement (pas d'aller-retour réseau) : on démarre
    // l'écoute des messages tout de suite au lieu d'attendre la
    // confirmation/création de la conversation, qui tournait avant en
    // série et doublait le temps avant le premier affichage.
    _conversationId = Conversation.buildId(myUid, _otherUid);

    // Envois encore en vol quand l'écran a été quitté : leurs bulles
    // « en cours » reviennent telles quelles (voir
    // ChatService.inFlightFor), **avec** leur action de renvoi — sans
    // elle, un envoi retombé en échec afficherait une flèche de renvoi
    // qui ne fait rien.
    for (final pending in _chat.inFlightFor(_conversationId).values) {
      _localMessages[pending.id] = pending;
      _retryActions[pending.id] = _retryActionFor(pending);
    }

    // Badge remis à zéro dès que le document existe (no-op si la
    // conversation n'a pas encore été créée — voir _ensureConversation).
    _chat.clearUnread(_conversationId, myUid).catchError((_) {});
    _watchOtherProfile();
    _watchMessages();
    _watchOtherActivity();
    _conversationReady = _ensureConversation();
  }

  /// Création (ou lecture) du document de conversation, lancée à
  /// l'ouverture. Le premier message l'attend : écrit avant, il partait
  /// bien, mais son aperçu et le badge non lu étaient refusés (le document
  /// n'existait pas encore) et la conversation n'apparaissait pas dans la
  /// liste de l'autre. Borné dans le temps pour ne jamais bloquer un envoi
  /// hors ligne.
  Future<void> _conversationReady = Future.value();

  /// Où en est l'envoi d'une vidéo, par id de message : d'abord la
  /// compression, puis la montée vers Storage. Lu par la bulle.
  final videoProgress = <String, ({bool compressing, double value})>{}.obs;

  /// Vidéos déjà compressées, par id de message : un renvoi après échec
  /// réutilise le fichier au lieu de tout recompresser.
  final _preparedVideos = <String, PreparedVideo>{};

  Future<void> _awaitConversation() =>
      _conversationReady.timeout(const Duration(seconds: 6), onTimeout: () {});

  @override
  void onClose() {
    // Avant de disposer du contrôleur de texte : après, son contenu n'est
    // plus lisible.
    unawaited(_saveDraft(textController.text));
    textController.removeListener(notifyTyping);
    textController.dispose();
    scrollController.dispose();
    inputFocusNode.dispose();
    _msgSub?.cancel();
    _otherProfileSub?.cancel();
    _activitySub?.cancel();
    _recordTimer?.cancel();
    _typingIdleTimer?.cancel();
    _activityHeartbeat?.cancel();
    _activityStaleTimer?.cancel();
    _pushActivity(ChatActivity.idle);
    // Nettoie les vocaux dont l'envoi a échoué et n'a jamais été rejoué —
    // sinon leur fichier temporaire reste orphelin sur le disque.
    for (final msg in _localMessages.values) {
      if (msg.type == MessageType.voice &&
          msg.status == MessageDeliveryStatus.failed) {
        _safeDeleteFile(msg.content);
      }
      // Vidéo compressée dont l'envoi a échoué : le renvoi n'est plus
      // possible une fois l'écran quitté, le fichier temporaire part.
      if (msg.type == MessageType.video &&
          msg.status == MessageDeliveryStatus.failed) {
        unawaited(_preparedVideos.remove(msg.id)?.discard());
      }
    }
    _recorder.dispose();
    super.onClose();
  }

  void _watchOtherProfile() {
    _otherProfileSub = _follow.watchUserProfile(
      uid: _otherUid,
      onData: (data) {
        otherProfile.value = data != null
            ? UserProfile.fromMap(_otherUid, data)
            : null;
      },
    );
  }

  Future<void> _ensureConversation() async {
    try {
      final result = await _chat.getOrCreateConversation(myUid, _otherUid);
      conversation.value = result.conversation;
      ephemeralSeconds.value = result.conversation.ephemeralSeconds;

      await _chat.clearUnread(_conversationId, myUid).catchError((_) {});

      // Ré-abonnement uniquement si le document vient d'être créé : avant
      // ça les règles Firestore refusaient la lecture de ses
      // sous-collections, donc l'écoute lancée par onInit() est morte
      // silencieusement et doit repartir. Le faire dans tous les cas
      // (ce qu'on faisait ici) jetait un listener déjà chaud, avec son
      // snapshot en cache, pour repartir sur un aller-retour serveur :
      // l'écran restait sur son chargeur alors que les messages étaient
      // déjà disponibles localement.
      if (result.created) {
        _watchMessages();
        _watchOtherActivity();
      }
    } on Exception catch (e) {
      // La conversation existe déjà côté serveur dans l'immense majorité
      // des cas (elle n'est créée qu'au tout premier message) : les
      // écoutes ouvertes par onInit() restent valides, on les laisse.
      developer.log(
        'getOrCreateConversation error',
        name: 'ChatController',
        error: e,
      );
    }
  }

  void _watchOtherActivity() {
    _activitySub?.cancel();
    _activityStaleTimer?.cancel();
    _activitySub = _chat.watchActivity(
      conversationId: _conversationId,
      uid: _otherUid,
      onData: (activity) {
        _otherActivityAt = DateTime.now();
        _applyOtherActivity(activity);
      },
    );
    // L'autre participant peut disparaître (crash, réseau) sans jamais
    // renvoyer "idle" : on revérifie périodiquement l'ancienneté du
    // dernier signal reçu plutôt que de ne réagir qu'aux nouveaux
    // snapshots.
    _activityStaleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _applyOtherActivity(otherActivity.value);
    });
  }

  void _applyOtherActivity(ChatActivity activity) {
    final at = _otherActivityAt;
    final stale =
        at == null || DateTime.now().difference(at) > chatActivityStaleAfter;
    otherActivity.value = stale ? ChatActivity.idle : activity;
  }

  void _watchMessages() {
    _msgSub?.cancel();
    _msgSub = _chat.watchMessages(
      conversationId: _conversationId,
      onData: (list) {
        final hasNewMessages = list.length > _serverMessages.length;
        _serverMessages
          ..clear()
          ..addAll(list);
        // Un message local dont l'id apparaît maintenant côté serveur est
        // confirmé : sa version serveur (avec readAt/expiresAt à jour)
        // prend le relais, plus besoin de la copie locale ni de son
        // action de renvoi.
        final confirmedIds = list.map((m) => m.id).toSet();
        _localMessages.removeWhere((id, _) => confirmedIds.contains(id));
        _retryActions.removeWhere((id, _) => confirmedIds.contains(id));

        _resolveFirstUnread(list);
        _rebuildMessages();
        isLoading.value = false;

        if (hasNewMessages) _scrollToBottom();

        _batchMarkAsRead(list);
      },
      onError: (e) {
        developer.log('watchMessages error', name: 'ChatController', error: e);
        isLoading.value = false;
      },
    );
  }

  /// Repère le premier message reçu non lu, une seule fois par ouverture.
  ///
  /// Figé volontairement : la barre « messages non lus » doit rester où
  /// elle est pendant qu'on lit, sinon elle glisserait vers le bas à
  /// chaque accusé de lecture et ne servirait plus de repère.
  void _resolveFirstUnread(List<ChatMessage> list) {
    if (_firstUnreadResolved) return;
    if (list.isEmpty) return;
    _firstUnreadResolved = true;
    ChatMessage? unread;
    for (final m in list) {
      if (m.senderUid != myUid && !m.isRead) {
        unread = m;
        break;
      }
    }
    // Rien à signaler si tout est lu, ou si le premier non lu est déjà le
    // tout premier message affiché : la barre ferait alors doublon avec
    // le haut de la conversation.
    if (unread == null || unread.id == list.first.id) return;
    firstUnreadId.value = unread.id;
  }

  void _rebuildMessages() {
    // L'écran a pu être quitté pendant un envoi : l'écriture, elle, va au
    // bout, mais plus rien ne doit toucher aux observables.
    if (isClosed) return;
    final confirmedIds = _serverMessages.map((m) => m.id).toSet();
    final pending = _localMessages.values.where(
      (m) => !confirmedIds.contains(m.id),
    );
    // L'historique remonté par `loadOlder` précède toujours la fenêtre
    // temps réel ; les doublons éventuels (un message présent dans les
    // deux) sont écartés par identifiant.
    final older = _olderMessages.where((m) => !confirmedIds.contains(m.id));
    final merged =
        [...older, ..._serverMessages, ...pending]
            // « Supprimé pour moi » : le message existe toujours pour
            // l'autre, il n'apparaît simplement plus ici.
            .where((m) => !m.isHiddenFor(myUid))
            .toList()
          ..sort(_chronological);
    messages.assignAll(merged);

    // Ne garde que les clés des messages encore présents.
    final liveIds = merged.map((m) => m.id).toSet();
    _bubbleKeys.removeWhere((id, _) => !liveIds.contains(id));

    _checkForScam(merged);
  }

  /// Analyse le dernier message **reçu** : c'est celui qui peut porter la
  /// demande d'acompte ou de transfert. Ce qu'on écrit soi-même n'a pas à
  /// être commenté.
  void _checkForScam(List<ChatMessage> merged) {
    final incoming = merged.reversed.where(
      (m) => m.senderUid != myUid && m.type == MessageType.text,
    );
    if (incoming.isEmpty) {
      scamWarning.value = null;
      return;
    }
    final last = incoming.first;
    if (_dismissedScamIds.contains(last.id)) {
      scamWarning.value = null;
      return;
    }
    scamWarning.value = ScamGuard.warningFor(last.content);
    if (scamWarning.value != null) _lastScamMessageId = last.id;
  }

  String? _lastScamMessageId;

  void dismissScamWarning() {
    final id = _lastScamMessageId;
    if (id != null) _dismissedScamIds.add(id);
    scamWarning.value = null;
  }

  // ---------------------------------------------------------------------
  // Répondre à un message (citation façon iMessage)
  // ---------------------------------------------------------------------

  /// Reconstruit l'action de renvoi d'un message resté en vol.
  ///
  /// Le message porte déjà tout ce qu'il faut : son type, le chemin local
  /// du fichier (le contenu tant que l'envoi n'est pas confirmé) et les
  /// champs de la citation. Ces derniers reviennent par un message de
  /// façade — `sendMessage` n'en lit que l'identifiant, l'expéditeur et
  /// l'aperçu, et l'original n'est plus forcément chargé.
  Future<void> Function() _retryActionFor(ChatMessage pending) {
    final replyTo = pending.replyToId == null
        ? null
        : ChatMessage(
            id: pending.replyToId!,
            senderUid: pending.replyToSenderUid ?? '',
            type: MessageType.text,
            content: pending.replyToText ?? '',
            createdAt: pending.createdAt,
          );

    if (pending.type == MessageType.text ||
        pending.type == MessageType.sticker) {
      return () => _finishSend(
        id: pending.id,
        type: pending.type,
        content: pending.content,
        replyTo: replyTo,
      );
    }
    return () => _uploadAndSend(
      id: pending.id,
      type: pending.type,
      localPath: pending.content,
      durationMs: pending.durationMs,
      fileName: pending.fileName,
      replyTo: replyTo,
    );
  }

  // -----------------------------------------------------------------------
  // Brouillon
  // -----------------------------------------------------------------------

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString(_draftKey) ?? '';
      // L'écran a pu être quitté, ou quelque chose déjà tapé pendant la
      // lecture des préférences : dans les deux cas on ne touche à rien.
      if (isClosed || draft.isEmpty || textController.text.isNotEmpty) return;
      textController.text = draft;
      textController.selection = TextSelection.collapsed(offset: draft.length);
    } catch (e) {
      developer.log('restoreDraft', name: 'ChatController', error: e);
    }
  }

  Future<void> _saveDraft(String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = text.trim();
      if (draft.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, draft);
      }
    } catch (e) {
      developer.log('saveDraft', name: 'ChatController', error: e);
    }
  }

  // -----------------------------------------------------------------------
  // Historique
  // -----------------------------------------------------------------------

  /// Remonte une page d'historique avant le plus ancien message affiché.
  ///
  /// L'écoute temps réel ne porte que sur les derniers messages : au-delà,
  /// la conversation n'était pas seulement masquée, elle était
  /// inatteignable. Appelée quand la liste arrive en haut.
  Future<void> loadOlder() async {
    if (isLoadingHistory.value || !hasMoreHistory.value) return;
    if (messages.isEmpty) return;

    isLoadingHistory.value = true;
    try {
      final page = await _chat.loadOlderMessages(
        conversationId: _conversationId,
        before: messages.first.createdAt,
      );
      if (page.isEmpty) {
        hasMoreHistory.value = false;
      } else {
        final known = messages.map((m) => m.id).toSet();
        // Hauteur déjà défilée avant l'insertion : le contenu s'ajoute
        // **au-dessus**, donc sans recalage la liste garderait le même
        // décalage en pixels et sauterait ailleurs dans la conversation.
        final before = scrollController.hasClients
            ? scrollController.position.maxScrollExtent
            : null;
        _olderMessages.insertAll(0, page.where((m) => !known.contains(m.id)));
        _rebuildMessages();
        if (before != null) _restoreScrollAfterPrepend(before);
      }
    } catch (e) {
      developer.log('loadOlder', name: 'ChatController', error: e);
    } finally {
      isLoadingHistory.value = false;
    }
  }

  /// Replace la vue là où elle était après l'ajout de messages en tête :
  /// on se décale de la hauteur gagnée, mesurée une fois la liste
  /// reconstruite.
  void _restoreScrollAfterPrepend(double extentBefore) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || !scrollController.hasClients) return;
      final gained = scrollController.position.maxScrollExtent - extentBefore;
      if (gained <= 0) return;
      scrollController.jumpTo(
        (scrollController.offset + gained).clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  // -----------------------------------------------------------------------
  // Supprimer / réagir
  // -----------------------------------------------------------------------

  /// Retire un message pour tout le monde. Le document reste, vidé : le
  /// supprimer pour de bon laisserait un trou dans les réponses qui le
  /// citent. Le fichier joint, lui, part vraiment de Storage.
  Future<void> deleteMessage(ChatMessage message) async {
    // Le délai est aussi vérifié par les règles : ce contrôle évite un
    // aller-retour voué à être refusé, il ne le remplace pas.
    if (!message.canDeleteForEveryone(myUid)) return;
    try {
      await _chat.deleteMessage(
        conversationId: _conversationId,
        message: message,
      );
    } catch (e) {
      _reportSendError('deleteMessage failed for ${message.id}', e);
    }
  }

  /// Retire le message de **mon seul** affichage. Toujours possible, quel
  /// que soit l'expéditeur et l'âge du message : ce que je choisis de ne
  /// plus voir ne regarde que moi.
  Future<void> hideMessage(ChatMessage message) async {
    if (message.isHiddenFor(myUid)) return;
    try {
      await _chat.hideMessageForMe(
        conversationId: _conversationId,
        messageId: message.id,
        uid: myUid,
      );
    } catch (e) {
      _reportSendError('hideMessage failed for ${message.id}', e);
    }
  }

  /// Pose, remplace ou retire sa réaction. Une seule par personne :
  /// reposer le même emoji l'enlève.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    if (message.deleted) return;
    final current = message.reactions[myUid];
    try {
      await _chat.setReaction(
        conversationId: _conversationId,
        messageId: message.id,
        uid: myUid,
        emoji: current == emoji ? null : emoji,
      );
    } catch (e) {
      _reportSendError('setReaction failed for ${message.id}', e);
    }
  }

  /// Fait suivre un message dans une autre discussion.
  ///
  /// Le contenu est recopié tel quel — pour une photo ou un document,
  /// c'est l'URL déjà en ligne qui repart, sans nouvel envoi de fichier.
  /// Ni un message supprimé ni un message à vue unique ne se transfèrent.
  Future<bool> forwardMessage(ChatMessage message, String toUid) async {
    if (message.deleted || toUid.isEmpty || toUid == myUid) return false;
    // Un message à vue unique ne se fait pas suivre : la copie vivrait
    // dans une autre conversation, hors de portée de la consommation —
    // « vue unique » n'y voudrait plus rien dire.
    if (message.viewOnce) return false;
    // Un média encore en cours d'envoi n'a qu'un chemin local, illisible
    // depuis le téléphone d'en face.
    final isFile =
        message.type != MessageType.text && message.type != MessageType.sticker;
    if (isFile && !message.content.startsWith('http')) return false;
    final targetId = Conversation.buildId(myUid, toUid);
    try {
      await _chat.getOrCreateConversation(myUid, toUid);
      await _chat.sendMessage(
        conversationId: targetId,
        messageId: _chat.newMessageId(targetId),
        senderUid: myUid,
        recipientUid: toUid,
        type: message.type,
        content: message.content,
        fileName: message.fileName,
        durationMs: message.durationMs,
        // Sans elle, une vidéo transférée arrivait sans aperçu.
        thumbUrl: message.thumbUrl,
      );
      return true;
    } catch (e) {
      _reportSendError('forwardMessage failed for ${message.id}', e);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Recherche dans la conversation
  // -----------------------------------------------------------------------

  /// La recherche porte sur ce qui est **chargé** : le texte des messages
  /// en mémoire, historique remonté compris. Firestore n'offre pas de
  /// recherche plein texte, et indexer chaque mot de chaque message coûte
  /// plus que ce que ça rapporte ici — remonter l'historique élargit la
  /// recherche d'autant.
  void updateSearch(String query) {
    searchQuery.value = query;
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      searchResults.clear();
      searchIndex.value = 0;
      return;
    }
    final hits = messages
        .where(
          (m) =>
              !m.deleted &&
              (m.type == MessageType.text || m.type == MessageType.document) &&
              (m.type == MessageType.document ? (m.fileName ?? '') : m.content)
                  .toLowerCase()
                  .contains(needle),
        )
        .map((m) => m.id)
        .toList()
        .reversed
        .toList();
    searchResults.assignAll(hits);
    searchIndex.value = 0;
    if (hits.isNotEmpty) jumpToMessage(hits.first);
  }

  void nextSearchResult() => _moveSearch(1);
  void previousSearchResult() => _moveSearch(-1);

  void _moveSearch(int step) {
    if (searchResults.isEmpty) return;
    final next =
        (searchIndex.value + step + searchResults.length) %
        searchResults.length;
    searchIndex.value = next;
    jumpToMessage(searchResults[next]);
  }

  void openSearch() => isSearching.value = true;

  void closeSearch() {
    isSearching.value = false;
    searchQuery.value = '';
    searchResults.clear();
    searchIndex.value = 0;
  }

  void startReply(ChatMessage message) {
    replyingTo.value = message;
    inputFocusNode.requestFocus();
  }

  void cancelReply() => replyingTo.value = null;

  /// Fait défiler le fil jusqu'au message cité et le surligne brièvement.
  Future<void> jumpToMessage(String id) async {
    final idx = messages.indexWhere((m) => m.id == id);
    if (idx < 0) {
      Get.snackbar(
        'Message indisponible',
        'Le message d’origine a été supprimé ou n’est plus chargé.',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    highlightedId.value = id;

    Future<bool> ensureVisible() async {
      final ctx = _bubbleKeys[id]?.currentContext;
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return true;
    }

    if (!await ensureVisible() && scrollController.hasClients) {
      // Message pas encore construit : on s'en approche par estimation
      // (l'index rapporté à l'étendue scrollable) puis on retente.
      final pos = scrollController.position;
      final target = pos.maxScrollExtent * (idx / messages.length);
      await scrollController.animateTo(
        target.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await ensureVisible();
    }

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (highlightedId.value == id) highlightedId.value = null;
  }

  /// Ordre « vraie discussion » : les messages dont l'horodatage serveur
  /// est résolu passent en premier, dans l'ordre du serveur (seule
  /// référence commune aux deux appareils) ; ceux encore en attente
  /// d'accusé serveur (les nôtres, tout juste envoyés) restent en bas,
  /// dans leur ordre d'envoi local. Sans ça, une horloge d'appareil
  /// décalée fait remonter nos messages optimistes au-dessus de messages
  /// déjà confirmés, et un message change de place quand son timestamp
  /// serveur arrive.
  static int _chronological(ChatMessage a, ChatMessage b) {
    if (a.hasServerTimestamp != b.hasServerTimestamp) {
      return a.hasServerTimestamp ? -1 : 1;
    }
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      // L'écran a pu être quitté pendant ce délai : le contrôleur de
      // défilement est alors déjà disposé.
      if (isClosed) return;
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _batchMarkAsRead(List<ChatMessage> list) {
    // `readAt` est un horodatage serveur : jusqu'à ce que le serveur le
    // résolve, les snapshots locaux le voient encore à `null`, donc les
    // mêmes messages repassaient pour non lus et déclenchaient un nouveau
    // batch à chaque snapshot — une rafale d'écritures qui saturait la
    // connexion et faisait ramer la discussion. On ne marque chaque id
    // qu'une fois, et on le relibère seulement si l'écriture échoue.
    final unreadIds = [
      for (final m in list)
        if (m.senderUid != myUid && !m.isRead && _markedRead.add(m.id)) m.id,
    ];
    if (unreadIds.isEmpty) return;
    _chat.markAsRead(_conversationId, unreadIds, myUid).catchError((_) {
      _markedRead.removeAll(unreadIds);
    });
  }

  /// Appelé à chaque frappe (écoute posée sur `textController`). Envoie
  /// "typing" au premier caractère puis se rafraîchit toutes les 5s tant
  /// qu'on continue d'écrire ; repasse à "idle" après 3s sans frappe.
  void notifyTyping() {
    if (textController.text.trim().isEmpty) {
      _stopActivity();
      return;
    }
    if (_activityHeartbeat == null) _startActivity(ChatActivity.typing);
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(_typingIdleAfter, _stopActivity);
  }

  void _startActivity(ChatActivity activity) {
    _pushActivity(activity);
    _activityHeartbeat?.cancel();
    _activityHeartbeat = Timer.periodic(
      _activityHeartbeatInterval,
      (_) => _pushActivity(activity),
    );
  }

  void _stopActivity() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    if (_activityHeartbeat == null) return;
    _activityHeartbeat?.cancel();
    _activityHeartbeat = null;
    _pushActivity(ChatActivity.idle);
  }

  void _pushActivity(ChatActivity activity) {
    _chat.setActivity(_conversationId, myUid, activity).catchError((_) {});
  }

  // ---------------------------------------------------------------------
  // Envoi optimiste
  // ---------------------------------------------------------------------

  ChatMessage _pendingMessage({
    required String id,
    required MessageType type,
    required String content,
    String? fileName,
    int? durationMs,
    String? thumbUrl,
    bool viewOnce = false,
    ChatMessage? replyTo,
  }) {
    final eph = ephemeralSeconds.value;
    final expiresAt = (eph != null && eph > 0)
        ? DateTime.now().add(Duration(seconds: eph))
        : null;
    return ChatMessage(
      id: id,
      senderUid: myUid,
      type: type,
      content: content,
      fileName: fileName,
      durationMs: durationMs,
      thumbUrl: thumbUrl,
      viewOnce: viewOnce,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      status: MessageDeliveryStatus.sending,
      hasServerTimestamp: false,
      replyToId: replyTo?.id,
      replyToSenderUid: replyTo?.senderUid,
      replyToText: replyTo?.shortPreview,
    );
  }

  void _addLocalMessage(ChatMessage msg) {
    _localMessages[msg.id] = msg;
    // Confié aussi au service, qui survit à l'écran : quitter la
    // discussion pendant un envoi ne doit plus faire disparaître la bulle
    // « en cours » alors que l'envoi continue en arrière-plan.
    _chat.markInFlight(_conversationId, msg);
    _rebuildMessages();
    _scrollToBottom();
  }

  void _updateLocalStatus(String id, MessageDeliveryStatus status) {
    final msg = _localMessages[id];
    if (msg == null) return;
    final updated = msg.copyWith(status: status);
    _localMessages[id] = updated;
    _chat.markInFlight(_conversationId, updated);
    _rebuildMessages();
  }

  /// Envoi terminé : la bulle locale n'a plus lieu d'être, la version
  /// serveur prend le relais.
  void _clearPending(String id) {
    _retryActions.remove(id);
    _chat.clearInFlight(_conversationId, id);
  }

  /// Écriture Firestore pure (texte/sticker : pas d'upload préalable).
  Future<void> _finishSend({
    required String id,
    required MessageType type,
    required String content,
    ChatMessage? replyTo,
  }) async {
    try {
      await _awaitConversation();
      await _chat.sendMessage(
        conversationId: _conversationId,
        messageId: id,
        senderUid: myUid,
        recipientUid: _otherUid,
        type: type,
        content: content,
        ephemeralSeconds: ephemeralSeconds.value,
        replyToId: replyTo?.id,
        replyToSenderUid: replyTo?.senderUid,
        replyToText: replyTo?.shortPreview,
      );
      _clearPending(id);
    } on Exception catch (e) {
      _reportSendError('sendMessage failed for $id', e);
      _updateLocalStatus(id, MessageDeliveryStatus.failed);
    }
  }

  /// Log + snackbar avec le message technique réel — sur un téléphone de
  /// test sans câble/console branchés, "échec d'envoi" seul ne dit pas
  /// pourquoi (permission Firestore, réseau, règles Storage...).
  void _reportSendError(String context, Object e) {
    developer.log(context, name: 'ChatController', error: e);
    // Écran quitté : l'envoi s'est poursuivi sans lui, mais une alerte
    // surgissant sur un autre écran ne dirait rien à personne.
    if (!isClosed && Get.overlayContext != null) {
      Get.snackbar(
        'Échec d’envoi',
        '$e',
        duration: const Duration(seconds: 10),
        isDismissible: true,
      );
    }
  }

  /// Upload (voix/image/vidéo/document) puis écriture Firestore. `localPath`
  /// reste le contenu affiché tant que l'envoi n'est pas confirmé — la
  /// bulle lit directement le fichier local le temps de l'upload (voir
  /// _MessageBubble._buildImage / _togglePlayVoice côté UI).
  Future<void> _uploadAndSend({
    required String id,
    required MessageType type,
    required String localPath,
    int? durationMs,
    String? fileName,
    String? thumbPath,
    bool viewOnce = false,
    ChatMessage? replyTo,
  }) async {
    try {
      final url = switch (type) {
        MessageType.voice => await _chat.uploadVoice(
          localPath,
          _conversationId,
        ),
        MessageType.image => await _chat.uploadImage(
          localPath,
          _conversationId,
        ),
        MessageType.video => await _uploadVideo(id, localPath),
        MessageType.document => await _chat.uploadDocument(
          localPath,
          _conversationId,
          fileName!,
        ),
        MessageType.text ||
        MessageType.sticker => throw StateError('unsupported upload type'),
      };
      // La vignette part après la vidéo : si l'envoi du gros fichier
      // échoue, on n'a pas laissé une image orpheline dans Storage.
      // Son échec à elle, en revanche, ne doit pas emporter le message —
      // une vidéo sans aperçu vaut mieux que pas de vidéo.
      String? thumbUrl;
      if (thumbPath != null) {
        try {
          thumbUrl = await _chat.uploadVideoThumb(thumbPath, _conversationId);
        } on Exception catch (e) {
          developer.log(
            'Vignette non envoyée pour $id',
            name: 'ChatController',
            error: e,
          );
        }
      }
      await _awaitConversation();
      await _chat.sendMessage(
        conversationId: _conversationId,
        messageId: id,
        senderUid: myUid,
        recipientUid: _otherUid,
        type: type,
        content: url,
        fileName: fileName,
        durationMs: durationMs,
        thumbUrl: thumbUrl,
        viewOnce: viewOnce,
        ephemeralSeconds: ephemeralSeconds.value,
        replyToId: replyTo?.id,
        replyToSenderUid: replyTo?.senderUid,
        replyToText: replyTo?.shortPreview,
      );
      _clearPending(id);
      if (type == MessageType.voice) _safeDeleteFile(localPath);
      if (type == MessageType.video) {
        unawaited(_preparedVideos.remove(id)?.discard());
      }
    } on Exception catch (e) {
      _reportSendError('uploadAndSend failed for $id ($type)', e);
      _updateLocalStatus(id, MessageDeliveryStatus.failed);
    } finally {
      videoProgress.remove(id);
    }
  }

  /// Compresse (une seule fois, même après un échec d'envoi) puis monte la
  /// vidéo, en publiant la progression de chaque étape pour la bulle.
  Future<String> _uploadVideo(String id, String localPath) async {
    var prepared = _preparedVideos[id];
    if (prepared == null) {
      videoProgress[id] = (compressing: true, value: 0);
      prepared = await VideoCompressionService.prepare(
        localPath,
        onProgress: (p) {
          if (!isClosed) videoProgress[id] = (compressing: true, value: p);
        },
      );
      _preparedVideos[id] = prepared;
    }
    videoProgress[id] = (compressing: false, value: 0);
    return _chat.uploadVideo(
      prepared.path,
      _conversationId,
      onProgress: (p) {
        if (!isClosed) videoProgress[id] = (compressing: false, value: p);
      },
    );
  }

  /// Rejoue l'envoi d'un message resté en `failed` — l'appui sur la
  /// flèche de renvoi dans la bulle (voir _MessageBubble) passe par ici.
  Future<void> retrySend(ChatMessage msg) async {
    final action = _retryActions[msg.id];
    if (action == null) return;
    _updateLocalStatus(msg.id, MessageDeliveryStatus.sending);
    await action();
  }

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;

    textController.clear();
    unawaited(_saveDraft(''));
    _stopActivity();

    final replyTo = replyingTo.value;
    replyingTo.value = null;

    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.text,
        content: text,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _finishSend(
      id: id,
      type: MessageType.text,
      content: text,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  Future<void> sendSticker(String emoji) async {
    showStickers.value = false;
    final replyTo = replyingTo.value;
    replyingTo.value = null;

    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.sticker,
        content: emoji,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _finishSend(
      id: id,
      type: MessageType.sticker,
      content: emoji,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  Future<void> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      isRecording.value = true;
      recordDuration.value = 0;
      _recordTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => recordDuration.value++,
      );
      _startActivity(ChatActivity.recording);
    } on Exception catch (_) {}
  }

  Future<void> stopRecording({bool cancel = false}) async {
    _recordTimer?.cancel();
    _stopActivity();

    String? path;
    try {
      path = await _recorder.stop();
    } on Exception catch (_) {}
    isRecording.value = false;

    if (cancel || path == null || recordDuration.value < 1) {
      _safeDeleteFile(path);
      // Enregistrement annulé : l'armement n'a rien consommé, il reste
      // en place pour le prochain envoi.
      return;
    }

    final replyTo = replyingTo.value;
    replyingTo.value = null;
    final viewOnce = _consumeViewOnceArm();

    final durationMs = recordDuration.value * 1000;
    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.voice,
        content: path,
        durationMs: durationMs,
        viewOnce: viewOnce,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _uploadAndSend(
      id: id,
      type: MessageType.voice,
      localPath: path!,
      durationMs: durationMs,
      viewOnce: viewOnce,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  /// Plafond d'envoi en une fois. Une conversation reste lisible tant que
  /// les photos ne la noient pas, et chaque photo part comme un message
  /// distinct : dix d'un coup rempliraient l'écran de l'autre.
  static const maxImagesPerSend = 6;

  /// Sélection multiple : `pickImage` ne rendait qu'une photo à la fois,
  /// obligeant à rouvrir la galerie pour chacune.
  Future<void> pickAndSendImage() async {
    final picked = await ImagePicker().pickMultiImage(
      limit: maxImagesPerSend,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked.isEmpty) return;
    // Une sélection multiple reste **un** geste : l'armement vaut pour
    // toutes les photos choisies ensemble, pas seulement la première.
    final viewOnce = _consumeViewOnceArm();
    // `limit` n'est qu'une indication sur certaines galeries Android : on
    // retronque nous-mêmes.
    for (final file in picked.take(maxImagesPerSend)) {
      // Un envoi après l'autre : chaque photo est un message, et l'ordre
      // d'affichage doit suivre l'ordre de sélection.
      await sendImageFile(file.path, viewOnce: viewOnce);
    }
  }

  Future<void> sendImageFromCamera() async {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (xfile == null) return;
    await sendImageFile(xfile.path, viewOnce: _consumeViewOnceArm());
  }

  Future<void> sendImageFile(String path, {bool viewOnce = false}) async {
    final replyTo = replyingTo.value;
    replyingTo.value = null;

    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.image,
        content: path,
        viewOnce: viewOnce,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _uploadAndSend(
      id: id,
      type: MessageType.image,
      localPath: path,
      viewOnce: viewOnce,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  /// Durée maximale d'une vidéo **filmée depuis la discussion**.
  ///
  /// `maxDuration` ne borne que la prise de vue : une vidéo choisie dans
  /// la galerie n'est pas coupée par le sélecteur, quel que soit
  /// l'appareil. C'est le plafond de poids côté service
  /// ([ChatService.maxVideoBytes]) qui tient ce rôle-là — les deux sont
  /// nécessaires, aucun ne remplace l'autre.
  static const maxVideoRecording = Duration(minutes: 2);

  /// Ouvre la galerie (ou la caméra) et envoie la vidéo choisie.
  Future<void> pickAndSendVideo(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: maxVideoRecording,
      );
    } on Exception catch (e) {
      _reportSendError('pickVideo failed', e);
      return;
    }
    if (picked == null) return;
    await sendVideoFile(picked.path, viewOnce: _consumeViewOnceArm());
  }

  /// Extrait l'image d'aperçu de la vidéo, dans le dossier temporaire.
  ///
  /// Prise à 1 s plutôt qu'à 0 : la toute première image d'une vidéo
  /// filmée au téléphone est souvent noire ou floue, le temps que
  /// l'exposition se fasse. Une vidéo plus courte retombe sur l'origine.
  ///
  /// Un échec n'empêche rien : la vidéo part sans vignette, la bulle
  /// retombe sur sa tuile.
  Future<String?> _extractVideoThumb(String path, int? durationMs) async {
    try {
      final dir = await getTemporaryDirectory();
      final thumb = await VideoThumbnail.thumbnailFile(
        video: path,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: (durationMs != null && durationMs < 1000) ? 0 : 1000,
        maxWidth: 480,
        quality: 70,
      );
      return thumb.path;
    } on Exception catch (e) {
      developer.log('Vignette de la vidéo', name: 'ChatController', error: e);
      return null;
    }
  }

  /// Durée de la vidéo, lue sur le fichier local avant l'envoi.
  ///
  /// La bulle affiche « 0:42 » dès la première image, sans attendre que
  /// quelqu'un appuie sur lecture — et l'information part avec le message,
  /// donc le destinataire l'a aussi sans télécharger la vidéo.
  ///
  /// Un échec ici n'empêche rien : la vidéo part sans sa durée, la bulle
  /// s'en passe.
  Future<int?> _probeVideoDuration(String path) async {
    final probe = VideoPlayerController.file(File(path));
    try {
      await probe.initialize();
      final value = probe.value.duration;
      return value > Duration.zero ? value.inMilliseconds : null;
    } on Exception catch (e) {
      developer.log('Durée de la vidéo', name: 'ChatController', error: e);
      return null;
    } finally {
      await probe.dispose();
    }
  }

  Future<void> sendVideoFile(String path, {bool viewOnce = false}) async {
    final durationMs = await _probeVideoDuration(path);
    // Pas de vignette pour une vidéo à vue unique : elle en montrerait le
    // contenu dans la conversation, ce qui est exactement ce qu'on cherche
    // à éviter.
    final thumbPath = viewOnce
        ? null
        : await _extractVideoThumb(path, durationMs);

    final replyTo = replyingTo.value;
    replyingTo.value = null;

    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.video,
        content: path,
        durationMs: durationMs,
        thumbUrl: thumbPath,
        viewOnce: viewOnce,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _uploadAndSend(
      id: id,
      type: MessageType.video,
      localPath: path,
      durationMs: durationMs,
      thumbPath: thumbPath,
      viewOnce: viewOnce,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  Future<void> pickAndSendDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    final replyTo = replyingTo.value;
    replyingTo.value = null;

    final id = _chat.newMessageId(_conversationId);
    _addLocalMessage(
      _pendingMessage(
        id: id,
        type: MessageType.document,
        content: file.path!,
        fileName: file.name,
        replyTo: replyTo,
      ),
    );
    _retryActions[id] = () => _uploadAndSend(
      id: id,
      type: MessageType.document,
      localPath: file.path!,
      fileName: file.name,
      replyTo: replyTo,
    );
    await _retryActions[id]!();
  }

  void toggleStickers() {
    showStickers.value = !showStickers.value;
  }

  /// Signale un message reçu, puis propose de bloquer son expéditeur.
  ///
  /// Le texte joint au signalement n'est qu'un aperçu : le serveur
  /// (`onReportCreated`) recopie lui-même le message dans la file de
  /// modération, pour que la preuve survive à une suppression et ne
  /// dépende pas de ce que l'app déclare.
  Future<void> reportMessage(ChatMessage msg) async {
    if (msg.senderUid == myUid || _conversationId.isEmpty) return;
    final choice = await showReportSheet(targetLabel: 'ce message');
    if (choice == null) return;

    final excerpt = switch (msg.type) {
      MessageType.text => msg.content,
      MessageType.sticker => msg.content,
      _ => '[${msg.type.name}] ${msg.fileName ?? ''}'.trim(),
    };
    try {
      await _moderation.report(
        ContentReport(
          targetType: ReportTargetType.message,
          targetId: msg.id,
          targetPath: 'conversations/$_conversationId/messages/${msg.id}',
          targetOwnerUid: msg.senderUid,
          reporterUid: myUid,
          reason: choice.reason,
          details: choice.details,
          excerpt: excerpt,
        ),
      );
    } catch (e) {
      Get.snackbar('Signalement impossible', '$e');
      return;
    }

    if (iBlockedPeer) {
      Get.snackbar('Signalement envoyé', 'Merci. Notre équipe va l\'examiner.');
      return;
    }
    final name = otherProfile.value?.displayName ?? 'ce contact';
    final block = await confirmAction(
      title: 'Signalement envoyé',
      message:
          'Merci. Notre équipe va l\'examiner.\n\nVoulez-vous aussi bloquer '
          '$name ? Cette personne ne pourra plus vous écrire ni vous appeler.',
      confirmLabel: 'Bloquer',
      cancelLabel: 'Plus tard',
    );
    if (!block) return;
    try {
      await _moderation.blockUser(
        myUid: myUid,
        targetUid: _otherUid,
        targetName: otherProfile.value?.displayName ?? '',
      );
    } catch (e) {
      Get.snackbar('Blocage impossible', '$e');
    }
  }

  void startAudioCall() => _startCall(CallType.audio);

  void startVideoCall() => _startCall(CallType.video);

  void _startCall(CallType type) {
    if (_otherUid.isEmpty) return;
    // Le serveur refuserait de toute façon l'appel (règles `calls`) ; on
    // l'explique plutôt que de laisser sonner dans le vide.
    if (iBlockedPeer) {
      Get.snackbar(
        'Contact bloqué',
        'Débloquez ce contact pour pouvoir l\'appeler.',
      );
      return;
    }
    if (peerBlockedMe) {
      Get.snackbar(
        'Appel impossible',
        'Vous ne pouvez pas appeler ce contact.',
      );
      return;
    }
    Get.toNamed(
      AppRoutes.call,
      arguments: {
        'incoming': false,
        'otherUid': _otherUid,
        'type': type,
        'conversationId': _conversationId,
      },
    );
  }

  /// Ouvre un message à vue unique et le consomme.
  ///
  /// Marqué ouvert **avant** que la visionneuse s'affiche : si l'app
  /// meurt pendant qu'on regarde, le message reste consommé plutôt que de
  /// se rouvrir. L'URL est rendue à l'appelant, qui l'affiche depuis la
  /// mémoire — elle ne sera plus dans la base une seconde après.
  ///
  /// Rend `null` si le message n'est pas ouvrable (déjà vu, ou c'est le
  /// nôtre) : la bulle ne devrait pas le proposer, mais deux appuis
  /// rapides passeraient tous les deux ici.
  Future<String?> openViewOnce(ChatMessage message) async {
    if (!message.canOpenViewOnce(myUid)) return null;
    final url = message.content;
    if (url.isEmpty) return null;
    try {
      await _chat.consumeViewOnce(
        conversationId: _conversationId,
        messageId: message.id,
      );
    } on Exception catch (e) {
      _reportSendError('consumeViewOnce failed for ${message.id}', e);
      return null;
    }
    return url;
  }

  /// Dit à l'expéditeur qu'on vient de capturer l'écran de son message.
  void reportScreenshot(String messageId) => unawaited(
    _chat.reportScreenshot(
      conversationId: _conversationId,
      messageId: messageId,
    ),
  );

  /// Efface le fichier d'un message à vue unique, une fois refermé.
  void releaseViewOnce(String url) => unawaited(_chat.deleteViewOnceFile(url));

  Future<void> setEphemeral(int? seconds) async {
    ephemeralSeconds.value = seconds;
    try {
      await _chat.setEphemeral(_conversationId, seconds);
    } on Exception catch (_) {}
  }

  void _safeDeleteFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException catch (_) {}
  }
}
