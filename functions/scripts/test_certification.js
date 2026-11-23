/**
 * Certification : conditions lues dans `config/certification`, jamais
 * dans le code.
 *
 *   npm run test:certification
 */

const PROJECT = process.env.GCLOUD_PROJECT || "demo-certif";
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT});

const {getFirestore} = require("firebase-admin/firestore");
const index = require("../index.js");

const {certificationStatus, requestCertification, onCertificationDecided} =
  index;

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
 * @param {string} code Code attendu.
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

const call = (fn, uid) => fn.run({data: {}, auth: uid ? {uid} : null});

/** @return {Promise<void>} */
async function main() {
  const db = getFirestore();
  await db.doc("users/awa").set({
    displayName: "Awa", accountType: "personal", followersCount: 600,
    verified: false,
  });
  await db.doc("users/bob").set({
    displayName: "Bob", accountType: "personal", followersCount: 600,
    verified: false,
  });
  await db.doc("users/mairie").set({
    displayName: "Mairie", accountType: "structure", followersCount: 9000,
    verified: false,
  });
  // Awa : 700 + 400 J'aime ; Bob : 300.
  await db.doc("posts/a1").set({authorUid: "awa", likesCount: 700});
  await db.doc("posts/a2").set({authorUid: "awa", likesCount: 400});
  await db.doc("posts/b1").set({authorUid: "bob", likesCount: 300});

  console.log("Certification");

  await check("sans document de configuration : indisponible", async () => {
    const s = await call(certificationStatus, "awa");
    expect(s.enabled === false && s.eligible === false, JSON.stringify(s));
    await expectHttpsError(call(requestCertification, "awa"),
        "failed-precondition");
  });

  await db.doc("config/certification").set({
    personal: {enabled: true, minFollowers: 500, minLikes: 1000},
    structure: {enabled: false},
  });

  await check("seuils lus dans Firestore, J'aime additionnés", async () => {
    const s = await call(certificationStatus, "awa");
    expect(s.minFollowers === 500 && s.minLikes === 1000, "seuils");
    expect(s.followers === 600 && s.likes === 1100, `compteurs ${s.likes}`);
    expect(s.eligible === true, "éligible");
  });

  await check("pas assez de J'aime : refus", async () => {
    const s = await call(certificationStatus, "bob");
    expect(s.eligible === false && s.likes === 300, JSON.stringify(s));
    await expectHttpsError(call(requestCertification, "bob"),
        "failed-precondition");
  });

  await check("structure : bientôt disponible", async () => {
    const s = await call(certificationStatus, "mairie");
    expect(s.accountType === "structure" && s.enabled === false, "fermé");
    await expectHttpsError(call(requestCertification, "mairie"),
        "failed-precondition");
  });

  await check("Awa demande : en attente, pas de doublon", async () => {
    const res = await call(requestCertification, "awa");
    expect(res.status === "pending", res.status);
    const r = (await db.doc("certificationRequests/awa").get()).data();
    expect(r.status === "pending" && r.likes === 1100, JSON.stringify(r));
    expect((await db.doc("users/awa").get()).get("verified") === false,
        "pas encore certifiée");
    await expectHttpsError(call(requestCertification, "awa"),
        "already-exists");
  });

  await check("validée dans la console : certifiée et prévenue", async () => {
    const ref = db.doc("certificationRequests/awa");
    const before = (await ref.get()).data();
    await ref.update({status: "approved"});
    const after = (await ref.get()).data();
    await onCertificationDecided.run({
      params: {uid: "awa"},
      data: {
        before: {data: () => before},
        after: {data: () => after, ref},
      },
    });
    expect((await db.doc("users/awa").get()).get("verified") === true,
        "certifiée");
    const notifs = await db.collection("users/awa/notifications")
        .where("type", "==", "certification").get();
    expect(notifs.size === 1, `notification : ${notifs.size}`);
  });

  await check("seuils changés dans Firestore : pris en compte", async () => {
    await db.doc("config/certification").update({
      "personal.minLikes": 200, "personal.autoApprove": true,
    });
    const s = await call(certificationStatus, "bob");
    expect(s.minLikes === 200 && s.eligible === true, JSON.stringify(s));
    const res = await call(requestCertification, "bob");
    expect(res.status === "approved", res.status);
    expect((await db.doc("users/bob").get()).get("verified") === true,
        "validation automatique");
  });

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
