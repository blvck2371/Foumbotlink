/**
 * Appels : qui reçoit un jeton LiveKit, et quand la salle est fermée.
 *
 * Awa appelle Bob. Seuls eux deux entrent dans la salle `call_{id}`, et
 * seulement tant que l'appel sonne ou est en cours. Carole (étrangère à
 * l'appel), Dan (bloqué) et un compte suspendu restent dehors. À la fin
 * de l'appel, la salle est fermée.
 *
 * LiveKit est remplacé par un faux qui note ce qu'on lui demande.
 *
 *   npm run test:calls
 */

const PROJECT = process.env.GCLOUD_PROJECT || "demo-calls";
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT});

const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc: clientDoc, getDoc, updateDoc, arrayRemove, collection, query, where,
  getDocs,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");
const index = require("../index.js");
const {setLiveKitFactory} = require("../lives.js");

const {joinCall, inviteToCall, onCallUpdated} = index;

const AWA = "awa";
const BOB = "bob";
const CAROLE = "carole";
const DAN = "dan";
const SUSPENDU = "suspendu";
const EVE = "eve";
const FRED = "fred";

let failures = 0;

/**
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas.
 */
async function check(name, body) {
  try {
    await body();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures++;
    console.error(`  ✗ ${name}\n    ${err.stack || err.message}`);
  }
}

/**
 * @param {boolean} ok Condition.
 * @param {string} what Ce qui était attendu.
 */
function expect(ok, what) {
  if (!ok) throw new Error(what);
}

/**
 * @param {Promise} promise Appel.
 * @param {string} code Code HttpsError attendu.
 */
async function expectHttpsError(promise, code) {
  try {
    await promise;
  } catch (err) {
    expect(err.code === code, `code ${code} attendu, reçu ${err.code}`);
    return;
  }
  throw new Error(`refus ${code} attendu, l'appel a réussi`);
}

const call = (fn, uid, data) => fn.run({data, auth: uid ? {uid} : null});

const liveKitCalls = [];
setLiveKitFactory(() => ({
  url: "wss://faux.livekit.test",
  token: async ({identity, name, room, publish}) =>
    `jeton:${identity}:${name}:${room}:${publish ? "emet" : "regarde"}`,
  deleteRoom: async (room) => {
    liveKitCalls.push(["deleteRoom", room]);
  },
  removeParticipant: async () => {},
}));

/**
 * Simule le déclencheur Firestore sur un changement de statut.
 *
 * @param {string} callId Appel.
 * @param {object} before Données avant.
 * @param {object} after Données après.
 */
async function fireUpdated(callId, before, after) {
  await onCallUpdated.run({
    params: {callId},
    data: {
      before: {data: () => before},
      after: {data: () => after, ref: getFirestore().doc(`calls/${callId}`)},
    },
  });
}

/**
 * Relit l'appel et rejoue le déclencheur comme après une écriture.
 *
 * @param {string} callId Appel.
 * @param {object} before Données avant l'écriture.
 * @return {Promise<object>} Données après le déclencheur.
 */
async function settle(callId, before) {
  const ref = getFirestore().doc(`calls/${callId}`);
  const after = (await ref.get()).data();
  await fireUpdated(callId, before, after);
  return (await ref.get()).data();
}

/** @return {Promise<void>} */
async function main() {
  const db = getFirestore();
  await db.doc(`users/${AWA}`).set({displayName: "Awa"});
  await db.doc(`users/${BOB}`).set({displayName: "Bob"});
  await db.doc(`users/${CAROLE}`).set({displayName: "Carole"});
  await db.doc(`users/${DAN}`).set({displayName: "Dan"});
  await db.doc(`users/${SUSPENDU}`).set({displayName: "S", suspended: true});
  await db.doc(`users/${BOB}/blocked/${DAN}`).set({displayName: "Dan"});
  await db.doc(`users/${EVE}`).set({displayName: "Ève"});
  await db.doc(`users/${FRED}`).set({displayName: "Fred"});

  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  const as = (uid) => env.authenticatedContext(uid).firestore();

  const newCall = async (callerUid, calleeUid, status = "ringing") => {
    const ref = db.collection("calls").doc();
    await ref.set({
      callerUid, calleeUid, status, type: "audio", conversationId: "c",
      createdAt: Timestamp.now(),
    });
    return ref.id;
  };

  console.log("Appels — jetons LiveKit");
  const callId = await newCall(AWA, BOB);

  await check("sans connexion ou sans identifiant valable : refus", async () => {
    await expectHttpsError(call(joinCall, null, {callId}), "unauthenticated");
    await expectHttpsError(call(joinCall, AWA, {}), "invalid-argument");
    await expectHttpsError(
        call(joinCall, AWA, {callId: "../users/x"}), "invalid-argument");
    await expectHttpsError(
        call(joinCall, AWA, {callId: "inexistant"}), "not-found");
  });

  await check("l'appelante et l'appelé entrent dans la même salle", async () => {
    const a = await call(joinCall, AWA, {callId});
    const b = await call(joinCall, BOB, {callId});
    const room = `call_${callId}`;
    expect(a.room === room && b.room === room, `salle ${a.room} / ${b.room}`);
    expect(a.url === "wss://faux.livekit.test", a.url);
    expect(a.token === `jeton:${AWA}:Awa:${room}:emet`, a.token);
    expect(b.token === `jeton:${BOB}:Bob:${room}:emet`, b.token);
  });

  await check("un tiers n'entre pas", async () => {
    await expectHttpsError(call(joinCall, CAROLE, {callId}),
        "permission-denied");
  });

  await check("appel en cours : on peut encore (re)joindre", async () => {
    await db.doc(`calls/${callId}`).update({status: "accepted"});
    await call(joinCall, BOB, {callId});
  });

  await check("appel terminé : plus de jeton", async () => {
    for (const status of ["ended", "declined", "missed", "busy"]) {
      await db.doc(`calls/${callId}`).update({status});
      await expectHttpsError(call(joinCall, AWA, {callId}),
          "failed-precondition");
    }
  });

  await check("blocage, dans un sens comme dans l'autre : refus", async () => {
    const id = await newCall(DAN, BOB);
    await expectHttpsError(call(joinCall, DAN, {callId: id}),
        "permission-denied");
    await expectHttpsError(call(joinCall, BOB, {callId: id}),
        "permission-denied");
  });

  await check("compte suspendu : refus", async () => {
    const id = await newCall(SUSPENDU, AWA);
    await expectHttpsError(call(joinCall, SUSPENDU, {callId: id}),
        "permission-denied");
  });

  console.log("Appels — fermeture de la salle");

  await check("fin d'appel : la salle LiveKit est fermée", async () => {
    liveKitCalls.length = 0;
    const base = {callerUid: AWA, calleeUid: BOB, type: "audio"};
    await fireUpdated(callId, {...base, status: "accepted"},
        {...base, status: "ended"});
    expect(liveKitCalls.some(([op, room]) =>
      op === "deleteRoom" && room === `call_${callId}`),
    JSON.stringify(liveKitCalls));
  });

  await check("décroché (ringing → accepted) : la salle reste ouverte",
      async () => {
        liveKitCalls.length = 0;
        const base = {callerUid: AWA, calleeUid: BOB, type: "audio"};
        await fireUpdated(callId, {...base, status: "ringing"},
            {...base, status: "accepted"});
        expect(liveKitCalls.length === 0, JSON.stringify(liveKitCalls));
      });


  console.log("Appels de groupe");
  const gid = await newCall(AWA, BOB, "accepted");
  const gref = db.doc(`calls/${gid}`);

  await check("on n'ajoute personne à un appel qui sonne encore", async () => {
    const ringing = await newCall(AWA, BOB);
    await expectHttpsError(call(inviteToCall, AWA, {callId: ringing, uid: CAROLE}),
        "failed-precondition");
  });

  await check("un tiers ne peut pas inviter ; on ne s'invite pas soi-même",
      async () => {
        await expectHttpsError(call(inviteToCall, CAROLE, {callId: gid, uid: EVE}),
            "permission-denied");
        await expectHttpsError(call(inviteToCall, AWA, {callId: gid, uid: AWA}),
            "invalid-argument");
      });

  await check("personne bloquée par un membre : refus", async () => {
    await expectHttpsError(call(inviteToCall, AWA, {callId: gid, uid: DAN}),
        "permission-denied");
  });

  await check("Awa ajoute Carole : l'appel passe en groupe", async () => {
    const res = await call(inviteToCall, AWA, {callId: gid, uid: CAROLE});
    expect(res.invited && res.name === "Carole", JSON.stringify(res));
    const c = (await gref.get()).data();
    expect(c.group === true, "group");
    expect(c.members[AWA].state === "joined", "Awa en communication");
    expect(c.members[BOB].state === "joined", "Bob en communication");
    expect(c.members[CAROLE].state === "ringing", "Carole sonne");
    expect(c.members[CAROLE].invitedBy === AWA, "invitée par Awa");
    expect(c.ringingUids.includes(CAROLE), "ringingUids");
    expect([AWA, BOB, CAROLE].every((u) => c.memberUids.includes(u)),
        "memberUids");
    await expectHttpsError(call(inviteToCall, BOB, {callId: gid, uid: CAROLE}),
        "already-exists");
  });

  await check("Carole trouve l'appel qui sonne pour elle et le lit", async () => {
    const q = query(collection(as(CAROLE), "calls"),
        where("ringingUids", "array-contains", CAROLE));
    const snap = await assertSucceeds(getDocs(q));
    expect(snap.docs.some((d) => d.id === gid), "appel trouvé");
    await assertSucceeds(getDoc(clientDoc(as(CAROLE), `calls/${gid}`)));
    await assertFails(getDoc(clientDoc(as(EVE), `calls/${gid}`)));
    // La requête de l'appelé (1:1) marche toujours.
    await assertSucceeds(getDocs(query(collection(as(BOB), "calls"),
        where("calleeUid", "==", BOB))));
  });

  await check("Carole reçoit un jeton pour la salle commune", async () => {
    const res = await call(joinCall, CAROLE, {callId: gid});
    expect(res.room === `call_${gid}`, res.room);
    await expectHttpsError(call(joinCall, EVE, {callId: gid}),
        "permission-denied");
  });

  await check("règles : chacun ne touche qu'à sa ligne", async () => {
    const mine = clientDoc(as(CAROLE), `calls/${gid}`);
    await assertSucceeds(updateDoc(mine, {
      [`members.${CAROLE}.state`]: "joined",
      "ringingUids": arrayRemove(CAROLE),
    }));
    // Pas la ligne d'un autre, pas le statut de l'appel, pas d'invitation.
    await assertFails(updateDoc(mine, {[`members.${BOB}.state`]: "left"}));
    await assertFails(updateDoc(mine, {status: "ended"}));
    await assertFails(updateDoc(mine, {[`members.${CAROLE}.state`]: "ringing"}));
    await assertFails(updateDoc(mine, {
      [`members.${EVE}`]: {state: "ringing"},
    }));
    // Bob (appelé d'origine) ne coupe plus l'appel pour tout le monde.
    await assertFails(updateDoc(clientDoc(as(BOB), `calls/${gid}`),
        {status: "ended"}));
  });

  await check("Bob raccroche : Awa et Carole continuent", async () => {
    const before = (await gref.get()).data();
    await assertSucceeds(updateDoc(clientDoc(as(BOB), `calls/${gid}`), {
      [`members.${BOB}.state`]: "left",
    }));
    const after = await settle(gid, before);
    expect(after.status === "accepted", `statut ${after.status}`);
    await expectHttpsError(call(joinCall, BOB, {callId: gid}),
        "failed-precondition");
  });

  await check("huit participants au plus", async () => {
    const big = await newCall(AWA, BOB, "accepted");
    const extra = ["u1", "u2", "u3", "u4", "u5", "u6"];
    for (const u of extra) {
      await db.doc(`users/${u}`).set({displayName: u});
      await call(inviteToCall, AWA, {callId: big, uid: u});
    }
    await db.doc("users/u7").set({displayName: "u7"});
    await expectHttpsError(call(inviteToCall, AWA, {callId: big, uid: "u7"}),
        "resource-exhausted");
  });

  await check("Awa seule, Fred sonne encore : l'appel attend", async () => {
    await call(inviteToCall, CAROLE, {callId: gid, uid: FRED});
    const before = (await gref.get()).data();
    await updateDoc(clientDoc(as(CAROLE), `calls/${gid}`),
        {[`members.${CAROLE}.state`]: "left"});
    const after = await settle(gid, before);
    expect(after.status === "accepted", `statut ${after.status}`);
  });

  await check("Fred ne répond pas : l'appel est clos, la salle fermée",
      async () => {
        liveKitCalls.length = 0;
        const before = (await gref.get()).data();
        await updateDoc(clientDoc(as(FRED), `calls/${gid}`), {
          [`members.${FRED}.state`]: "missed",
          "ringingUids": arrayRemove(FRED),
        });
        const ended = await settle(gid, before);
        expect(ended.status === "ended", `statut ${ended.status}`);
        // La clôture repasse par le déclencheur, qui ferme la salle.
        await fireUpdated(gid, {...ended, status: "accepted"}, ended);
        expect(liveKitCalls.some(([op, room]) =>
          op === "deleteRoom" && room === `call_${gid}`),
        JSON.stringify(liveKitCalls));
      });

  await env.cleanup();

  if (failures) {
    console.error(`\n${failures} échec(s)`);
    process.exit(1);
  }
  console.log("\nTout est bon.");
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
