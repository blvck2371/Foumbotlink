/**
 * Appels audio et vidéo — le média passe par LiveKit.
 *
 * La sonnerie ne change pas : le document Firestore `calls/{callId}`
 * (statut ringing → accepted → ended…) et les pushes `incoming_call` /
 * `call_cancelled` d'index.js. Seul le transport de la voix et de l'image
 * a changé : au lieu d'une connexion directe entre les deux téléphones
 * (WebRTC pair-à-pair, qui échouait dès qu'un des deux était derrière le
 * NAT d'un opérateur mobile), chacun rejoint la salle LiveKit
 * `call_{callId}` et LiveKit relaie le flux.
 *
 * **Appel de groupe.** Un appel commence toujours à deux. Pendant la
 * communication, un participant peut en ajouter d'autres
 * ([inviteToCall]) : le document passe alors en mode groupe
 *
 *   group: true
 *   memberUids: [uid, …]            tous les membres, passés et présents
 *   ringingUids: [uid, …]           ceux dont le téléphone sonne
 *   members: {uid: {state, name, invitedBy, invitedAt, at}}
 *
 * où `state` vaut ringing | joined | left | declined | missed | busy.
 * Chacun n'écrit plus que son propre `members.{uid}` (règles Firestore) :
 * raccrocher fait quitter l'appel sans le couper pour les autres. C'est le
 * serveur ([settleGroupCall]) qui clôt l'appel (`status: ended`) quand il
 * ne reste plus personne à qui parler.
 *
 * Personne n'entre dans la salle LiveKit sans un jeton signé ici : seuls
 * les membres d'un appel encore vivant en reçoivent un, et jamais entre
 * deux comptes dont l'un a bloqué l'autre.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {liveKit, LIVEKIT_SECRETS} = require("./lives");

/** Statuts pendant lesquels on peut (encore) entrer dans la salle. */
const JOINABLE = ["ringing", "accepted"];

/** États d'un membre qui occupent une place dans l'appel. */
const ACTIVE_STATES = ["ringing", "joined"];

/** Participants simultanés au plus (membres qui sonnent compris). */
const MAX_CALL_MEMBERS = 8;

const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
const UID_RE = /^[A-Za-z0-9]{1,128}$/;

/**
 * Salle LiveKit d'un appel.
 *
 * @param {string} callId Document `calls/{callId}`.
 * @return {string} Nom de la salle.
 */
const callRoom = (callId) => `call_${callId}`;

/**
 * Membres d'un appel. Un appel à deux n'a pas encore de `members` : on
 * les déduit de l'appelant et de l'appelé, tous deux en communication.
 *
 * @param {object} call Document `calls/{id}`.
 * @return {Object<string, object>} Membres par uid.
 */
function membersOf(call) {
  if (call.group && call.members) return call.members;
  return {
    [call.callerUid]: {state: "joined"},
    [call.calleeUid]: {state: "joined"},
  };
}

/**
 * Uids des membres dans l'un des états donnés.
 *
 * @param {object} call Document.
 * @param {string[]} states États retenus.
 * @return {string[]} Uids.
 */
function uidsIn(call, states) {
  return Object.entries(membersOf(call))
      .filter(([, m]) => m && states.includes(m.state))
      .map(([uid]) => uid);
}

module.exports = function calls({db, sendToUser}) {
  const requireUid = (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    return uid;
  };

  const requireCallId = (value) => {
    if (typeof value !== "string" || !ID_RE.test(value)) {
      throw new HttpsError("invalid-argument", "Appel inconnu.");
    }
    return value;
  };

  /**
   * Vrai si l'un des deux comptes a bloqué l'autre.
   *
   * @param {string} a Compte.
   * @param {string} b Autre compte.
   * @return {Promise<boolean>}
   */
  async function blockedBetween(a, b) {
    const [ab, ba] = await Promise.all([
      db.doc(`users/${a}/blocked/${b}`).get(),
      db.doc(`users/${b}/blocked/${a}`).get(),
    ]);
    return ab.exists || ba.exists;
  }

  /**
   * Profil utilisable dans un appel, ou refus.
   *
   * @param {string} uid Compte.
   * @return {Promise<{name: string}>}
   */
  async function callProfile(uid) {
    const snap = await db.doc(`users/${uid}`).get();
    const profile = snap.exists ? snap.data() : {};
    if (profile.suspended) {
      throw new HttpsError("permission-denied", "Ce compte est suspendu.");
    }
    const name = ((typeof profile.displayName === "string" &&
      profile.displayName.trim()) || "Habitant").slice(0, 80);
    return {name, exists: snap.exists};
  }

  const joinCall = onCall({secrets: LIVEKIT_SECRETS}, async (request) => {
    const uid = requireUid(request);
    const callId = requireCallId(request.data && request.data.callId);

    const snap = await db.doc(`calls/${callId}`).get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Cet appel n'existe plus.");
    }
    const call = snap.data();
    const isPair = uid === call.callerUid || uid === call.calleeUid;
    const me = call.group ? (call.members || {})[uid] : null;
    if (call.group ? !me : !isPair) {
      throw new HttpsError("permission-denied", "Cet appel ne vous concerne pas.");
    }
    if (!JOINABLE.includes(call.status)) {
      throw new HttpsError("failed-precondition", "Cet appel est terminé.");
    }
    if (me && !ACTIVE_STATES.includes(me.state)) {
      throw new HttpsError("failed-precondition",
          "Vous avez quitté cet appel.");
    }

    // Personne avec qui l'un a bloqué l'autre dans la même salle.
    const others = call.group ?
      uidsIn(call, ACTIVE_STATES).filter((u) => u !== uid) :
      [uid === call.callerUid ? call.calleeUid : call.callerUid];
    const blocks = await Promise.all(others.map((o) => blockedBetween(uid, o)));
    if (blocks.some(Boolean)) {
      throw new HttpsError("permission-denied", "Cet appel n'est pas possible.");
    }
    const {name} = await callProfile(uid);

    const lk = liveKit();
    const room = callRoom(callId);
    const token = await lk.token({identity: uid, name, room, publish: true});
    return {url: lk.url, token, room};
  });

  /**
   * Ajoute quelqu'un à un appel en cours : son téléphone sonne, et s'il
   * décroche il rejoint la même salle.
   */
  const inviteToCall = onCall(async (request) => {
    const uid = requireUid(request);
    const callId = requireCallId(request.data && request.data.callId);
    const target = request.data && request.data.uid;
    if (typeof target !== "string" || !UID_RE.test(target) || target === uid) {
      throw new HttpsError("invalid-argument", "Personne inconnue.");
    }

    const ref = db.doc(`calls/${callId}`);
    const first = await ref.get();
    if (!first.exists) {
      throw new HttpsError("not-found", "Cet appel n'existe plus.");
    }
    // Vérifications hors transaction (lectures de profils et de blocages),
    // refaites sur l'état frais dans la transaction pour ce qui peut bouger.
    const [inviter, invitee] = await Promise.all([
      callProfile(uid), callProfile(target),
    ]);
    if (!invitee.exists) {
      throw new HttpsError("not-found", "Ce compte n'existe plus.");
    }
    const present = uidsIn(first.data(), ACTIVE_STATES);
    const blocks = await Promise.all(
        present.filter((u) => u !== target)
            .map((u) => blockedBetween(target, u)));
    if (blocks.some(Boolean)) {
      throw new HttpsError("permission-denied",
          `${invitee.name} ne peut pas rejoindre cet appel.`);
    }

    const call = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data();
      if (data.status !== "accepted") {
        throw new HttpsError("failed-precondition",
            "On ne peut ajouter quelqu'un qu'à un appel en cours.");
      }
      const members = membersOf(data);
      if (!members[uid] || members[uid].state !== "joined") {
        throw new HttpsError("permission-denied",
            "Vous ne participez pas à cet appel.");
      }
      const current = members[target];
      if (current && ACTIVE_STATES.includes(current.state)) {
        throw new HttpsError("already-exists",
            `${invitee.name} est déjà dans l'appel.`);
      }
      if (uidsIn(data, ACTIVE_STATES).length >= MAX_CALL_MEMBERS) {
        throw new HttpsError("resource-exhausted",
            `${MAX_CALL_MEMBERS} participants au plus par appel.`);
      }

      const update = {
        "group": true,
        "memberUids": FieldValue.arrayUnion(
            data.callerUid, data.calleeUid, target),
        "ringingUids": FieldValue.arrayUnion(target),
        [`members.${target}`]: {
          state: "ringing",
          name: invitee.name,
          invitedBy: uid,
          invitedAt: FieldValue.serverTimestamp(),
        },
      };
      if (!data.group) {
        // Passage en groupe : l'appelant et l'appelé deviennent des membres
        // comme les autres.
        const [callerName, calleeName] = await Promise.all([
          callProfile(data.callerUid).then((p) => p.name),
          callProfile(data.calleeUid).then((p) => p.name),
        ]);
        update[`members.${data.callerUid}`] =
          {state: "joined", name: callerName};
        update[`members.${data.calleeUid}`] =
          {state: "joined", name: calleeName};
      }
      tx.update(ref, update);
      return data;
    });

    await sendToUser(target, {
      data: {
        type: "incoming_call",
        callId,
        callerUid: uid,
        callerName: `${inviter.name} · appel de groupe`,
        callType: call.type || "audio",
        conversationId: "",
        group: "1",
      },
      android: {priority: "high"},
      apns: {
        headers: {"apns-push-type": "alert", "apns-priority": "10"},
        payload: {aps: {"content-available": 1, "mutable-content": 1}},
      },
    });
    logger.info(`Appel ${callId} : ${uid} ajoute ${target}`);
    return {invited: true, name: invitee.name};
  });

  /**
   * Appel de groupe : clôt l'appel quand plus personne ne peut se parler —
   * personne en communication, ou un seul et plus personne qui sonne.
   *
   * @param {FirebaseFirestore.DocumentReference} ref Document.
   * @param {object} call Données après l'écriture.
   * @return {Promise<boolean>} Vrai si l'appel vient d'être clos.
   */
  async function settleGroupCall(ref, call) {
    if (!call.group || call.status !== "accepted") return false;
    const joined = uidsIn(call, ["joined"]).length;
    const ringing = uidsIn(call, ["ringing"]).length;
    if (joined > 1 || (joined === 1 && ringing > 0)) return false;
    await ref.update({status: "ended", endedAt: FieldValue.serverTimestamp()});
    logger.info(`Appel de groupe ${ref.id} clos (plus personne)`);
    return true;
  }

  /**
   * Ferme la salle d'un appel terminé : coupe aussi un téléphone qui
   * n'aurait pas vu la fin (app figée, réseau revenu trop tard).
   *
   * @param {string} callId Appel.
   * @return {Promise<void>}
   */
  async function closeCallRoom(callId) {
    try {
      await liveKit().deleteRoom(callRoom(callId));
    } catch (err) {
      // Salle déjà vide et fermée par LiveKit, ou jamais ouverte.
      logger.info(`Appel ${callId} : salle non fermée`, err.message);
    }
  }

  return {
    joinCall,
    inviteToCall,
    settleGroupCall,
    closeCallRoom,
    uidsIn,
  };
};

module.exports.callRoom = callRoom;
module.exports.MAX_CALL_MEMBERS = MAX_CALL_MEMBERS;
