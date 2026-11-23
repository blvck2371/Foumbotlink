/**
 * Lives de bout en bout, sous les vraies règles Realtime Database et
 * Firestore : Awa lance un live, Bob le rejoint, commente, envoie des
 * cœurs ; Carole (sans profil), Dan (bloqué par Awa) et les curieux non
 * inscrits restent dehors. Puis exclusion, fin, ménage des lives
 * abandonnés et coupure par signalements.
 *
 * LiveKit est remplacé par un faux qui note ce qu'on lui demande : ce
 * test vérifie qui reçoit un jeton et avec quels droits, pas la vidéo.
 *
 *   npm run test:lives
 */

const PROJECT = process.env.GCLOUD_PROJECT || "demo-lives";
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT});
// Même espace de noms que les clients de test (rules-unit-testing).
process.env.LIVE_RTDB_URL =
  `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST || "127.0.0.1:9000"}` +
  `?ns=${PROJECT}`;

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {doc, setDoc} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");
const {getFirestore} = require("firebase-admin/firestore");
const {getDatabaseWithUrl} = require("firebase-admin/database");
const index = require("../index.js");
const {setLiveKitFactory} = require("../lives.js");

const {
  startLive, joinLive, endLive, expelFromLive, onLiveSessionCreated,
  onReportCreated, moderate,
} = index;
const lives = index._lives;

const TS = {".sv": "timestamp"};
const AWA = "awa";
const BOB = "bob";
const CAROLE = "carole";
const DAN = "dan";
const EVE = "eve";
const ADMIN = "admin";

let failures = 0;

/**
 * Exécute une vérification en annonçant son résultat.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas.
 * @return {Promise<void>}
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
 * Attend un refus de fonction avec ce code.
 *
 * @param {Promise} promise Appel.
 * @param {string} code Code HttpsError attendu.
 * @return {Promise<void>}
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

/** Faux LiveKit : jetons lisibles, appels notés. */
const liveKitCalls = [];
setLiveKitFactory(() => ({
  url: "wss://faux.livekit.test",
  token: async ({identity, room, publish}) =>
    `jeton:${identity}:${room}:${publish ? "emet" : "regarde"}`,
  deleteRoom: async (room) => {
    liveKitCalls.push(["deleteRoom", room]);
  },
  removeParticipant: async (room, identity) => {
    liveKitCalls.push(["removeParticipant", room, identity]);
  },
}));

/**
 * Point d'entrée.
 *
 * @return {Promise<void>}
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    database: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "database.rules.json"), "utf8"),
      host: "127.0.0.1",
      port: 9000,
    },
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  const db = getFirestore();
  const rtdb = getDatabaseWithUrl(process.env.LIVE_RTDB_URL);
  const as = (uid) => env.authenticatedContext(uid).database();
  const anon = env.unauthenticatedContext().database();
  const val = async (p) => (await rtdb.ref(p).get()).val();

  for (const [uid, name] of [[AWA, "Awa"], [BOB, "Bob"], [DAN, "Dan"],
    [EVE, "Ève"], [ADMIN, "Modération"]]) {
    await db.doc(`users/${uid}`).set({displayName: name});
  }
  await db.doc(`users/${AWA}/blocked/${DAN}`).set({displayName: "Dan"});
  await db.doc(`users/${AWA}/followers/${BOB}`).set({at: new Date()});
  await db.doc(`admins/${ADMIN}`).set({});

  console.log("Lives — lancement");
  let liveId;

  await check("sans connexion ni profil, pas de live", async () => {
    await expectHttpsError(call(startLive, null, {}), "unauthenticated");
    await expectHttpsError(call(startLive, CAROLE, {}), "failed-precondition");
  });

  await check("Awa lance un live : jeton d'émission, fiche, nœud temps réel",
      async () => {
        const res = await call(startLive, AWA, {title: "  Marché   du soir  "});
        liveId = res.liveId;
        expect(res.token === `jeton:${AWA}:${liveId}:emet`, res.token);
        expect(res.url === "wss://faux.livekit.test", res.url);
        expect(res.title === "Marché du soir", res.title);
        const live = await val(`lives/${liveId}`);
        expect(live.hostUid === AWA && live.hostName === "Awa", "hôte");
        expect(live.viewers === 0 && live.likes === 0, "compteurs à zéro");
        expect(live.hostOnline === false, "hôte pas encore connecté");
        const session = (await db.doc(`liveSessions/${liveId}`).get()).data();
        expect(session.status === "live" && session.hostUid === AWA, "fiche");
        expect(await val(`liveMembers/${liveId}/${AWA}`) === "host", "membre");
      });

  await check("titre vide : « Live de Awa »", async () => {
    const res = await call(startLive, EVE, {title: "   "});
    expect(res.title === "Live de Ève", res.title);
    await lives.endLiveInternal(res.liveId, {by: EVE, reason: "host"});
  });

  await check("les abonnés d'Awa sont prévenus", async () => {
    const snap = await db.doc(`liveSessions/${liveId}`).get();
    await onLiveSessionCreated.run({
      params: {liveId},
      data: {id: liveId, data: () => snap.data()},
    });
    const notifs = await db.collection(`users/${BOB}/notifications`)
        .where("type", "==", "live").get();
    expect(notifs.size === 1, `1 notification attendue, ${notifs.size}`);
    const n = notifs.docs[0].data();
    expect(n.title === "Awa est en live", n.title);
    expect(n.data && n.data.liveId === liveId, "liveId dans la notification");
  });

  console.log("Lives — présence de l'hôte");

  await check("Awa signale sa présence ; Bob ne peut pas le faire pour elle",
      async () => {
        await assertSucceeds(as(AWA).ref(`lives/${liveId}`).update({
          hostOnline: true, hostSeenAt: TS,
        }));
        await assertFails(
            as(BOB).ref(`lives/${liveId}/hostOnline`).set(false));
        await assertFails(as(AWA).ref(`lives/${liveId}/title`).set("Autre"));
        await assertFails(as(AWA).ref(`lives/${liveId}/viewers`).set(500));
      });

  await check("la liste des lives est réservée aux comptes connectés",
      async () => {
        await assertFails(anon.ref("lives").get());
        await assertSucceeds(as(BOB).ref("lives").get());
      });

  console.log("Lives — spectateurs");

  await check("avant d'entrer, Bob ne lit ni n'écrit rien", async () => {
    await assertFails(as(BOB).ref(`liveComments/${liveId}`).get());
    await assertFails(as(BOB).ref(`liveComments/${liveId}`).push({
      uid: BOB, name: "Bob", text: "Salut", at: TS,
    }));
    await assertFails(as(BOB).ref(`lives/${liveId}/likes`).set(1));
    await assertFails(as(BOB).ref(`liveViewers/${liveId}/${BOB}`).set({
      name: "Bob", at: TS,
    }));
  });

  await check("Bob entre : jeton de spectateur, sans droit d'émettre",
      async () => {
        const res = await call(joinLive, BOB, {liveId});
        expect(res.token === `jeton:${BOB}:${liveId}:regarde`, res.token);
        expect(res.role === "viewer", res.role);
        expect(await val(`liveMembers/${liveId}/${BOB}`) === "viewer", "membre");
      });

  await check("Awa rentre dans son propre live avec un jeton d'émission",
      async () => {
        const res = await call(joinLive, AWA, {liveId});
        expect(res.role === "host" && res.token.endsWith(":emet"), res.token);
      });

  await check("Dan, bloqué par Awa, et Carole, sans profil, restent dehors",
      async () => {
        await expectHttpsError(call(joinLive, DAN, {liveId}),
            "permission-denied");
        await expectHttpsError(call(joinLive, CAROLE, {liveId}),
            "failed-precondition");
        await expectHttpsError(call(joinLive, BOB, {liveId: "../x"}),
            "invalid-argument");
        await expectHttpsError(call(joinLive, BOB, {liveId: "inexistant"}),
            "not-found");
      });

  await check("Bob se signale présent, commente et envoie des cœurs",
      async () => {
        await assertSucceeds(as(BOB).ref(`liveViewers/${liveId}/${BOB}`).set({
          name: "Bob", at: TS,
        }));
        await assertSucceeds(as(BOB).ref(`liveComments/${liveId}`).push({
          uid: BOB, name: "Bob", text: "Bonsoir Foumbot !", at: TS,
        }));
        await assertSucceeds(as(BOB).ref(`liveComments/${liveId}`).get());
        await assertSucceeds(as(BOB).ref(`lives/${liveId}/likes`).set(3));
        expect(await val(`lives/${liveId}/likes`) === 3, "3 cœurs");
      });

  await check("commentaires et cœurs invalides refusés", async () => {
    const comments = as(BOB).ref(`liveComments/${liveId}`);
    await assertFails(comments.push({
      uid: BOB, name: "Bob", text: "x".repeat(201), at: TS,
    }));
    await assertFails(comments.push({
      uid: AWA, name: "Awa", text: "usurpé", at: TS,
    }));
    await assertFails(comments.push({
      uid: BOB, name: "Bob", text: "Salut", at: TS, pin: true,
    }));
    await assertFails(comments.push({
      uid: BOB, name: "Bob", text: "Salut", at: 1,
    }));
    await assertFails(as(BOB).ref(`lives/${liveId}/likes`).set(2));
    await assertFails(as(BOB).ref(`lives/${liveId}/likes`).set(500));
  });

  await check("compteur de spectateurs tenu par le serveur", async () => {
    await lives.applyViewerDelta(liveId, 1);
    await lives.applyViewerDelta(liveId, 1);
    await lives.applyViewerDelta(liveId, -1);
    const live = await val(`lives/${liveId}`);
    expect(live.viewers === 1, `1 spectateur, ${live.viewers}`);
    expect(live.peakViewers === 2, `pic de 2, ${live.peakViewers}`);
  });

  await check("chacun efface ses commentaires ; l'hôte efface ceux des autres",
      async () => {
        const mine = as(BOB).ref(`liveComments/${liveId}`).push();
        await mine.set({uid: BOB, name: "Bob", text: "oups", at: TS});
        const other = as(EVE);
        await call(joinLive, EVE, {liveId});
        await assertFails(
            other.ref(`liveComments/${liveId}/${mine.key}`).remove());
        await assertSucceeds(
            as(BOB).ref(`liveComments/${liveId}/${mine.key}`).remove());
        const again = as(BOB).ref(`liveComments/${liveId}`).push();
        await again.set({uid: BOB, name: "Bob", text: "re", at: TS});
        await assertSucceeds(
            as(AWA).ref(`liveComments/${liveId}/${again.key}`).remove());
      });

  console.log("Lives — exclusion et fin");

  await check("seule Awa peut retirer Bob, qui perd tout accès", async () => {
    await expectHttpsError(call(expelFromLive, EVE, {liveId, uid: BOB}),
        "permission-denied");
    await expectHttpsError(call(expelFromLive, AWA, {liveId, uid: AWA}),
        "invalid-argument");
    await call(expelFromLive, AWA, {liveId, uid: BOB});
    expect(await val(`liveBans/${liveId}/${BOB}`) === true, "banni");
    expect(await val(`liveMembers/${liveId}/${BOB}`) === null, "plus membre");
    expect(await val(`liveViewers/${liveId}/${BOB}`) === null, "plus présent");
    const left = Object.values(await val(`liveComments/${liveId}`) || {});
    expect(!left.some((c) => c.uid === BOB), "ses commentaires effacés");
    expect(liveKitCalls.some(([op, room, who]) =>
      op === "removeParticipant" && room === liveId && who === BOB),
    "sorti de la salle LiveKit");
    await assertFails(as(BOB).ref(`liveComments/${liveId}`).push({
      uid: BOB, name: "Bob", text: "je reviens", at: TS,
    }));
    await expectHttpsError(call(joinLive, BOB, {liveId}), "permission-denied");
  });

  await check("seule Awa (ou l'admin) termine le live", async () => {
    await expectHttpsError(call(endLive, EVE, {liveId}), "permission-denied");
    const res = await call(endLive, AWA, {liveId});
    expect(res.ended === true, "terminé");
    expect(await val(`lives/${liveId}`) === null, "nœud effacé");
    expect(await val(`liveComments/${liveId}`) === null, "commentaires effacés");
    expect(await val(`liveMembers/${liveId}`) === null, "membres effacés");
    const s = (await db.doc(`liveSessions/${liveId}`).get()).data();
    expect(s.status === "ended" && s.endReason === "host", s.endReason);
    expect(s.likes === 3 && s.peakViewers === 2, `bilan ${s.likes}/${s.peakViewers}`);
    expect(liveKitCalls.some(([op, room]) =>
      op === "deleteRoom" && room === liveId), "salle LiveKit fermée");
  });

  await check("un live clos ne renaît pas (compteurs, cœurs, présence)",
      async () => {
        await lives.applyViewerDelta(liveId, 1);
        expect(await val(`lives/${liveId}`) === null, "pas de live fantôme");
        await assertFails(as(EVE).ref(`lives/${liveId}/likes`).set(1));
        await assertFails(as(AWA).ref(`lives/${liveId}/hostOnline`).set(false));
        await expectHttpsError(call(joinLive, EVE, {liveId}), "not-found");
        const again = await call(endLive, AWA, {liveId});
        expect(again.ended === false, "deuxième fin sans effet");
      });

  await check("un second live d'Awa clôt celui resté ouvert", async () => {
    const first = await call(startLive, AWA, {title: "Un"});
    const second = await call(startLive, AWA, {title: "Deux"});
    expect(await val(`lives/${first.liveId}`) === null, "premier clos");
    expect(await val(`lives/${second.liveId}`) !== null, "second ouvert");
    const s = (await db.doc(`liveSessions/${first.liveId}`).get()).data();
    expect(s.endReason === "replaced", s.endReason);
    await call(endLive, ADMIN, {liveId: second.liveId});
    const s2 = (await db.doc(`liveSessions/${second.liveId}`).get()).data();
    expect(s2.endReason === "admin", `fin par l'admin : ${s2.endReason}`);
  });

  console.log("Lives — ménage planifié");

  await check("hôte parti, live trop long, nœud fantôme, fiche orpheline",
      async () => {
        const gone = (await call(startLive, AWA, {title: "Parti"})).liveId;
        const alive = (await call(startLive, EVE, {title: "Là"})).liveId;
        await rtdb.ref(`lives/${alive}`).update({
          hostOnline: true, hostSeenAt: Date.now(),
        });
        await rtdb.ref("lives/fantome").set({hostOnline: false, hostSeenAt: 1});
        await db.doc("liveSessions/orpheline").set({
          hostUid: DAN, title: "?", status: "live",
        });

        // Deux minutes plus tard : Awa n'est jamais revenue.
        const ended = await lives.cleanupLivesOnce(Date.now() + 2 * 60e3);
        expect(ended === 1, `1 live clos, ${ended}`);
        expect(await val(`lives/${gone}`) === null, "live abandonné clos");
        expect(await val(`lives/${alive}`) !== null, "live actif gardé");
        expect(await val("lives/fantome") === null, "fantôme effacé");
        const orphan = (await db.doc("liveSessions/orpheline").get()).data();
        expect(orphan.status === "ended" && orphan.endReason === "lost",
            "fiche orpheline close");
        const s = (await db.doc(`liveSessions/${gone}`).get()).data();
        expect(s.endReason === "hostGone", s.endReason);

        // Cinq heures plus tard : même un hôte présent est arrêté.
        await lives.cleanupLivesOnce(Date.now() + 5 * 3600e3);
        expect(await val(`lives/${alive}`) === null, "live trop long clos");
      });

  console.log("Lives — modération");

  await check("un live se signale depuis l'app (règles Firestore)", async () => {
    const live = (await call(startLive, AWA, {title: "À signaler"})).liveId;
    const report = (uid) => ({
      targetType: "live",
      targetId: live,
      targetPath: `liveSessions/${live}`,
      targetOwnerUid: AWA,
      reporterUid: uid,
      reason: "nuditeSexuel",
      details: "",
      excerpt: "À signaler",
      status: "pending",
    });
    const fsFor = (uid) => env.authenticatedContext(uid).firestore();
    await assertSucceeds(setDoc(
        doc(fsFor(BOB), "reports", `live_${live}_${BOB}`), report(BOB)));
    await assertFails(setDoc(doc(fsFor(EVE), "reports", `live_x_${EVE}`), {
      ...report(EVE), targetPath: "posts/x",
    }));
    await call(endLive, AWA, {liveId: live});
  });

  await check("trois signalements coupent le live", async () => {
    const live = (await call(startLive, AWA, {title: "Signalé"})).liveId;
    for (const [i, uid] of ["r1", "r2", "r3"].entries()) {
      const id = `live_${live}_${uid}`;
      const data = {
        targetType: "live", targetId: live,
        targetPath: `liveSessions/${live}`, targetOwnerUid: AWA,
        reporterUid: uid, reason: "violence", status: "pending",
      };
      await db.doc(`reports/${id}`).set(data);
      await onReportCreated.run({params: {reportId: id},
        data: {id, data: () => data}});
      const still = await val(`lives/${live}`);
      if (i < 2) expect(still !== null, `encore en ligne après ${i + 1}`);
    }
    expect(await val(`lives/${live}`) === null, "coupé au 3e signalement");
    const s = (await db.doc(`liveSessions/${live}`).get()).data();
    expect(s.endReason === "reports", s.endReason);
    const q = (await db.doc(`moderationQueue/live_${live}`).get()).data();
    expect(q.targetOwnerUid === AWA && q.reportsCount === 3, "dossier ouvert");
  });

  await check("l'admin retire un live ; suspendre l'hôte coupe ses lives",
      async () => {
        const live = (await call(startLive, AWA, {title: "Retiré"})).liveId;
        const id = `live_${live}_r9`;
        const data = {
          targetType: "live", targetId: live,
          targetPath: `liveSessions/${live}`, targetOwnerUid: AWA,
          reporterUid: "r9", reason: "spam", status: "pending",
        };
        await db.doc(`reports/${id}`).set(data);
        await onReportCreated.run({params: {reportId: id},
          data: {id, data: () => data}});
        await moderate.run({
          data: {entryId: `live_${live}`, action: "remove"},
          auth: {uid: ADMIN},
        });
        expect(await val(`lives/${live}`) === null, "live retiré");
        const s = (await db.doc(`liveSessions/${live}`).get()).data();
        expect(s.removedByModeration === true, "fiche marquée");

        const next = (await call(startLive, EVE, {title: "Suspendue"})).liveId;
        const id2 = `live_${next}_r9`;
        const data2 = {...data, targetId: next,
          targetPath: `liveSessions/${next}`, targetOwnerUid: EVE};
        await db.doc(`reports/${id2}`).set(data2);
        await onReportCreated.run({params: {reportId: id2},
          data: {id: id2, data: () => data2}});
        await moderate.run({
          data: {entryId: `live_${next}`, action: "suspend"},
          auth: {uid: ADMIN},
        });
        expect(await val(`lives/${next}`) === null, "live de la suspendue coupé");
      });

  await env.cleanup();
  if (failures) {
    console.error(`\n${failures} échec(s).`);
    process.exit(1);
  }
  console.log("\nTous les cas passent.");
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
