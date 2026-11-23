/**
 * Cloud Functions — notifications d'appel Foumbot Link.
 *
 * Le système d'appel repose sur un document Firestore (`calls/{callId}`)
 * pour la sonnerie et sur LiveKit pour la voix et l'image (calls.js). Sans push, l'appelé ne « sonne » que si son app tourne
 * déjà. Ces fonctions envoient un message FCM data-only haute priorité à la
 * création de l'appel (réveille l'appareil, même app tuée → CallKit natif via
 * `flutter_callkit_incoming`), un message `call_cancelled` quand la phase de
 * sonnerie se termine (l'appelant raccroche, réponse sur un autre appareil…),
 * et une notification « Appel manqué ».
 *
 * Les tokens FCM de chaque utilisateur vivent dans `users/{uid}/private/push`
 * ({ tokens: string[] }) — doc privé, lisible seulement par son propriétaire.
 * L'Admin SDK contourne les règles Firestore.
 */

const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");
const {getAuth} = require("firebase-admin/auth");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {marketKeywords, backfillListing} =
  require("./market_backfill");

initializeApp();
const db = getFirestore();

const RINGING = "ringing";
const ACCEPTED = "accepted";
const TOKEN_DOC = (uid) => db.doc(`users/${uid}/private/push`);

/**
 * Statuts qui terminent définitivement un appel.
 *
 * ⚠️ `accepted` n'en fait **pas** partie, et ne doit jamais y être remis :
 * le push `call_cancelled` émis ici part vers *tous* les appareils de
 * l'appelé, celui qui vient de décrocher inclus. Quand `accepted` déclenchait
 * ce push, l'appareil qui répondait recevait l'ordre de retirer sa propre UI
 * d'appel — et avec elle, sur iOS, la session audio CallKit : l'appel se
 * coupait dans la seconde suivant le décroché, sans jamais démarrer le
 * compteur de durée.
 */
const ENDED_STATUSES = ["declined", "busy", "ended", "missed"];

/** Statuts depuis lesquels un appel peut encore se terminer. */
const LIVE_STATUSES = [RINGING, ACCEPTED];

/** Codes d'erreur FCM qui signifient « ce token n'est plus valide ». */
const STALE_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

/**
 * Envoie `message` à tous les tokens FCM de `uid` et purge ceux devenus
 * invalides. `message` ne doit pas contenir `token` / `tokens`.
 */
async function sendToUser(uid, message) {
  if (!uid) return;
  const snap = await TOKEN_DOC(uid).get();
  const tokens = (snap.exists && snap.data().tokens) || [];
  if (tokens.length === 0) {
    logger.info(`aucun token pour ${uid}`);
    return;
  }

  const res = await getMessaging().sendEachForMulticast({...message, tokens});
  logger.info(`envoi à ${uid}: ${res.successCount}/${tokens.length} ok`);

  const stale = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error && STALE_TOKEN_CODES.has(r.error.code)) {
      stale.push(tokens[i]);
    }
  });
  if (stale.length > 0) {
    await TOKEN_DOC(uid).set(
        {tokens: FieldValue.arrayRemove(...stale)},
        {merge: true},
    );
    logger.info(`purge ${stale.length} token(s) périmé(s) pour ${uid}`);
  }
}

/** `users/{uid}.displayName` (fallback fourni). */
async function displayName(uid, fallback) {
  try {
    const doc = await db.doc(`users/${uid}`).get();
    return (doc.exists && doc.data().displayName) || fallback;
  } catch (_) {
    return fallback;
  }
}

/**
 * Écrit une notification dans le flux personnel `users/{uid}/notifications`
 * (lu par NotificationService côté app — `type` doit correspondre au nom de
 * l'enum Dart `AppNotificationType`, ex. "missedCall" pas "missed_call").
 */
async function writeNotification(uid, {type, title, body, data = {}, fromUid, fromName}) {
  if (!uid) return;
  await db.collection(`users/${uid}/notifications`).add({
    type,
    title,
    body,
    data,
    fromUid: fromUid || null,
    fromName: fromName || null,
    createdAt: FieldValue.serverTimestamp(),
    read: false,
  });
}

/**
 * `writeNotification` + push correspondant. FCM exige des valeurs `data`
 * en string, converties au passage.
 */
async function notifyUser(uid, {
  type, title, body, data = {}, fromUid, fromName, storedBody,
}) {
  if (!uid) return;
  // `storedBody` : ce qui reste dans la liste des notifications de l'app,
  // quand le contenu ne doit pas y survivre (message éphémère). Le push,
  // lui, s'efface de l'écran comme il est venu.
  await writeNotification(uid, {
    type, title, body: storedBody ?? body, data, fromUid, fromName,
  });

  const stringData = {type};
  for (const [k, v] of Object.entries(data)) stringData[k] = String(v);
  if (fromUid) stringData.fromUid = String(fromUid);

  // Canal Android dédié : les messages privés et le suivi des démarches
  // (importance haute, bannière) ne se mélangent pas avec l'activité
  // sociale — un « votre dossier est prêt » ne doit pas arriver en même
  // classe qu'un J'aime, et couper les J'aime ne doit pas le faire taire.
  // Les canaux sont créés côté app par LocalNotificationsService ; ceux-ci
  // ne font que router.
  const CHANNELS = {message: "messages", dossier: "demarches", moderation: "messages"};
  const channelId = CHANNELS[type] || "social";

  await sendToUser(uid, {
    notification: {title, body},
    data: stringData,
    android: {
      priority: "high",
      notification: {channelId, sound: "default"},
    },
    apns: {payload: {aps: {sound: "default"}}},
  });
}

/** Tronque un texte pour l'aperçu d'une notification (ex. message). */
function preview(text, max = 80) {
  if (!text) return "";
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

// ---------------------------------------------------------------------
// Appels : la voix et l'image passent par LiveKit, l'appel de groupe se
// gère dans calls.js.
// ---------------------------------------------------------------------
const {LIVEKIT_SECRETS} = require("./lives");
const calls = require("./calls")({db, sendToUser});
exports.joinCall = calls.joinCall;
exports.inviteToCall = calls.inviteToCall;
Object.defineProperty(exports, "_calls", {value: calls, enumerable: false});

/**
 * Nouvel appel → notifier l'appelé. Message data-only + priorité haute pour
 * réveiller un appareil endormi / une app tuée (l'isolate de fond Flutter
 * lève alors l'UI CallKit).
 */
exports.onCallCreated = onDocumentCreated("calls/{callId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const call = snap.data();
  const callId = event.params.callId;

  if (call.status !== RINGING) return;

  const callerName = await displayName(call.callerUid, "Appel entrant");

  await sendToUser(call.calleeUid, {
    data: {
      type: "incoming_call",
      callId,
      callerUid: call.callerUid || "",
      callerName,
      callType: call.type || "audio",
      conversationId: call.conversationId || "",
    },
    android: {priority: "high"},
    apns: {
      // Phase B iOS : passer à 'voip' + topic `<bundleId>.voip` une fois le
      // certificat PushKit disponible. En 'alert', iOS ne peut pas lancer une
      // app tuée ni sonner comme un appel — seulement afficher une bannière.
      headers: {"apns-push-type": "alert", "apns-priority": "10"},
      payload: {aps: {"content-available": 1, "mutable-content": 1}},
    },
  });
});

/**
 * Fin d'un appel. On ne réagit qu'au passage d'un état vivant (`ringing` ou
 * `accepted`) vers un état terminal : les autres écritures sur le
 * document laissent le statut inchangé et ne déclenchent donc rien ici.
 *
 * Le passage `ringing` → `accepted` (le décroché) n'envoie volontairement
 * aucun push : voir [ENDED_STATUSES].
 */
exports.onCallUpdated = onDocumentUpdated({
  document: "calls/{callId}",
  secrets: LIVEKIT_SECRETS,
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const callId = event.params.callId;

  // Appel de groupe : chacun ne fait que quitter l'appel ; c'est ici qu'il
  // est clos quand il ne reste plus personne à qui parler. Cette clôture
  // réécrit le document et repasse par ce déclencheur.
  if (await calls.settleGroupCall(event.data.after.ref, after)) return;

  if (before.status === after.status) return;
  if (!LIVE_STATUSES.includes(before.status)) return;
  if (!ENDED_STATUSES.includes(after.status)) return;

  // Ferme la salle LiveKit de l'appel : un téléphone qui n'aurait pas vu
  // la fin (app figée, réseau revenu trop tard) est coupé lui aussi.
  await calls.closeCallRoom(callId);

  // Appel de groupe clos alors que des invités sonnaient encore.
  if (after.group) {
    await Promise.all(calls.uidsIn(after, ["ringing"]).map((uid) =>
      sendToUser(uid, {
        data: {type: "call_cancelled", callId},
        android: {priority: "high"},
        apns: {
          headers: {"apns-push-type": "background", "apns-priority": "5"},
          payload: {aps: {"content-available": 1}},
        },
      })));
  }

  // Retire l'UI d'appel native restée affichée chez l'appelé : l'appelant a
  // raccroché (pendant la sonnerie ou en pleine conversation), ou l'appel a
  // été refusé. L'appareil qui a lui-même mis fin à l'appel ignore ce push
  // (PushService filtre sur son appel actif).
  await sendToUser(after.calleeUid, {
    data: {type: "call_cancelled", callId},
    android: {priority: "high"},
    apns: {
      headers: {"apns-push-type": "background", "apns-priority": "5"},
      payload: {aps: {"content-available": 1}},
    },
  });

  // Un appel décroché puis terminé n'est pas un appel manqué — la condition
  // sur `before.status` évite une notification « Appel manqué » à la fin
  // d'une vraie conversation.
  if (after.status === "missed" && before.status === RINGING) {
    const callerName = await displayName(after.callerUid, "Quelqu'un");

    // Historisé dans le flux de notifications (écran dédié) séparément du
    // push ci-dessous, qui garde son propre `data.type` ("missed_call",
    // avec underscore) attendu par PushService._onNotificationTap.
    await writeNotification(after.calleeUid, {
      type: "missedCall",
      title: "Appel manqué",
      body: `${callerName} a essayé de vous appeler`,
      data: {
        callId,
        callerUid: after.callerUid || "",
        conversationId: after.conversationId || "",
      },
      fromUid: after.callerUid,
      fromName: callerName,
    });

    await sendToUser(after.calleeUid, {
      notification: {
        title: "Appel manqué",
        body: `${callerName} a essayé de vous appeler`,
      },
      data: {
        type: "missed_call",
        callId,
        callerUid: after.callerUid || "",
        conversationId: after.conversationId || "",
      },
      android: {
        priority: "high",
        notification: {channelId: "missed_calls", priority: "high"},
      },
      apns: {payload: {aps: {sound: "default"}}},
    });
  }
});

// ---------------------------------------------------------------------
// Messagerie — notifie le destinataire à chaque nouveau message.
// ---------------------------------------------------------------------

const MESSAGE_PREVIEWS = {
  voice: "🎤 Message vocal",
  image: "📷 Photo",
  video: "🎥 Vidéo",
  sticker: null, // le contenu est déjà l'emoji lui-même
};

/**
 * Badge non lu du destinataire, tenu par le serveur seul.
 *
 * Il était écrit par le téléphone de l'expéditeur, que les règles
 * laissaient donc modifier le compteur de l'autre : une app modifiée
 * pouvait le gonfler à volonté, et un échec de cette écriture laissait
 * le badge faux.
 *
 * Lu et écrit dans une transaction avec le message : si le destinataire,
 * discussion ouverte, l'a déjà marqué lu (`readAt`) avant que ce trigger
 * ne passe, il n'est pas compté — sinon un « 1 » resterait affiché sur
 * un message lu. L'app pose `readAt` avant de remettre le badge à zéro
 * (ChatService.markAsRead), ce qui ferme l'autre ordre possible.
 *
 * Le premier message peut précéder le document de conversation : il est
 * alors créé ici, pour que la discussion apparaisse chez le destinataire.
 *
 * @param {string} conversationId Id `uidA_uidB`.
 * @param {string} messageId Message créé.
 * @param {string} senderUid Expéditeur.
 * @param {string} recipient Destinataire.
 * @return {Promise<void>} Résolue une fois le compteur à jour.
 */
async function countUnread(conversationId, messageId, senderUid, recipient) {
  const convRef = db.doc(`conversations/${conversationId}`);
  const msgRef = convRef.collection("messages").doc(messageId);
  try {
    await db.runTransaction(async (tx) => {
      const [conv, message] = await Promise.all([tx.get(convRef),
        tx.get(msgRef)]);
      if (!message.exists || message.get("readAt")) return;
      if (!conv.exists) {
        tx.set(convRef, {
          participants: [senderUid, recipient],
          createdAt: FieldValue.serverTimestamp(),
          lastMessageAt: FieldValue.serverTimestamp(),
          unreadCounts: {[recipient]: 1},
        });
        return;
      }
      tx.update(convRef, {
        [`unreadCounts.${recipient}`]: FieldValue.increment(1),
      });
    });
  } catch (err) {
    // Le badge ne doit jamais empêcher la notification de partir.
    logger.error("Badge non lu", {conversationId, messageId, err});
  }
}

/** Ce qu'on montre d'un message éphémère là où il serait conservé. */
const EPHEMERAL_PREVIEW = "⏱ Message éphémère";

/** Messages expirés supprimés par passage, au plus. */
const MESSAGE_PURGE_BATCH = 400;

/**
 * Chemin Storage d'une URL de téléchargement Firebase
 * (`…/v0/b/{bucket}/o/{chemin encodé}?alt=media&token=…`), ou `null`.
 *
 * @param {string} url URL lue dans le message.
 * @return {?string} Chemin dans le bucket.
 */
function storagePathFromUrl(url) {
  if (typeof url !== "string") return null;
  const match = /\/o\/([^?#]+)/.exec(url);
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch (err) {
    return null;
  }
}

/**
 * Ramasse les messages éphémères arrivés à échéance : le document et ses
 * fichiers (média, vignette).
 *
 * L'app les cachait déjà, mais rien ne les effaçait : le texte restait
 * dans Firestore et les fichiers dans Storage, indéfiniment — lisibles par
 * qui interroge la base directement. Un message « éphémère » doit l'être
 * pour de vrai.
 *
 * Deux garde-fous sur les fichiers :
 * - seuls ceux rangés sous `chat/{cette conversation}/` sont supprimés : un
 *   message transféré pointe vers le fichier d'une autre conversation, qu'il
 *   ne faut pas casser ;
 * - un message signalé, dont le dossier de modération est encore ouvert,
 *   garde son fichier : c'est la preuve que l'administrateur doit voir.
 *
 * @return {Promise<number>} Nombre de messages supprimés.
 */
async function purgeExpiredMessagesOnce() {
  const snap = await db.collectionGroup("messages")
      .where("expiresAt", "<=", new Date())
      .limit(MESSAGE_PURGE_BATCH)
      .get();
  if (snap.empty) return 0;

  const reviews = await db.getAll(...snap.docs.map((d) =>
    db.doc(`moderationQueue/message_${d.id}`)));
  const underReview = new Set(reviews
      .filter((r) => r.exists && r.get("status") === "open")
      .map((r) => r.id.slice("message_".length)));

  const bucket = getStorage().bucket();
  const batch = db.batch();
  for (const doc of snap.docs) {
    const conversationId = doc.ref.parent.parent.id;
    if (!underReview.has(doc.id)) {
      for (const url of [doc.get("content"), doc.get("thumbUrl")]) {
        const path = storagePathFromUrl(url);
        if (!path || !path.startsWith(`chat/${conversationId}/`)) continue;
        try {
          await bucket.file(path).delete({ignoreNotFound: true});
        } catch (err) {
          logger.error(`Fichier du message éphémère ${doc.id}`, err);
        }
      }
    }
    batch.delete(doc.ref);
  }
  await batch.commit();
  return snap.size;
}

/**
 * Toutes les 10 minutes : l'app fait disparaître le message à la seconde
 * près, ce passage efface ce qui reste côté serveur. Plusieurs lots par
 * passage si un retard s'est accumulé.
 */
exports.purgeExpiredMessages = onSchedule(
    {schedule: "every 10 minutes", timeZone: "Africa/Douala"},
    async () => {
      let total = 0;
      for (let round = 0; round < 5; round++) {
        const purged = await purgeExpiredMessagesOnce();
        total += purged;
        if (purged < MESSAGE_PURGE_BATCH) break;
      }
      logger.info(`Messages éphémères : ${total} supprimé(s).`);
    },
);

exports.onMessageCreated = onDocumentCreated(
    "conversations/{conversationId}/messages/{messageId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data();
      const {conversationId} = event.params;

      // Les participants se lisent dans l'id (`uidA_uidB`, uids triés,
      // jamais de `_` dans un uid) : le premier message d'une nouvelle
      // conversation peut arriver avant le document de conversation, et
      // repartait alors sans notification.
      const participants = conversationId.split("_");
      if (participants.length !== 2 ||
          !participants.includes(msg.senderUid)) {
        return;
      }
      const recipient = participants.find((p) => p !== msg.senderUid);
      if (!recipient) return;

      await countUnread(conversationId, event.params.messageId,
          msg.senderUid, recipient);

      const senderName = await displayName(msg.senderUid, "Quelqu'un");
      // Un message à vue unique ne livre pas son type au-delà du
      // nécessaire, et surtout pas son contenu : la notification se lit
      // sur un écran verrouillé, sans que personne l'ait ouvert.
      const viewOnceNouns = {
        voice: "Message vocal",
        video: "Vidéo",
        image: "Photo",
      };
      const body = msg.viewOnce && viewOnceNouns[msg.type] ?
        `👁 ${viewOnceNouns[msg.type]} · vue unique` :
        msg.type === "document" ?
          `📎 ${msg.fileName || "Document"}` :
          (MESSAGE_PREVIEWS[msg.type] || preview(msg.content));

      await notifyUser(recipient, {
        type: "message",
        title: senderName,
        body,
        storedBody: msg.expiresAt ? EPHEMERAL_PREVIEW : undefined,
        data: {conversationId, senderUid: msg.senderUid || ""},
        fromUid: msg.senderUid,
        fromName: senderName,
      });
    },
);

// ---------------------------------------------------------------------
// Publications — like, commentaire/réponse, nouvelle publication (aux
// abonnés de l'auteur).
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// Rapprochement du répertoire téléphonique
// ---------------------------------------------------------------------

/**
 * Nombre d'empreintes acceptées par appel.
 *
 * Un répertoire ordinaire compte quelques centaines de numéros. Le
 * plafond n'est pas là pour eux : il est là pour qu'on ne puisse pas se
 * servir de cette fonction pour balayer l'espace des numéros
 * camerounais. Un répertoire plus gros est découpé côté app.
 */
const MAX_CONTACT_HASHES = 500;

/**
 * Plafonds journaliers par compte.
 *
 * Le plafond par appel ralentit un balayage, il ne l'interdit pas :
 * rien n'empêchait d'appeler la fonction en boucle, 500 empreintes à la
 * fois, pour tester des numéros générés. Ces deux bornes le rendent sans
 * intérêt — 5 000 numéros testables par jour, là où un seul préfixe
 * d'opérateur en compte un million.
 *
 * Calibrés large pour les usages réels : un répertoire bien fourni
 * compte quelques centaines de numéros, soit un ou deux appels, et on
 * peut relancer la recherche plusieurs fois par jour sans jamais s'en
 * approcher.
 */
const MAX_CONTACT_HASHES_PER_DAY = 5000;
const MAX_CONTACT_CALLS_PER_DAY = 20;

/**
 * Jour courant à Foumbot, au format `AAAA-MM-JJ`.
 *
 * Le quota doit se remettre à zéro à minuit **ici**, pas à Londres :
 * sinon il repartirait à neuf en pleine journée. Le Cameroun est à
 * UTC+1 toute l'année, sans heure d'été — un simple décalage suffit.
 */
function douaLaDayKey(now = new Date()) {
  const shifted = new Date(now.getTime() + 60 * 60 * 1000);
  return shifted.toISOString().slice(0, 10);
}

/**
 * Décompte l'appel, ou refuse s'il dépasse le quota du jour.
 *
 * Le compteur vit dans `contactMatchQuota/{uid}`, une collection
 * qu'aucun client ne peut ni lire ni écrire : la remettre à zéro depuis
 * l'app viderait la protection de son sens. La transaction évite que
 * plusieurs appels simultanés passent chacun sous le plafond.
 */
async function consumeContactQuota(uid, hashCount) {
  const ref = db.doc(`contactMatchQuota/${uid}`);
  const today = douaLaDayKey();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    // Un nouveau jour repart de zéro, sans qu'aucun ménage n'ait à
    // tourner : le jour stocké fait foi.
    const sameDay = data.day === today;
    const calls = sameDay ? (data.calls || 0) : 0;
    const hashes = sameDay ? (data.hashes || 0) : 0;

    if (calls + 1 > MAX_CONTACT_CALLS_PER_DAY ||
        hashes + hashCount > MAX_CONTACT_HASHES_PER_DAY) {
      throw new HttpsError(
          "resource-exhausted",
          "Vous avez atteint la limite de recherches pour aujourd'hui. " +
          "Réessayez demain.",
      );
    }

    tx.set(ref, {
      day: today,
      calls: calls + 1,
      hashes: hashes + hashCount,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Retrouve, parmi les empreintes envoyées, celles qui correspondent à un
 * compte de l'application.
 *
 * L'app n'envoie **jamais** de numéros : elle envoie des empreintes
 * SHA-256, et ne reçoit en retour que les comptes trouvés — jamais
 * l'information « ce numéro-là n'existe pas », qui suffirait à
 * transformer la fonction en annuaire inversé.
 *
 * La collection `phoneDirectory` n'est lisible par aucun client (voir
 * firestore.rules) : c'est ici, avec les droits de l'Admin SDK, que la
 * comparaison a lieu.
 */
exports.matchContacts = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError(
        "unauthenticated",
        "Connectez-vous pour retrouver vos contacts.",
    );
  }

  const hashes = Array.isArray(request.data && request.data.hashes) ?
    request.data.hashes :
    [];
  if (!hashes.length) return {matches: []};
  if (hashes.length > MAX_CONTACT_HASHES) {
    throw new HttpsError(
        "invalid-argument",
        `Envoyez au plus ${MAX_CONTACT_HASHES} empreintes par appel.`,
    );
  }

  // Une empreinte SHA-256 fait 64 caractères hexadécimaux : tout le
  // reste est écarté sans même être cherché.
  const valid = hashes
      .filter((h) => typeof h === "string" && /^[0-9a-f]{64}$/.test(h));
  if (!valid.length) return {matches: []};

  // Décompté avant toute lecture de l'annuaire : un appel refusé ne doit
  // rien apprendre, pas même que l'annuaire a été consulté.
  await consumeContactQuota(uid, valid.length);

  // `getAll` accepte une centaine de références par appel ; on découpe.
  const refs = valid.map((h) => db.doc(`phoneDirectory/${h}`));
  const found = new Set();
  for (let i = 0; i < refs.length; i += 100) {
    const snaps = await db.getAll(...refs.slice(i, i + 100));
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const owner = snap.data().uid;
      // On ne se propose pas à soi-même.
      if (owner && owner !== uid) found.add(owner);
    }
  }
  if (!found.size) return {matches: []};

  // Les comptes déjà suivis n'ont rien à faire dans une liste de
  // suggestions : la personne les a déjà trouvés.
  const following = new Set();
  const followingSnap = await db.collection(`users/${uid}/following`).get();
  followingSnap.forEach((doc) => following.add(doc.id));

  const matches = [];
  for (const owner of found) {
    if (following.has(owner)) continue;
    const userSnap = await db.doc(`users/${owner}`).get();
    if (!userSnap.exists) continue;
    const data = userSnap.data();
    matches.push({
      uid: owner,
      displayName: data.displayName || "Habitant",
      photoUrl: data.photoUrl || null,
      accountType: data.accountType || "personal",
      verified: data.verified === true,
    });
  }

  logger.info(
      `matchContacts : ${valid.length} empreinte(s) pour ${uid}, ` +
      `${matches.length} suggestion(s).`,
  );
  return {matches};
});

// ---------------------------------------------------------------------
// Suivi des dossiers déposés au guichet
// ---------------------------------------------------------------------

/**
 * Ce que la personne lit sur son téléphone, pour chaque état.
 *
 * Formulé du point de vue de celui qui attend, pas de celui qui traite :
 * ce qui compte est « puis-je venir le chercher ? », pas le vocabulaire
 * interne du service.
 */
const DOSSIER_MESSAGES = {
  receptionne: {
    title: "Dossier réceptionné",
    body: (d) => `${d.structureName} a bien reçu votre dossier.`,
  },
  enCours: {
    title: "Dossier en cours de traitement",
    body: (d) => `${d.structureName} travaille sur votre dossier.`,
  },
  complementRequis: {
    title: "Une pièce manque à votre dossier",
    body: (d) =>
      `${d.structureName} attend une pièce. Ouvrez l'application pour ` +
      `savoir laquelle.`,
  },
  termine: {
    title: "Votre dossier est prêt",
    body: (d) => `Vous pouvez le retirer auprès de ${d.structureName}.`,
  },
  retire: {
    title: "Dossier retiré",
    body: () => "Démarche terminée. Bonne journée !",
  },
  rejete: {
    title: "Dossier non abouti",
    body: (d) =>
      `${d.structureName} a clos votre dossier. Le motif est dans ` +
      `l'application.`,
  },
};

/**
 * Prévient le propriétaire à chaque changement d'état de son dossier.
 *
 * C'est le cœur de la fonctionnalité : sans cette notification, il
 * faudrait ouvrir l'app pour savoir, donc y penser — et le service
 * continuerait de recevoir des visites « juste pour vérifier ».
 *
 * Déclenché sur création **et** sur mise à jour : la réception au guichet
 * est déjà une nouvelle qui vaut d'être annoncée.
 */
exports.onDossierWritten = onDocumentWritten(
    "dossiers/{dossierId}",
    async (event) => {
      const after = event.data && event.data.after;
      if (!after || !after.exists) return;
      const dossier = after.data();

      const before = event.data.before;
      const previousStatus = before && before.exists ?
        before.data().status :
        null;

      // Seul un changement d'état intéresse : une correction de référence
      // ne doit pas faire sonner le téléphone de quelqu'un.
      if (previousStatus === dossier.status) return;

      const message = DOSSIER_MESSAGES[dossier.status];
      if (!message) {
        logger.warn(`État de dossier inconnu : ${dossier.status}`);
        return;
      }

      // Ni l'intitulé de la démarche, ni le motif saisi par l'agent ne
      // sortent d'ici. Une notification s'affiche sur un écran verrouillé,
      // au vu de qui se trouve à côté : « Test VIH : votre résultat est
      // prêt » n'a rien à y faire. L'app dit **où** en est le dossier et
      // **où** aller ; ce qu'il contient se lit dans l'app, après
      // déverrouillage.
      await notifyUser(dossier.ownerUid, {
        type: "dossier",
        title: message.title,
        body: message.body(dossier),
        data: {
          dossierId: event.params.dossierId,
          status: dossier.status,
        },
        fromUid: dossier.structureUid,
        fromName: dossier.structureName,
      });

      logger.info(
          `Dossier ${event.params.dossierId} → ${dossier.status}, ` +
          `${dossier.ownerUid} notifié`,
      );
    },
);

exports.onPostCreated = onDocumentCreated("posts/{postId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const post = snap.data();
  const {postId} = event.params;
  if (!post.authorUid) return;

  // Plafonné pour borner le coût d'un fan-out vers un compte à forte
  // audience — au-delà, seuls les 300 abonnés les plus récents sont
  // notifiés. Suffisant à l'échelle de ce projet (commune).
  const followers = await db
      .collection(`users/${post.authorUid}/followers`)
      .limit(300)
      .get();
  if (followers.empty) return;

  // Le titre d'une publication est facultatif côté app, et le message
  // aussi quand elle ne porte que des photos : sans repli, la
  // notification arrivait avec un corps vide.
  const imageCount = Array.isArray(post.imageUrls) ? post.imageUrls.length : 0;
  const photoLabel = imageCount > 1 ?
    `${imageCount} photos` :
    "Une photo";

  await Promise.all(followers.docs.map((doc) => notifyUser(doc.id, {
    type: "post",
    title: post.authorName || "Nouvelle publication",
    body: preview(post.title || post.body || (imageCount ? photoLabel : "")),
    data: {postId},
    fromUid: post.authorUid,
    fromName: post.authorName,
  })));
});

/**
 * Un « j'aime » est désormais un document `posts/{postId}/likes/{likerUid}`
 * et non plus une entrée du tableau `likedBy` du post : on écoute donc sa
 * création plutôt qu'une mise à jour du post.
 */
exports.onPostLiked = onDocumentCreated(
    "posts/{postId}/likes/{likerUid}",
    async (event) => {
      const {postId, likerUid} = event.params;

      const postSnap = await db.doc(`posts/${postId}`).get();
      const authorUid = postSnap.exists ? postSnap.data().authorUid : null;
      if (!authorUid || authorUid === likerUid) return;

      // Un « j'aime » retiré puis reposé recrée ce document : sans ce
      // marqueur, l'auteur recevrait une notification à chaque fois et
      // elles s'accumuleraient. `create()` échoue si le marqueur existe
      // déjà — on ne notifie donc qu'une fois par (post, personne).
      try {
        await db.doc(`posts/${postId}/likeNotified/${likerUid}`).create({
          notifiedAt: FieldValue.serverTimestamp(),
        });
      } catch {
        return;
      }

      const likerName = await displayName(likerUid, "Quelqu'un");
      await notifyUser(authorUid, {
        type: "like",
        title: likerName,
        body: "a aimé votre publication",
        data: {postId},
        fromUid: likerUid,
        fromName: likerName,
      });
    });

exports.onCommentCreated = onDocumentCreated(
    "posts/{postId}/comments/{commentId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const comment = snap.data();
      const {postId, commentId} = event.params;
      const commentAuthorName = comment.authorName || "Quelqu'un";

      // Réponse à un commentaire : on notifie l'auteur du commentaire
      // parent plutôt que l'auteur du post (plus pertinent).
      if (comment.parentCommentId) {
        const parentDoc = await db
            .doc(`posts/${postId}/comments/${comment.parentCommentId}`)
            .get();
        const parentAuthorUid = parentDoc.exists ?
          parentDoc.data().authorUid :
          null;
        if (parentAuthorUid && parentAuthorUid !== comment.authorUid) {
          await notifyUser(parentAuthorUid, {
            type: "comment",
            title: commentAuthorName,
            body: "a répondu à votre commentaire",
            data: {postId, commentId},
            fromUid: comment.authorUid,
            fromName: commentAuthorName,
          });
        }
        return;
      }

      const postDoc = await db.doc(`posts/${postId}`).get();
      if (!postDoc.exists) return;
      const postAuthorUid = postDoc.data().authorUid;
      if (!postAuthorUid || postAuthorUid === comment.authorUid) return;

      await notifyUser(postAuthorUid, {
        type: "comment",
        title: commentAuthorName,
        body: "a commenté votre publication",
        data: {postId, commentId},
        fromUid: comment.authorUid,
        fromName: commentAuthorName,
      });
    },
);

// ---------------------------------------------------------------------
// Nouvel abonné.
// ---------------------------------------------------------------------

exports.onFollowerAdded = onDocumentCreated(
    "users/{uid}/followers/{followerUid}",
    async (event) => {
      const {uid, followerUid} = event.params;
      const followerName = await displayName(followerUid, "Quelqu'un");
      await notifyUser(uid, {
        type: "follow",
        title: followerName,
        body: "a commencé à vous suivre",
        data: {followerUid},
        fromUid: followerUid,
        fromName: followerName,
      });
    },
);

// ---------------------------------------------------------------------
// Blocage — miroir et rupture des abonnements.
//
// `users/{uid}/blocked/{cible}` est écrit par le client et n'est lisible
// que par celui qui bloque. Ce trigger en tient le miroir
// `users/{cible}/blockedBy/{uid}`, que seule la personne bloquée peut lire :
// son app s'en sert pour masquer à son tour les contenus de celui qui
// l'a bloquée. Les règles Firestore, elles, lisent directement `blocked`.
//
// Bloquer rompt aussi les abonnements dans les deux sens : les règles
// interdisent d'en créer de nouveaux, mais n'effacent pas ceux qui
// existent, et le client n'a pas le droit de toucher à l'abonnement de
// l'autre.
// ---------------------------------------------------------------------

/**
 * Supprime l'abonnement de `followerUid` à `targetUid`, s'il existe, avec
 * ses deux compteurs.
 *
 * @param {string} followerUid Compte abonné.
 * @param {string} targetUid Compte suivi.
 * @return {Promise<boolean>} `true` si un abonnement a été rompu.
 */
async function removeFollowEdge(followerUid, targetUid) {
  const followingRef = db.doc(`users/${followerUid}/following/${targetUid}`);
  const followerRef = db.doc(`users/${targetUid}/followers/${followerUid}`);
  return db.runTransaction(async (tx) => {
    const [following, follower, followerUser, targetUser] = await Promise.all([
      tx.get(followingRef),
      tx.get(followerRef),
      tx.get(db.doc(`users/${followerUid}`)),
      tx.get(db.doc(`users/${targetUid}`)),
    ]);
    if (!following.exists && !follower.exists) return false;
    if (following.exists) {
      tx.delete(followingRef);
      if (followerUser.exists) {
        tx.update(followerUser.ref, {followingCount: FieldValue.increment(-1)});
      }
    }
    if (follower.exists) {
      tx.delete(followerRef);
      if (targetUser.exists) {
        tx.update(targetUser.ref, {followersCount: FieldValue.increment(-1)});
      }
    }
    return true;
  });
}

exports.onBlockWritten = onDocumentWritten(
    "users/{uid}/blocked/{blockedUid}",
    async (event) => {
      const {uid, blockedUid} = event.params;
      if (uid === blockedUid) return;
      const mirror = db.doc(`users/${blockedUid}/blockedBy/${uid}`);

      if (!event.data.after.exists) {
        await mirror.delete();
        return;
      }
      if (event.data.before.exists) return; // simple réécriture

      await mirror.set({createdAt: FieldValue.serverTimestamp()});
      await removeFollowEdge(uid, blockedUid);
      await removeFollowEdge(blockedUid, uid);
    },
);

// ---------------------------------------------------------------------
// Suppression d'une publication — purge en cascade.
//
// Firestore ne supprime pas les sous-collections avec leur document
// parent : sans cette fonction, les commentaires d'un post effacé
// resteraient en base indéfiniment (facturés, et ressuscités si un
// document de même id était recréé). Les images vivent dans
// `posts/{postId}/` sur Storage et ne sont pas davantage nettoyées
// automatiquement.
//
// Le client ne peut pas faire ce ménage lui-même : les règles ne
// l'autorisent à supprimer que ses propres commentaires, et l'auteur du
// post n'a aucun droit sur ceux des autres. L'Admin SDK, lui, ignore les
// règles. Le client efface tout de même ses images avant de supprimer le
// document (les règles Storage s'appuient dessus) ; le `deleteFiles`
// ci-dessous est le filet de sécurité.
// ---------------------------------------------------------------------

/**
 * Supprime les likes d'un post et leur miroir personnel, par lots.
 *
 * @param {string} postId Publication dont les likes doivent disparaître.
 */
async function purgeLikes(postId) {
  const likesRef = db.collection(`posts/${postId}/likes`);
  for (;;) {
    const snap = await likesRef.limit(400).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      batch.delete(db.doc(`users/${doc.id}/likes/${postId}`));
    }
    await batch.commit();
    if (snap.size < 400) return;
  }
}

exports.onPostDeleted = onDocumentDeleted("posts/{postId}", async (event) => {
  const {postId} = event.params;

  try {
    await db.recursiveDelete(db.collection(`posts/${postId}/comments`));
  } catch (err) {
    logger.error(`Purge des commentaires de ${postId} échouée`, err);
  }

  // Les likes et leurs marqueurs de notification vivent en
  // sous-collections : la suppression du post ne les emporte pas. Chaque
  // like a en plus son miroir chez la personne qui l'a posé
  // (`users/{uid}/likes/{postId}`) — laissé en place, il encombrerait
  // indéfiniment sa liste avec un post qui n'existe plus.
  try {
    await purgeLikes(postId);
  } catch (err) {
    logger.error(`Purge des likes de ${postId} échouée`, err);
  }

  try {
    await db.recursiveDelete(db.collection(`posts/${postId}/likeNotified`));
  } catch (err) {
    logger.error(`Purge des marqueurs de like de ${postId} échouée`, err);
  }

  // Deux emplacements : `posts/{authorUid}/{postId}/` depuis que les
  // règles Storage lisent le propriétaire dans le chemin, et l'ancien
  // `posts/{postId}/` où vivent les photos publiées avant ce changement.
  const postAuthorUid = event.data && event.data.data() ?
    event.data.data().authorUid : null;
  const postPrefixes = [`posts/${postId}/`];
  if (postAuthorUid) postPrefixes.push(`posts/${postAuthorUid}/${postId}/`);
  for (const prefix of postPrefixes) {
    try {
      await getStorage().bucket().deleteFiles({prefix});
    } catch (err) {
      logger.error(`Purge des images de ${postId} (${prefix}) échouée`, err);
    }
  }

  // Les signalements sont conservés : ils documentent pourquoi un contenu
  // a disparu, y compris quand c'est l'auteur qui l'a retiré de lui-même.
  logger.info(`Publication ${postId} purgée (commentaires + images)`);
});

// ---------------------------------------------------------------------
// Modération — signalements.
//
// Un document `reports/{type}_{cible}_{signaleur}` par signalement : l'id
// déterministe empêche un même utilisateur de gonfler le compteur en
// signalant plusieurs fois le même contenu.
//
// Chaque signalement alimente aussi la file de modération
// `moderationQueue/{type}_{cible}` — un dossier par contenu ou profil
// visé, que seule l'équipe (Admin SDK, console) lit. Le dossier garde :
//  - une copie du contenu faite **par le serveur** au premier
//    signalement : la preuve survit à une suppression par son auteur
//    (message « supprimé pour tout le monde », statut expiré…) et ne
//    dépend pas de ce que l'app du signaleur a déclaré ;
//  - le nombre de signalements et leur répartition par motif ;
//  - une priorité, pour traiter d'abord ce qui presse.
//
// Masquage automatique au-delà du seuil pour les contenus publics
// (publications, commentaires, annonces, statuts) : c'est ce qui assure le
// retrait rapide sans attendre un humain. Un message privé n'est pas
// masqué — le signaleur peut bloquer —, un profil non plus : suspendre un
// compte relève d'une décision humaine.
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// Lives (voir lives.js).
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
// Certification de compte (voir certification.js) : conditions lues dans
// `config/certification`.
// ---------------------------------------------------------------------
const certification = require("./certification")({db, notifyUser});
exports.certificationStatus = certification.certificationStatus;
exports.requestCertification = certification.requestCertification;
exports.onCertificationDecided = certification.onCertificationDecided;

const lives = require("./lives")({db, notifyUser});
exports.startLive = lives.startLive;
exports.joinLive = lives.joinLive;
exports.endLive = lives.endLive;
exports.expelFromLive = lives.expelFromLive;
exports.onLiveViewerWritten = lives.onLiveViewerWritten;
exports.cleanupLives = lives.cleanupLives;
exports.onLiveSessionCreated = lives.onLiveSessionCreated;
// Pour les tests.
// Accès des tests aux rouages des lives. Non énumérable : Firebase parcourt
// les objets exportés et y aurait redécouvert startLive, joinLive… sous des
// noms invalides (« _lives-startLive »).
Object.defineProperty(exports, "_lives", {value: lives, enumerable: false});

/** Nombre de signalements distincts au-delà duquel un contenu est masqué. */
const REPORT_HIDE_THRESHOLD = 5;

/** Signalements distincts d'un profil qui le font passer en priorité. */
const USER_REPORT_PRIORITY_THRESHOLD = 3;

/** Motifs traités en priorité dès le premier signalement. */
const URGENT_REASONS = new Set(["nuditeSexuel", "violence"]);

/** Types de contenus masquables automatiquement. */
const HIDEABLE_TYPES = new Set(["post", "comment", "marketItem", "status"]);

/**
 * Auteur d'un contenu, lu dans le document lui-même plutôt que dans ce
 * qu'a déclaré le signaleur.
 *
 * @param {string} targetType Type de contenu.
 * @param {string} targetPath Chemin du document.
 * @param {object|undefined} data Données du document, s'il existe.
 * @return {string|null} Uid de l'auteur, ou null s'il est inconnu.
 */
function contentOwner(targetType, targetPath, data) {
  if (targetType === "user") return targetPath.split("/")[1] || null;
  if (!data) return null;
  return data.authorUid || data.senderUid || data.sellerUid ||
    data.hostUid || null;
}

exports.onReportCreated = onDocumentCreated({
  document: "reports/{reportId}",
  // Couper un live signalé ferme aussi sa salle LiveKit.
  secrets: lives.LIVEKIT_SECRETS,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const report = snap.data();
  const {targetType, targetPath, reason} = report;
  if (!targetPath || !targetType) return;

  logger.warn("Signalement reçu", {targetPath, reason, reporterUid: report.reporterUid});

  const targetRef = db.doc(targetPath);
  const queueRef = db.doc(`moderationQueue/${targetType}_${targetRef.id}`);

  let escalated = null;
  try {
    escalated = await db.runTransaction(async (tx) => {
      const [target, queue] = await Promise.all([
        tx.get(targetRef),
        tx.get(queueRef),
      ]);
      const data = target.exists ? target.data() : undefined;
      const count = (queue.exists ? queue.get("reportsCount") || 0 : 0) + 1;

      let priority = "normal";
      if (URGENT_REASONS.has(reason)) priority = "high";
      if (targetType === "user" && count >= USER_REPORT_PRIORITY_THRESHOLD) {
        priority = "high";
      }
      if (count >= REPORT_HIDE_THRESHOLD) priority = "high";
      if (queue.exists && queue.get("priority") === "high") priority = "high";

      const entry = {
        targetType,
        targetPath,
        targetId: targetRef.id,
        targetOwnerUid: contentOwner(targetType, targetPath, data) ||
          report.targetOwnerUid || null,
        reportsCount: count,
        // Objet imbriqué : avec `set(…, {merge})`, une clé pointée serait
        // prise pour un nom de champ littéral.
        reasons: {[reason]: FieldValue.increment(1)},
        lastReportAt: FieldValue.serverTimestamp(),
        lastReportId: snap.id,
        priority,
        // Un nouveau signalement rouvre un dossier déjà tranché.
        status: "open",
      };
      if (!queue.exists) {
        entry.firstReportAt = FieldValue.serverTimestamp();
        // La preuve : copie du contenu tel qu'il est au premier
        // signalement. Absent si le contenu avait déjà disparu.
        entry.snapshot = data || null;
        entry.snapshotTakenAt = FieldValue.serverTimestamp();
        entry.excerpt = report.excerpt || "";
      }
      tx.set(queueRef, entry, {merge: true});

      if (HIDEABLE_TYPES.has(targetType) && target.exists) {
        const update = {reportsCount: FieldValue.increment(1)};
        if (count >= REPORT_HIDE_THRESHOLD) update.hidden = true;
        tx.update(targetRef, update);
      }

      // Un dossier qui *devient* prioritaire (ou qui est rouvert alors
      // qu'il l'était) alerte l'équipe — pas à chaque signalement suivant.
      const wasUrgentAndOpen = queue.exists &&
        queue.get("priority") === "high" && queue.get("status") === "open";
      return {
        count,
        escalate: priority === "high" && !wasUrgentAndOpen,
      };
    });
  } catch (err) {
    logger.error(`Traitement du signalement échoué pour ${targetPath}`, err);
    return;
  }

  // Un live ne se masque pas : au seuil, il est coupé. L'équipe tranche
  // ensuite sur le dossier (suspension de l'hôte, ou rien).
  if (targetType === "live" &&
      escalated.count >= lives.LIVE_REPORT_END_THRESHOLD) {
    try {
      await lives.endLiveInternal(targetRef.id, {
        by: "moderation", reason: "reports",
      });
    } catch (err) {
      logger.error(`Coupure du live ${targetRef.id} échouée`, err);
    }
  }

  if (escalated.escalate) {
    await notifyAdmins({
      entryId: queueRef.id,
      targetType,
      reason,
      count: escalated.count,
    });
  }
});

/** Libellés lus dans la notification envoyée aux administrateurs. */
const REPORT_TYPE_LABELS = {
  post: "Publication",
  comment: "Commentaire",
  user: "Profil",
  marketItem: "Annonce",
  message: "Message privé",
  status: "Statut",
  live: "Live",
};
const REPORT_REASON_LABELS = {
  spam: "spam",
  harcelement: "harcèlement",
  haine: "discours haineux",
  violence: "violence ou menaces",
  nuditeSexuel: "nudité ou contenu sexuel",
  fausseInformation: "fausse information",
  arnaque: "arnaque",
  autre: "autre motif",
};

/**
 * Prévient chaque administrateur (`admins/{uid}`) qu'un dossier de
 * modération demande son attention. Ne bloque jamais le traitement du
 * signalement : une notification ratée se rattrape dans l'écran de
 * modération.
 *
 * @param {object} p Dossier concerné.
 * @param {string} p.entryId Id dans `moderationQueue`.
 * @param {string} p.targetType Type de contenu.
 * @param {string} p.reason Motif du signalement déclencheur.
 * @param {number} p.count Nombre de signalements du dossier.
 * @return {Promise<void>} Résolue une fois les envois tentés.
 */
async function notifyAdmins({entryId, targetType, reason, count}) {
  try {
    const admins = await db.collection("admins").get();
    const label = REPORT_TYPE_LABELS[targetType] || "Contenu";
    const why = REPORT_REASON_LABELS[reason] || reason;
    const body = `${label} · ${why} · ${count} signalement` +
      (count > 1 ? "s" : "");
    await Promise.all(admins.docs.map((admin) => notifyUser(admin.id, {
      type: "moderation",
      title: "Signalement prioritaire",
      body,
      data: {entryId},
    }).catch((err) => logger.error(`Alerte modération ${admin.id}`, err))));
  } catch (err) {
    logger.error("Alerte des administrateurs échouée", err);
  }
}

// ---------------------------------------------------------------------
// Modération — décisions.
//
// Seule porte d'écriture sur les dossiers de `moderationQueue` et sur le
// contenu d'autrui : l'écran de modération de l'app appelle cette
// fonction, qui vérifie elle-même que l'appelant figure dans `admins`.
//
//  - `dismiss` : rien à reprocher ; un contenu masqué automatiquement
//    est remis en ligne.
//  - `remove`  : le contenu est retiré (supprimé, ou vidé pour un message
//    privé, comme un « supprimer pour tout le monde »). Les triggers de
//    suppression existants font le ménage (images, sous-collections).
//  - `suspend` : le compte de l'auteur est désactivé dans Firebase Auth
//    et ses sessions révoquées. Réversible depuis la console.
// ---------------------------------------------------------------------

/**
 * Vérifie que l'appelant est administrateur.
 *
 * @param {object} request Requête `onCall`.
 * @return {Promise<string>} Uid de l'administrateur.
 */
async function requireAdmin(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
  if (!(await db.doc(`admins/${uid}`).get()).exists) {
    throw new HttpsError("permission-denied", "Réservé aux administrateurs.");
  }
  return uid;
}

exports.moderate = onCall({secrets: lives.LIVEKIT_SECRETS}, async (request) => {
  const adminUid = await requireAdmin(request);
  const {entryId, action} = request.data || {};
  if (typeof entryId !== "string" || !entryId || entryId.includes("/")) {
    throw new HttpsError("invalid-argument", "Dossier inconnu.");
  }
  if (!["dismiss", "remove", "suspend"].includes(action)) {
    throw new HttpsError("invalid-argument", "Action inconnue.");
  }

  const entryRef = db.doc(`moderationQueue/${entryId}`);
  const entry = await entryRef.get();
  if (!entry.exists) throw new HttpsError("not-found", "Dossier introuvable.");
  const {targetType, targetPath, targetOwnerUid} = entry.data();
  const targetRef = db.doc(targetPath);
  const target = await targetRef.get();

  if (action === "dismiss") {
    if (target.exists && HIDEABLE_TYPES.has(targetType)) {
      await targetRef.update({hidden: false});
    }
  } else if (action === "remove") {
    if (targetType === "user") {
      throw new HttpsError("failed-precondition",
          "Un profil ne se retire pas : suspendez le compte.");
    }
    if (target.exists) {
      if (targetType === "message") {
        await targetRef.update({
          deleted: true,
          content: "",
          fileName: FieldValue.delete(),
          thumbUrl: FieldValue.delete(),
          removedByModeration: true,
        });
      } else if (targetType === "live") {
        // La fiche reste : c'est la mémoire de la décision.
        await lives.endLiveInternal(targetRef.id, {
          by: adminUid, reason: "moderation",
        });
        await targetRef.update({removedByModeration: true});
      } else if (targetType === "comment") {
        const postRef = targetRef.parent.parent;
        const batch = db.batch();
        batch.delete(targetRef);
        if ((await postRef.get()).exists) {
          batch.update(postRef, {commentsCount: FieldValue.increment(-1)});
        }
        await batch.commit();
      } else {
        await targetRef.delete();
      }
    }
  } else {
    if (!targetOwnerUid) {
      throw new HttpsError("failed-precondition", "Auteur inconnu.");
    }
    if (targetOwnerUid === adminUid ||
        (await db.doc(`admins/${targetOwnerUid}`).get()).exists) {
      throw new HttpsError("failed-precondition",
          "Un administrateur ne peut pas être suspendu ici.");
    }
    try {
      await getAuth().updateUser(targetOwnerUid, {disabled: true});
      await getAuth().revokeRefreshTokens(targetOwnerUid);
    } catch (err) {
      if (err.code !== "auth/user-not-found") throw err;
    }
    const userRef = db.doc(`users/${targetOwnerUid}`);
    if ((await userRef.get()).exists) {
      await userRef.update({
        suspended: true,
        suspendedAt: FieldValue.serverTimestamp(),
      });
    }
    // Un compte suspendu ne garde pas l'antenne. Une panne de la base
    // temps réel ne doit pas faire échouer la suspension elle-même : le
    // compte est déjà désactivé, et le ménage des lives le rattrapera.
    try {
      await lives.endLivesOf(targetOwnerUid, adminUid);
    } catch (err) {
      logger.error(`Lives de ${targetOwnerUid} non coupés`, err);
    }
  }

  const outcome = {dismiss: "dismissed", remove: "removed", suspend: "suspended"};
  await entryRef.update({
    status: outcome[action],
    resolvedBy: adminUid,
    resolvedAt: FieldValue.serverTimestamp(),
  });
  logger.info(`Modération ${entryId} : ${action} par ${adminUid}`);
  return {status: outcome[action]};
});

// ---------------------------------------------------------------------
// Marché
// ---------------------------------------------------------------------

/**
 * Nombre maximum d'annonces qu'un compte peut publier par jour.
 *
 * Doit rester aligné sur `kDailyListingLimit` côté Dart. Le client
 * vérifie ce quota pour ne pas faire remplir un formulaire pour rien,
 * mais c'est **ici** qu'il est appliqué : un client modifié ne peut pas
 * contourner une suppression côté serveur, et c'est la barrière
 * principale contre l'inondation de la grille par un compte d'arnaqueur.
 */
const DAILY_LISTING_LIMIT = 5;

/** Début de la journée en cours (heure du serveur). */
function startOfToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

/**
 * Une annonce correspond-elle aux critères d'une recherche enregistrée ?
 *
 * Le rapprochement est fait en mémoire plutôt qu'en requête : à
 * l'échelle d'une commune, les recherches actives se comptent en
 * centaines, et une requête par critère demanderait un index par
 * combinaison. À revoir si le volume change d'ordre de grandeur.
 */
function searchMatches(search, item, keywords) {
  if (search.active === false) return false;
  if (search.category && search.category !== item.category) return false;
  if (search.listingType && search.listingType !== item.listingType) {
    return false;
  }
  if (search.place && search.place !== item.location) return false;
  if (typeof search.maxPrice === "number") {
    if (item.priceOnRequest) return false;
    if ((item.price || 0) > search.maxPrice) return false;
  }
  const query = (search.query || "").trim();
  if (query) {
    const tokens = marketKeywords(query, "");
    if (!tokens.every((t) => keywords.includes(t))) return false;
  }
  return true;
}

/**
 * Réparation planifiée du marché.
 *
 * Le passage au modèle « annonce qui vit et qui expire » ajoute des
 * champs (`bumpedAt`, `expiresAt`, `keywords`, compteurs) et sort le
 * numéro du document public. Les annonces publiées avant ce changement
 * ne les ont pas — et sans `bumpedAt` elles disparaîtraient du marché
 * sans un mot.
 *
 * Plutôt qu'un script à lancer depuis un poste (qui demande des
 * identifiants d'administrateur que personne n'a forcément sous la
 * main), la réparation tourne ici : elle s'exécute avec les droits de
 * l'Admin SDK, se répare toute seule au premier passage, et devient un
 * simple balayage sans écriture ensuite.
 *
 * Bornée à un lot par exécution : à l'échelle d'une commune, un passage
 * suffit ; si la base grossit, les suivants finiront le travail.
 */
exports.repairMarketListings = onSchedule(
    {schedule: "every day 03:00", timeZone: "Africa/Douala"},
    async () => {
      const snap = await db.collection("market")
          .orderBy("__name__")
          .limit(500)
          .get();

      let repaired = 0;
      for (const doc of snap.docs) {
        try {
          if (await backfillListing(doc.ref, doc.data())) repaired += 1;
        } catch (err) {
          logger.error(`Réparation de ${doc.id} impossible`, err);
        }
      }
      logger.info(
          `Réparation du marché : ${snap.size} annonce(s) examinée(s), ` +
          `${repaired} complétée(s).`,
      );
    },
);

/**
 * Nouvelle annonce : quota, jetons de recherche, compteur du vendeur,
 * puis alertes.
 */
exports.onMarketItemCreated = onDocumentCreated(
    "market/{itemId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const item = snap.data();
      const itemId = event.params.itemId;
      const sellerUid = item.sellerUid;
      if (!sellerUid) return;

      // --- Quota journalier, appliqué côté serveur ---------------------
      try {
        const todays = await db.collection("market")
            .where("sellerUid", "==", sellerUid)
            .where("createdAt", ">=", startOfToday())
            .count()
            .get();
        if (todays.data().count > DAILY_LISTING_LIMIT) {
          logger.warn(
              `Quota dépassé pour ${sellerUid} : annonce ${itemId} supprimée`,
          );
          await snap.ref.delete();
          await notifyUser(sellerUid, {
            type: "marketAlert",
            title: "Annonce refusée",
            body: `Vous ne pouvez publier que ${DAILY_LISTING_LIMIT} ` +
              "annonces par jour. Réessayez demain.",
            data: {},
          });
          return;
        }
      } catch (err) {
        // Un échec de comptage ne doit pas empêcher une annonce
        // légitime d'exister : on laisse passer et on trace.
        logger.error("Comptage du quota impossible", err);
      }

      // --- Rattrapage d'un client ancien --------------------------------
      // Une version déjà installée écrit encore le numéro dans le
      // document public (lisible par n'importe qui) et ignore
      // `bumpedAt`, sans lequel l'annonce n'apparaîtrait dans *aucune*
      // requête triée : publiée, puis invisible, sans un mot.
      try {
        await backfillListing(snap.ref, item);
      } catch (err) {
        logger.error(`Rattrapage de ${itemId} impossible`, err);
      }

      const keywords = (item.keywords && item.keywords.length > 0) ?
        item.keywords :
        marketKeywords(item.title, item.description);

      // --- Compteur d'annonces du vendeur, affiché sur sa fiche --------
      await db.doc(`users/${sellerUid}`)
          .set({listingsCount: FieldValue.increment(1)}, {merge: true})
          .catch((e) => logger.error("listingsCount", e));

      // --- Alertes ------------------------------------------------------
      if (item.sold === true || item.hidden === true) return;
      await notifySavedSearches(itemId, item, keywords);
    },
);

/**
 * Prévient les habitants dont une recherche enregistrée correspond à
 * l'annonce. Le vendeur ne reçoit jamais d'alerte sur sa propre annonce.
 */
async function notifySavedSearches(itemId, item, keywords) {
  let searches;
  try {
    searches = await db.collectionGroup("savedSearches")
        .where("active", "==", true)
        .get();
  } catch (err) {
    logger.error("Lecture des recherches enregistrées impossible", err);
    return;
  }

  // Un même habitant peut avoir plusieurs alertes qui correspondent : on
  // ne le notifie qu'une fois, sinon la même annonce sonne trois fois.
  const notified = new Set([item.sellerUid]);

  for (const doc of searches.docs) {
    const uid = doc.ref.parent.parent && doc.ref.parent.parent.id;
    if (!uid || notified.has(uid)) continue;
    if (!searchMatches(doc.data(), item, keywords)) continue;
    notified.add(uid);

    const price = item.priceOnRequest ?
      "Prix à discuter" :
      `${item.price || 0} FCFA`;
    await notifyUser(uid, {
      type: "marketAlert",
      title: "Nouvelle annonce pour vous",
      body: `${preview(item.title, 60)} — ${price}`,
      data: {itemId},
      fromUid: item.sellerUid,
      fromName: item.sellerName || "",
    }).catch((e) => logger.error(`Alerte marché pour ${uid}`, e));
  }
}

/**
 * Annonce supprimée : ménage des photos et du document de contact, que
 * les règles Storage/Firestore n'autorisent plus une fois le document
 * parent parti, et décrément du compteur du vendeur.
 */
exports.onMarketItemDeleted = onDocumentDeleted(
    "market/{itemId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const item = snap.data();
      const itemId = event.params.itemId;

      if (item.sellerUid) {
        await db.doc(`users/${item.sellerUid}`)
            .set({listingsCount: FieldValue.increment(-1)}, {merge: true})
            .catch((e) => logger.error("listingsCount (suppression)", e));
      }

      // Le client supprime déjà ses photos avant le document ; ce passage
      // ramasse ce qui aurait échoué (réseau coupé en cours de route) et
      // les orphelins d'une suppression faite depuis la console.
      // Même découpage que pour les publications : nouvel emplacement
      // `market/{sellerUid}/{itemId}/`, plus l'ancien `market/{itemId}/`.
      const marketPrefixes = [`market/${itemId}/`];
      if (item.sellerUid) {
        marketPrefixes.push(`market/${item.sellerUid}/${itemId}/`);
      }
      for (const prefix of marketPrefixes) {
        try {
          await getStorage().bucket().deleteFiles({prefix});
        } catch (err) {
          logger.error(`Nettoyage Storage de ${itemId} (${prefix})`, err);
        }
      }

      try {
        const contacts = await snap.ref.collection("contact").get();
        await Promise.all(contacts.docs.map((d) => d.ref.delete()));
      } catch (err) {
        logger.error(`Nettoyage du contact de ${itemId}`, err);
      }
    },
);

/**
 * Recalcule la réputation d'un vendeur à chaque avis écrit ou retiré.
 *
 * L'agrégat vit sur `users/{uid}` pour qu'une fiche annonce l'affiche
 * sans lire tous les avis. Il est **recalculé** (et non incrémenté) :
 * un avis modifié change la moyenne sans changer le nombre, ce qu'un
 * simple compteur ne saurait pas suivre.
 */
exports.onSellerReviewWritten = onDocumentWritten(
    "users/{uid}/reviews/{reviewerUid}",
    async (event) => {
      const uid = event.params.uid;
      try {
        const snap = await db.collection(`users/${uid}/reviews`).get();
        let sum = 0;
        let count = 0;
        snap.forEach((doc) => {
          const rating = Number(doc.data().rating);
          if (rating >= 1 && rating <= 5) {
            sum += rating;
            count += 1;
          }
        });
        await db.doc(`users/${uid}`).set({
          ratingCount: count,
          ratingAvg: count > 0 ? sum / count : 0,
        }, {merge: true});
      } catch (err) {
        logger.error(`Recalcul de la réputation de ${uid}`, err);
      }
    },
);

// ---------------------------------------------------------------------
// Statuts éphémères
//
// Un statut vit 24 h. Le client ne montre que ceux dont `expiresAt` est
// encore dans le futur — c'est ce qui rend l'expiration immédiate à
// l'écran, sans attendre quoi que ce soit du serveur. Le ménage ci-dessous
// s'occupe du reste : effacer pour de bon les documents périmés, leurs
// vues, leurs miroirs personnels et leurs photos, faute de quoi la base et
// le bucket grossiraient indéfiniment de contenus que plus personne ne
// peut voir.
// ---------------------------------------------------------------------

/** Documents purgés par passage — borne la durée et le coût d'un tour. */
const STATUS_PURGE_BATCH = 300;

/**
 * Efface une sous-collection d'un statut et les miroirs personnels
 * correspondants, que la suppression du document parent n'emporte pas.
 *
 * Le même traitement sert aux vues (`views` ↔ `users/{uid}/statusViews`)
 * et aux « j'aime » (`likes` ↔ `users/{uid}/statusLikes`) : dans les deux
 * cas l'identifiant du document *est* l'uid de la personne, ce qui suffit
 * à retrouver son miroir.
 *
 * @param {string} statusId Statut à nettoyer.
 * @param {string} sub Sous-collection du statut (`views` ou `likes`).
 * @param {string} mirror Sous-collection miroir sous `users/{uid}`.
 */
async function purgeStatusSubcollection(statusId, sub, mirror) {
  const ref = db.collection(`statuses/${statusId}/${sub}`);
  for (;;) {
    const snap = await ref.limit(400).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      batch.delete(db.doc(`users/${doc.id}/${mirror}/${statusId}`));
    }
    await batch.commit();
    if (snap.size < 400) return;
  }
}

/**
 * Efface vues et « j'aime » d'un statut, miroirs personnels compris.
 *
 * @param {string} statusId Statut dont les traces doivent disparaître.
 */
async function purgeStatusViews(statusId) {
  await purgeStatusSubcollection(statusId, "views", "statusViews");
  await purgeStatusSubcollection(statusId, "likes", "statusLikes");
}

/**
 * Repartage : recopie le média dans l'espace du repartageur.
 *
 * Un repartage pointe d'abord sur l'URL du statut d'origine — c'est ce
 * qui le rend visible dans l'instant, sans faire repasser la vidéo par le
 * forfait de qui repartage. Mais si l'auteur d'origine supprime son
 * statut, `onStatusDeleted` efface le fichier, et l'image disparaîtrait
 * de tous les repartages. On en fait donc une copie sous
 * `statuses/{repartageur}/{nouvelId}.{ext}`, puis on réécrit l'URL du
 * document : chaque repartage devient autonome, et le ménage de chacun ne
 * touche que ses propres fichiers.
 */
exports.onStatusCreated = onDocumentCreated(
    "statuses/{statusId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const status = snap.data();
      if (!status.repostOfId || !status.repostOfAuthorUid) return;

      const {statusId} = event.params;
      const bucket = getStorage().bucket();

      // On retrouve le fichier d'origine par son chemin, pas par l'URL :
      // celle-ci porte un jeton d'accès qui ne dit rien de l'objet.
      const sourceId = status.repostOfId;
      const sourceUid = status.repostOfAuthorUid;
      const isVideo = Boolean(status.videoUrl);
      const extensions = isVideo ? ["mp4", "mov"] : ["jpg"];

      for (const ext of extensions) {
        const source = bucket.file(`statuses/${sourceUid}/${sourceId}.${ext}`);
        try {
          const [exists] = await source.exists();
          if (!exists) continue;

          const target = bucket.file(
              `statuses/${status.authorUid}/${statusId}.${ext}`,
          );
          await source.copy(target);
          await target.makePublic().catch(() => {});
          const [url] = await target.getSignedUrl({
            action: "read",
            // Le fichier ne vit que le temps du statut ; l'URL n'a pas à
            // vivre plus longtemps, mais on prend large pour absorber un
            // décalage d'horloge.
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
          });
          await snap.ref.update(isVideo ? {videoUrl: url} : {imageUrl: url});
          logger.info(`Média du repartage ${statusId} recopié (${ext}).`);
          return;
        } catch (err) {
          logger.error(`Copie du média du repartage ${statusId}`, err);
        }
      }
    },
);

exports.onStatusDeleted = onDocumentDeleted(
    "statuses/{statusId}",
    async (event) => {
      const {statusId} = event.params;
      const status = event.data ? event.data.data() : null;

      try {
        await purgeStatusViews(statusId);
      } catch (err) {
        logger.error(`Purge des vues du statut ${statusId} échouée`, err);
      }

      // Le média porte l'uid de l'auteur dans son chemin (les règles
      // Storage y lisent le propriétaire) : `statuses/{authorUid}/{id}.jpg`
      // pour une photo, `.mp4` ou `.mov` pour une vidéo (l'extension suit
      // celle de l'original — la galerie iOS rend du QuickTime). On tente
      // chaque extension plutôt
      // que d'effacer par préfixe : `statuses/{uid}/{id}` est le préfixe
      // de tout identifiant commençant par celui-ci, et emporterait les
      // médias d'autres statuts.
      if (status && status.authorUid) {
        for (const ext of ["jpg", "mp4", "mov"]) {
          try {
            await getStorage().bucket()
                .file(`statuses/${status.authorUid}/${statusId}.${ext}`)
                .delete({ignoreNotFound: true});
          } catch (err) {
            logger.error(
                `Purge du média (${ext}) du statut ${statusId} échouée`, err);
          }
        }
      }
    },
);

/**
 * Ramasse les statuts arrivés à échéance. Toutes les heures : un statut
 * disparaît de l'écran à la seconde près grâce au filtre côté client, ce
 * passage n'a donc qu'à récupérer la place, pas à tenir l'heure.
 */
exports.purgeExpiredStatuses = onSchedule(
    {schedule: "every 1 hours", timeZone: "Africa/Douala"},
    async () => {
      const snap = await db.collection("statuses")
          .where("expiresAt", "<=", new Date())
          .limit(STATUS_PURGE_BATCH)
          .get();

      if (snap.empty) {
        logger.info("Statuts : rien à purger.");
        return;
      }

      // Suppression une par une, et non par lot : chaque suppression doit
      // déclencher `onStatusDeleted`, qui emporte vues et photo.
      let purged = 0;
      for (const doc of snap.docs) {
        try {
          await doc.ref.delete();
          purged += 1;
        } catch (err) {
          logger.error(`Suppression du statut ${doc.id} impossible`, err);
        }
      }
      logger.info(`Statuts : ${purged} statut(s) expiré(s) purgé(s).`);
    },
);


// ---------------------------------------------------------------------
// Serveurs TURN — identifiants temporaires Cloudflare
// ---------------------------------------------------------------------

/**
 * Clé TURN Cloudflare (Realtime → TURN Server). Posée une fois avec :
 *   firebase functions:secrets:set CLOUDFLARE_TURN_KEY_ID
 *   firebase functions:secrets:set CLOUDFLARE_TURN_API_TOKEN
 */
const CLOUDFLARE_TURN_KEY_ID = defineSecret("CLOUDFLARE_TURN_KEY_ID");
const CLOUDFLARE_TURN_API_TOKEN = defineSecret("CLOUDFLARE_TURN_API_TOKEN");

/** Durée de vie des identifiants remis à l'app : une demi-journée. */
const TURN_TTL_SECONDS = 12 * 60 * 60;

/**
 * Remet à l'app des serveurs ICE avec des identifiants TURN valables
 * [TURN_TTL_SECONDS].
 *
 * Le jeton Cloudflare ne quitte jamais le serveur : l'app ne reçoit que
 * des identifiants qui expirent d'eux-mêmes. Des identifiants fixes
 * (`config/webrtc`) seraient lisibles par n'importe quel compte connecté,
 * et donc réutilisables par n'importe qui pour faire passer son propre
 * trafic sur notre facture.
 *
 * En cas d'échec (secrets absents, Cloudflare injoignable), on répond
 * `failed-precondition` / `unavailable` : l'app retombe alors sur
 * `config/webrtc`, puis sur sa liste compilée.
 */
exports.getIceServers = onCall(
    {secrets: [CLOUDFLARE_TURN_KEY_ID, CLOUDFLARE_TURN_API_TOKEN]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Connexion requise.");
      }
      const keyId = CLOUDFLARE_TURN_KEY_ID.value();
      const token = CLOUDFLARE_TURN_API_TOKEN.value();
      // « unset » : valeur provisoire tant que le compte Cloudflare n'est
      // pas créé (le déploiement exige que les secrets existent).
      if (!keyId || !token || keyId === "unset" || token === "unset") {
        throw new HttpsError("failed-precondition", "TURN non configuré.");
      }

      let response;
      try {
        response = await fetch(
            `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}` +
              "/credentials/generate-ice-servers",
            {
              method: "POST",
              headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({ttl: TURN_TTL_SECONDS}),
              signal: AbortSignal.timeout(5000),
            },
        );
      } catch (err) {
        logger.error("TURN : Cloudflare injoignable", err);
        throw new HttpsError("unavailable", "Serveur TURN injoignable.");
      }
      if (!response.ok) {
        logger.error("TURN : réponse Cloudflare", response.status);
        throw new HttpsError("unavailable", "Serveur TURN indisponible.");
      }

      const body = await response.json();
      // `generate-ice-servers` renvoie une liste ; l'ancien point d'entrée
      // `generate` renvoyait un objet seul.
      const raw = Array.isArray(body.iceServers) ?
        body.iceServers :
        [body.iceServers].filter(Boolean);
      const iceServers = raw
          .map((s) => ({
            ...s,
            // Le port 53 est bloqué par la plupart des navigateurs et de
            // nombreux réseaux mobiles : inutile de le tenter.
            urls: [].concat(s.urls || []).filter((u) => !/:53(\?|$)/.test(u)),
          }))
          .filter((s) => s.urls.length > 0);
      if (!iceServers.length) {
        throw new HttpsError("unavailable", "Aucun serveur TURN reçu.");
      }
      return {iceServers, ttlSeconds: TURN_TTL_SECONDS};
    },
);


// ---------------------------------------------------------------------
// Modification du profil
// ---------------------------------------------------------------------

/**
 * Recopie le nom et la photo d'un compte sur tout ce qu'il a publié.
 *
 * Publications, commentaires, statuts, annonces et code de suivi portent
 * une copie du nom
 * (et de la photo) de leur auteur, pour s'afficher sans lire un profil par
 * ligne. Sans cette recopie, un compte qui change de nom garderait
 * l'ancien sur tout ce qu'il a écrit avant.
 *
 * @param {string} uid Compte.
 * @param {{name: (string|undefined), photo: (string|null|undefined)}} o
 *   Nouvelles valeurs ; `undefined` = inchangé, `photo: null` = retirée.
 * @return {Promise<number>} Documents mis à jour.
 */
async function propagateProfile(uid, {name, photo}) {
  const authorPatch = {};
  if (name !== undefined) authorPatch.authorName = name;
  if (photo !== undefined) {
    authorPatch.authorPhotoUrl = photo === null ? FieldValue.delete() : photo;
  }
  const sellerPatch = name !== undefined ? {sellerName: name} : null;

  const targets = [
    [db.collection("posts").where("authorUid", "==", uid), authorPatch],
    [db.collectionGroup("comments").where("authorUid", "==", uid), authorPatch],
    [db.collection("statuses").where("authorUid", "==", uid), authorPatch],
    [db.collection("market").where("sellerUid", "==", uid), sellerPatch],
    // Le guichet retrouve un habitant par son code de suivi et affiche ce
    // nom.
    [db.collection("trackingCodes").where("uid", "==", uid),
      name !== undefined ? {displayName: name} : null],
  ];
  let count = 0;
  for (const [query, patch] of targets) {
    if (!patch || !Object.keys(patch).length) continue;
    const snap = await query.get();
    // Paquets de 400 : une écriture groupée en accepte 500 au plus.
    for (let i = 0; i < snap.docs.length; i += 400) {
      const batch = db.batch();
      for (const doc of snap.docs.slice(i, i + 400)) batch.update(doc.ref, patch);
      await batch.commit();
    }
    count += snap.size;
  }
  return count;
}

/**
 * Appelée par l'app après un changement de nom ou de photo : recopie les
 * valeurs actuelles du profil sur tout ce que le compte a publié.
 *
 * Volontairement pas un déclencheur sur `users/{uid}` : ce document est
 * réécrit toutes les 25 s par le signal de présence de chaque personne
 * connectée, et chaque écriture aurait lancé une exécution.
 */
exports.syncProfileCopies = onCall({timeoutSeconds: 300}, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Profil absent.");
  const data = snap.data();
  const name = typeof data.displayName === "string" ?
    data.displayName.trim() : "";
  const photo = typeof data.photoUrl === "string" &&
    data.photoUrl.startsWith("http") ? data.photoUrl : null;
  const n = await propagateProfile(uid, {name: name || undefined, photo});
  logger.info(`Profil ${uid} recopié sur ${n} document(s)`);
  return {updated: n};
});
Object.defineProperty(exports, "_propagateProfile",
    {value: propagateProfile, enumerable: false});

// ---------------------------------------------------------------------
// Suppression de compte
// ---------------------------------------------------------------------

/**
 * Supprime chaque document renvoyé par [query], par paquets.
 *
 * `recursiveDelete` emporte aussi les sous-collections ; les triggers
 * `onPostDeleted`, `onMarketItemDeleted`, `onStatusDeleted` font ensuite
 * le ménage habituel (images, likes, miroirs).
 *
 * @param {FirebaseFirestore.Query} query Documents à supprimer.
 * @return {Promise<number>} Nombre de documents supprimés.
 */
async function deleteAll(query) {
  const snap = await query.get();
  for (const doc of snap.docs) {
    await db.recursiveDelete(doc.ref);
  }
  return snap.size;
}

/**
 * Supprime le compte de l'appelant et ce qu'il a publié — exigence du
 * Play Store pour toute application où l'on crée un compte.
 *
 * Effacé : profil et toutes ses sous-collections (coordonnées, jetons
 * push, notifications, favoris…), publications, commentaires, statuts,
 * annonces, démarches publiées, empreinte de téléphone, code de suivi,
 * liens d'abonnement (les compteurs des autres sont corrigés), fichiers
 * Storage, puis le compte Firebase Auth lui-même.
 *
 * Conservé : les messages déjà envoyés restent chez leur destinataire
 * (comme un courrier remis), les dossiers déposés auprès d'une structure
 * restent dans ses registres, et les signalements sont gardés pour la
 * modération. Le profil n'existant plus, ces traces s'affichent au nom
 * d'un « compte supprimé ».
 */
exports.deleteAccount = onCall({timeoutSeconds: 540}, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  logger.info(`deleteAccount : début pour ${uid}`);

  const step = async (label, fn) => {
    try {
      const n = await fn();
      logger.info(`deleteAccount ${uid} — ${label}`, n === undefined ? "" : n);
    } catch (err) {
      // On s'arrête là : le compte Auth n'est supprimé qu'en dernier,
      // l'appel reste donc rejouable et reprendra le ménage.
      logger.error(`deleteAccount ${uid} — ${label} en échec`, err);
      throw err;
    }
  };

  // 1. Contenus publiés.
  await step("publications", () =>
    deleteAll(db.collection("posts").where("authorUid", "==", uid)));
  await step("commentaires", () =>
    deleteAll(db.collectionGroup("comments").where("authorUid", "==", uid)));
  await step("statuts", () =>
    deleteAll(db.collection("statuses").where("authorUid", "==", uid)));
  await step("annonces", () =>
    deleteAll(db.collection("market").where("sellerUid", "==", uid)));
  await step("démarches", () =>
    deleteAll(db.collection("demarches").where("structureUid", "==", uid)));

  // 2. Annuaires : plus personne ne doit pouvoir le retrouver.
  await step("annuaire téléphonique", () =>
    deleteAll(db.collection("phoneDirectory").where("uid", "==", uid)));
  await step("code de suivi", () =>
    deleteAll(db.collection("trackingCodes").where("uid", "==", uid)));
  await step("quota de contacts", () =>
    db.doc(`contactMatchQuota/${uid}`).delete());

  // 3. Abonnements : retirer les liens des deux côtés et corriger les
  // compteurs des autres comptes.
  // `update` et non `set(merge)` : si l'autre compte a déjà disparu, on
  // ne doit pas lui recréer un profil fantôme.
  const unlink = async (otherUid, edge, counter) => {
    const other = db.doc(`users/${otherUid}`);
    const batch = db.batch();
    batch.delete(db.doc(`users/${otherUid}/${edge}/${uid}`));
    if ((await other.get()).exists) {
      batch.update(other, {[counter]: FieldValue.increment(-1)});
    }
    await batch.commit();
  };
  await step("abonnements", async () => {
    const following = await db.collection(`users/${uid}/following`).get();
    for (const doc of following.docs) {
      await unlink(doc.id, "followers", "followersCount");
    }
    const followers = await db.collection(`users/${uid}/followers`).get();
    for (const doc of followers.docs) {
      await unlink(doc.id, "following", "followingCount");
    }
    return following.size + followers.size;
  });

  // 4. Profil et toutes ses sous-collections.
  await step("profil", () => db.recursiveDelete(db.doc(`users/${uid}`)));

  // 5. Fichiers.
  const bucket = getStorage().bucket();
  for (const prefix of [`profiles/${uid}/`, `statuses/${uid}/`,
    `posts/${uid}/`, `market/${uid}/`]) {
    await step(`fichiers ${prefix}`, () => bucket.deleteFiles({prefix}));
  }

  // 6. Le compte lui-même, en dernier : tant qu'il existe, l'appel peut
  // être rejoué pour finir le travail.
  await step("compte Auth", () => getAuth().deleteUser(uid));
  logger.info(`deleteAccount : ${uid} supprimé`);
  return {deleted: true};
});
