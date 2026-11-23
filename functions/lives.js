/**
 * Lives — diffusion vidéo en direct, façon TikTok.
 *
 * Deux briques, chacune dans son rôle :
 *
 *  - **LiveKit** transporte l'image et le son : le téléphone de l'hôte
 *    envoie un seul flux au serveur média, qui le redistribue à chaque
 *    spectateur en adaptant la qualité à son réseau. Firebase ne sait pas
 *    faire ça.
 *  - **Firebase Realtime Database** porte tout le reste, en temps réel :
 *    la liste des lives en cours (`lives`), les spectateurs présents
 *    (`liveViewers`), les commentaires (`liveComments`), les cœurs
 *    (`lives/{id}/likes`). La présence de l'hôte repose sur `onDisconnect`,
 *    que Firestore n'offre pas.
 *
 * Personne n'entre dans une salle LiveKit sans un jeton signé ici : c'est
 * ce qui permet d'appliquer blocages, exclusions et suspensions. Les
 * règles RTDB (database.rules.json) n'autorisent à commenter ou à envoyer
 * des cœurs que les membres inscrits par ces fonctions (`liveMembers`).
 *
 * Firestore garde la trace de chaque live (`liveSessions/{id}`) : c'est la
 * cible des signalements et la mémoire de la modération, quand les nœuds
 * RTDB ont disparu avec la fin du live.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onValueWritten} = require("firebase-functions/v2/database");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const {getDatabaseWithUrl, ServerValue} = require("firebase-admin/database");
const {FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

// Clés du projet LiveKit Cloud — posées avec
// `firebase functions:secrets:set LIVEKIT_URL` (et _API_KEY, _API_SECRET).
const LIVEKIT_URL = defineSecret("LIVEKIT_URL");
const LIVEKIT_API_KEY = defineSecret("LIVEKIT_API_KEY");
const LIVEKIT_API_SECRET = defineSecret("LIVEKIT_API_SECRET");
const LIVEKIT_SECRETS = [LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET];

/** Instance Realtime Database (Belgique, la plus proche du Cameroun). */
const RTDB_INSTANCE = "foumbotlink-default-rtdb";
const RTDB_REGION = "europe-west1";
const RTDB_URL = process.env.LIVE_RTDB_URL ||
  `https://${RTDB_INSTANCE}.${RTDB_REGION}.firebasedatabase.app`;

/** Longueur maximale d'un titre de live. */
const MAX_TITLE = 80;

/** Durée maximale d'un live : au-delà, il est clos automatiquement. */
const MAX_LIVE_MS = 4 * 60 * 60 * 1000;

/**
 * Temps laissé à un hôte qui a perdu la connexion (changement d'antenne,
 * tunnel…) pour revenir avant que son live soit clos.
 */
const HOST_GRACE_MS = 90 * 1000;

/** Durée de validité d'un jeton LiveKit. */
const TOKEN_TTL = "6h";

/** Abonnés prévenus au lancement d'un live (les plus anciens d'abord). */
const FOLLOWER_NOTIFY_CAP = 300;

/**
 * Signalements distincts qui coupent un live sans attendre un humain.
 * Plus bas que pour une publication : un live ne se « masque » pas, et ce
 * qu'il montre est vu tout de suite.
 */
const LIVE_REPORT_END_THRESHOLD = 3;

/**
 * Accès LiveKit. Remplaçable par les tests, qui n'ont ni réseau ni clés.
 *
 * @return {object} `{url, token(), deleteRoom(), removeParticipant()}`.
 */
let liveKitFactory = () => {
  const {AccessToken, RoomServiceClient} = require("livekit-server-sdk");
  const url = LIVEKIT_URL.value();
  const key = LIVEKIT_API_KEY.value();
  const secret = LIVEKIT_API_SECRET.value();
  const rooms = new RoomServiceClient(url.replace(/^ws/, "http"), key, secret);
  return {
    url,
    async token({identity, name, room, publish}) {
      const at = new AccessToken(key, secret, {identity, name, ttl: TOKEN_TTL});
      at.addGrant({
        roomJoin: true,
        room,
        canSubscribe: true,
        canPublish: publish,
        canPublishData: publish,
        // Les spectateurs n'apparaissent pas aux autres participants :
        // pas de trafic de présence LiveKit pour une salle de 200
        // personnes. La présence visible passe par `liveViewers`.
        hidden: !publish,
      });
      return at.toJwt();
    },
    deleteRoom: (room) => rooms.deleteRoom(room),
    removeParticipant: (room, identity) =>
      rooms.removeParticipant(room, identity),
  };
};

module.exports = function lives({db, notifyUser}) {
  const rtdb = () => getDatabaseWithUrl(RTDB_URL);
  const liveKit = () => liveKitFactory();

  const requireUid = (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    return uid;
  };

  const requireLiveId = (value) => {
    if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,40}$/.test(value)) {
      throw new HttpsError("invalid-argument", "Live inconnu.");
    }
    return value;
  };

  const isAdmin = async (uid) =>
    (await db.doc(`admins/${uid}`).get()).exists;

  /**
   * Profil exploitable pour entrer dans un live, ou refus explicite.
   *
   * @param {string} uid Compte.
   * @return {Promise<{name: string, photo: (string|null)}>} Profil.
   */
  async function liveProfile(uid) {
    const snap = await db.doc(`users/${uid}`).get();
    if (!snap.exists) {
      throw new HttpsError("failed-precondition",
          "Créez votre profil pour participer aux lives.");
    }
    const data = snap.data();
    if (data.suspended) {
      throw new HttpsError("permission-denied", "Ce compte est suspendu.");
    }
    const name = (typeof data.displayName === "string" &&
      data.displayName.trim()) || "Habitant";
    const photo = typeof data.photoUrl === "string" &&
      data.photoUrl.startsWith("http") ? data.photoUrl.slice(0, 1000) : null;
    return {name: name.slice(0, 80), photo};
  }

  /**
   * Titre affiché, nettoyé ; à défaut, « Live de {nom} ».
   *
   * @param {*} raw Titre saisi.
   * @param {string} hostName Nom de l'hôte.
   * @return {string} Titre.
   */
  function cleanTitle(raw, hostName) {
    const t = typeof raw === "string" ? raw.replace(/\s+/g, " ").trim() : "";
    return (t || `Live de ${hostName}`).slice(0, MAX_TITLE);
  }

  /**
   * Clôt un live : efface ses nœuds temps réel (les apps des spectateurs
   * le voient disparaître et quittent la salle), archive le bilan dans
   * `liveSessions`, puis ferme la salle LiveKit — ce qui coupe aussi un
   * client modifié qui continuerait d'émettre.
   *
   * @param {string} liveId Live.
   * @param {object} o Motif.
   * @param {string} o.by Uid (ou « system ») à l'origine de la fin.
   * @param {string} o.reason host | admin | moderation | reports |
   *   hostGone | tooLong | replaced | lost.
   * @return {Promise<boolean>} Faux si le live était déjà clos.
   */
  async function endLiveInternal(liveId, {by, reason}) {
    const snap = await rtdb().ref(`lives/${liveId}`).get();
    const live = snap.val();
    await rtdb().ref().update({
      [`lives/${liveId}`]: null,
      [`liveViewers/${liveId}`]: null,
      [`liveComments/${liveId}`]: null,
      [`liveMembers/${liveId}`]: null,
      [`liveBans/${liveId}`]: null,
    });

    const sessionRef = db.doc(`liveSessions/${liveId}`);
    const session = await sessionRef.get();
    if (session.exists && session.get("status") === "live") {
      await sessionRef.update({
        status: "ended",
        endedAt: FieldValue.serverTimestamp(),
        endReason: reason,
        endedBy: by,
        likes: (live && live.likes) || 0,
        peakViewers: Math.max(
            session.get("peakViewers") || 0,
            (live && live.peakViewers) || 0,
        ),
      });
    }

    try {
      await liveKit().deleteRoom(liveId);
    } catch (err) {
      // Salle déjà fermée (personne n'y était) : rien à faire.
      logger.info(`Live ${liveId} : salle LiveKit non fermée`, err.message);
    }
    logger.info(`Live ${liveId} clos (${reason}) par ${by}`);
    return Boolean(live);
  }

  /**
   * Ajoute `delta` au compteur de spectateurs, sans jamais recréer un
   * live déjà clos : `viewers` existe tant que le live existe, et une
   * transaction qui le lit absent n'écrit rien.
   *
   * @param {string} liveId Live.
   * @param {number} delta +1 ou -1.
   * @return {Promise<void>}
   */
  async function applyViewerDelta(liveId, delta) {
    const base = rtdb().ref(`lives/${liveId}`);
    const result = await base.child("viewers").transaction((n) =>
      n === null ? null : Math.max(0, n + delta));
    const viewers = result.snapshot.val();
    if (delta > 0 && typeof viewers === "number") {
      await base.child("peakViewers").transaction((peak) =>
        peak === null ? null : Math.max(peak, viewers));
    }
  }

  // -------------------------------------------------------------------
  // Fonctions appelées par l'app
  // -------------------------------------------------------------------

  const startLive = onCall({secrets: LIVEKIT_SECRETS}, async (request) => {
    const uid = requireUid(request);
    const {name, photo} = await liveProfile(uid);
    const title = cleanTitle(request.data && request.data.title, name);

    // Un seul live à la fois : celui qu'une app tuée a laissé ouvert est
    // clos avant d'en ouvrir un autre.
    const mine = await rtdb().ref("lives")
        .orderByChild("hostUid").equalTo(uid).get();
    for (const id of Object.keys(mine.val() || {})) {
      await endLiveInternal(id, {by: uid, reason: "replaced"});
    }

    const liveId = rtdb().ref("lives").push().key;
    await db.doc(`liveSessions/${liveId}`).set({
      hostUid: uid,
      hostName: name,
      photoUrl: photo,
      title,
      status: "live",
      startedAt: FieldValue.serverTimestamp(),
      likes: 0,
      peakViewers: 0,
    });
    const live = {
      hostUid: uid,
      hostName: name,
      title,
      startedAt: ServerValue.TIMESTAMP,
      // L'app de l'hôte passe `hostOnline` à vrai une fois connectée ;
      // sans elle sous 90 s, le ménage planifié clôt le live.
      hostOnline: false,
      hostSeenAt: ServerValue.TIMESTAMP,
      viewers: 0,
      peakViewers: 0,
      likes: 0,
    };
    if (photo) live.hostPhoto = photo;
    await rtdb().ref().update({
      [`lives/${liveId}`]: live,
      [`liveMembers/${liveId}/${uid}`]: "host",
    });

    const lk = liveKit();
    const token = await lk.token({
      identity: uid, name, room: liveId, publish: true,
    });
    logger.info(`Live ${liveId} ouvert par ${uid}`);
    return {liveId, url: lk.url, token, title, role: "host"};
  });

  const joinLive = onCall({secrets: LIVEKIT_SECRETS}, async (request) => {
    const uid = requireUid(request);
    const liveId = requireLiveId(request.data && request.data.liveId);
    const live = (await rtdb().ref(`lives/${liveId}`).get()).val();
    if (!live) throw new HttpsError("not-found", "Ce live est terminé.");

    const isHost = live.hostUid === uid;
    if (!isHost) {
      const banned = await rtdb().ref(`liveBans/${liveId}/${uid}`).get();
      if (banned.exists()) {
        throw new HttpsError("permission-denied",
            "L'hôte vous a retiré de ce live.");
      }
      const [hostBlocked, viewerBlocked] = await Promise.all([
        db.doc(`users/${live.hostUid}/blocked/${uid}`).get(),
        db.doc(`users/${uid}/blocked/${live.hostUid}`).get(),
      ]);
      if (hostBlocked.exists || viewerBlocked.exists) {
        throw new HttpsError("permission-denied",
            "Ce live ne vous est pas accessible.");
      }
    }
    const {name} = await liveProfile(uid);
    if (!isHost) {
      await rtdb().ref(`liveMembers/${liveId}/${uid}`).set("viewer");
    }

    const lk = liveKit();
    const token = await lk.token({
      identity: uid, name, room: liveId, publish: isHost,
    });
    return {liveId, url: lk.url, token, role: isHost ? "host" : "viewer"};
  });

  const endLive = onCall({secrets: LIVEKIT_SECRETS}, async (request) => {
    const uid = requireUid(request);
    const liveId = requireLiveId(request.data && request.data.liveId);
    const live = (await rtdb().ref(`lives/${liveId}`).get()).val();
    if (!live) return {ended: false};
    const host = live.hostUid === uid;
    if (!host && !(await isAdmin(uid))) {
      throw new HttpsError("permission-denied",
          "Seul l'hôte peut terminer ce live.");
    }
    await endLiveInternal(liveId, {by: uid, reason: host ? "host" : "admin"});
    return {ended: true};
  });

  const expelFromLive = onCall({secrets: LIVEKIT_SECRETS}, async (request) => {
    const uid = requireUid(request);
    const liveId = requireLiveId(request.data && request.data.liveId);
    const target = request.data && request.data.uid;
    if (typeof target !== "string" || !target || target.includes("/")) {
      throw new HttpsError("invalid-argument", "Spectateur inconnu.");
    }
    const live = (await rtdb().ref(`lives/${liveId}`).get()).val();
    if (!live) throw new HttpsError("not-found", "Ce live est terminé.");
    if (live.hostUid !== uid && !(await isAdmin(uid))) {
      throw new HttpsError("permission-denied",
          "Seul l'hôte peut retirer un spectateur.");
    }
    if (target === live.hostUid) {
      throw new HttpsError("invalid-argument",
          "L'hôte ne peut pas être retiré de son propre live.");
    }

    const update = {
      [`liveBans/${liveId}/${target}`]: true,
      [`liveMembers/${liveId}/${target}`]: null,
      [`liveViewers/${liveId}/${target}`]: null,
    };
    // Ses commentaires partent avec lui.
    const comments = await rtdb().ref(`liveComments/${liveId}`)
        .orderByChild("uid").equalTo(target).get();
    for (const id of Object.keys(comments.val() || {})) {
      update[`liveComments/${liveId}/${id}`] = null;
    }
    await rtdb().ref().update(update);

    try {
      await liveKit().removeParticipant(liveId, target);
    } catch (err) {
      logger.info(`Live ${liveId} : ${target} déjà sorti`, err.message);
    }
    return {expelled: true};
  });

  // -------------------------------------------------------------------
  // Déclencheurs et ménage
  // -------------------------------------------------------------------

  /** Compteur de spectateurs, tenu par le serveur et non par les apps. */
  const onLiveViewerWritten = onValueWritten({
    ref: "/liveViewers/{liveId}/{uid}",
    instance: RTDB_INSTANCE,
    region: RTDB_REGION,
  }, async (event) => {
    const before = event.data.before.exists();
    const after = event.data.after.exists();
    if (before === after) return;
    await applyViewerDelta(event.params.liveId, after ? 1 : -1);
  });

  /**
   * Clôt les lives abandonnés : hôte parti sans revenir, live trop long,
   * et remet d'accord Firestore avec la base temps réel.
   *
   * @param {number} now Horloge (injectée par les tests).
   * @return {Promise<number>} Nombre de lives clos.
   */
  async function cleanupLivesOnce(now = Date.now()) {
    const all = (await rtdb().ref("lives").get()).val() || {};
    let ended = 0;
    for (const [id, live] of Object.entries(all)) {
      // Nœud fantôme : un `onDisconnect` de l'hôte exécuté après la fin
      // du live a pu réécrire `hostOnline` seul. Rien à archiver.
      if (!live || !live.hostUid) {
        await rtdb().ref(`lives/${id}`).remove();
        continue;
      }
      const started = live.startedAt || 0;
      const seen = live.hostSeenAt || started;
      let reason = null;
      if (now - started > MAX_LIVE_MS) reason = "tooLong";
      else if (!live.hostOnline && now - seen > HOST_GRACE_MS) {
        reason = "hostGone";
      }
      if (reason) {
        await endLiveInternal(id, {by: "system", reason});
        ended++;
      }
    }
    const open = await db.collection("liveSessions")
        .where("status", "==", "live").get();
    for (const doc of open.docs) {
      if (all[doc.id]) continue;
      await doc.ref.update({
        status: "ended",
        endedAt: FieldValue.serverTimestamp(),
        endReason: "lost",
        endedBy: "system",
      });
    }
    return ended;
  }

  const cleanupLives = onSchedule({
    schedule: "every 5 minutes",
    secrets: LIVEKIT_SECRETS,
  }, async () => {
    const n = await cleanupLivesOnce();
    if (n) logger.info(`Lives abandonnés clos : ${n}`);
  });

  /** « X est en live » : prévient ses abonnés. */
  const onLiveSessionCreated = onDocumentCreated(
      "liveSessions/{liveId}", async (event) => {
        const s = event.data && event.data.data();
        if (!s || !s.hostUid) return;
        const followers = await db
            .collection(`users/${s.hostUid}/followers`)
            .limit(FOLLOWER_NOTIFY_CAP).get();
        await Promise.all(followers.docs.map((f) => notifyUser(f.id, {
          type: "live",
          title: `${s.hostName} est en live`,
          body: s.title,
          data: {liveId: event.params.liveId},
          fromUid: s.hostUid,
          fromName: s.hostName,
        }).catch((err) => logger.error(`Alerte live → ${f.id}`, err))));
      });

  /**
   * Clôt les lives en cours d'un compte (suspension).
   *
   * @param {string} uid Hôte.
   * @param {string} by Auteur de la décision.
   * @return {Promise<void>}
   */
  async function endLivesOf(uid, by) {
    const mine = await rtdb().ref("lives")
        .orderByChild("hostUid").equalTo(uid).get();
    for (const id of Object.keys(mine.val() || {})) {
      await endLiveInternal(id, {by, reason: "moderation"});
    }
  }

  return {
    startLive,
    joinLive,
    endLive,
    expelFromLive,
    onLiveViewerWritten,
    cleanupLives,
    onLiveSessionCreated,
    // Pour la modération et les tests.
    endLiveInternal,
    endLivesOf,
    applyViewerDelta,
    cleanupLivesOnce,
    LIVEKIT_SECRETS,
    LIVE_REPORT_END_THRESHOLD,
  };
};

/**
 * Tests uniquement : remplace l'accès LiveKit.
 *
 * @param {Function} factory Renvoie `{url, token, deleteRoom,
 *   removeParticipant}`.
 */
module.exports.setLiveKitFactory = (factory) => {
  liveKitFactory = factory;
};
module.exports.RTDB_URL = RTDB_URL;
// Partagés avec les appels (calls.js), qui passent aussi par LiveKit.
module.exports.LIVEKIT_SECRETS = LIVEKIT_SECRETS;
module.exports.liveKit = () => liveKitFactory();
