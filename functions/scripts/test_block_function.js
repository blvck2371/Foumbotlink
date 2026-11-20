/**
 * Trigger `onBlockWritten` : miroir `blockedBy` et rupture des
 * abonnements dans les deux sens.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_block_function.js"
 */

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: process.env.GCLOUD_PROJECT,
});

const {getFirestore} = require("firebase-admin/firestore");
const {onBlockWritten} = require("../index.js");

const ALICE = "alice";
const BOB = "bob";
const CAROLE = "carole";

let failures = 0;

/**
 * Annonce le résultat d'une vérification.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {boolean} ok Résultat.
 */
function expect(name, ok) {
  if (ok) {
    console.log(`  ✓ ${name}`);
  } else {
    failures++;
    console.error(`  ✗ ${name}`);
  }
}

/**
 * Simule l'événement Firestore d'une écriture de `blocked`.
 *
 * @param {boolean} before Le document existait avant.
 * @param {boolean} after Le document existe après.
 * @return {Promise<void>} Résolue après exécution du trigger.
 */
function fire(before, after) {
  return onBlockWritten.run({
    params: {uid: ALICE, blockedUid: BOB},
    data: {before: {exists: before}, after: {exists: after}},
  });
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const db = getFirestore();
  console.log("Blocage — trigger serveur");

  const users = {
    [ALICE]: {followersCount: 1, followingCount: 2},
    [BOB]: {followersCount: 1, followingCount: 1},
    [CAROLE]: {followersCount: 1, followingCount: 0},
  };
  for (const [uid, data] of Object.entries(users)) {
    await db.doc(`users/${uid}`).set(data);
  }
  // Alice suit Bob et Carole ; Bob suit Alice.
  const edge = (from, to) => Promise.all([
    db.doc(`users/${from}/following/${to}`).set({}),
    db.doc(`users/${to}/followers/${from}`).set({}),
  ]);
  await edge(ALICE, BOB);
  await edge(ALICE, CAROLE);
  await edge(BOB, ALICE);

  await db.doc(`users/${ALICE}/blocked/${BOB}`).set({});
  await fire(false, true);

  const exists = async (p) => (await db.doc(p).get()).exists;
  const count = async (uid, f) => (await db.doc(`users/${uid}`).get()).get(f);

  expect("le miroir blockedBy est posé",
      await exists(`users/${BOB}/blockedBy/${ALICE}`));
  expect("Alice ne suit plus Bob",
      !(await exists(`users/${ALICE}/following/${BOB}`)) &&
      !(await exists(`users/${BOB}/followers/${ALICE}`)));
  expect("Bob ne suit plus Alice",
      !(await exists(`users/${BOB}/following/${ALICE}`)) &&
      !(await exists(`users/${ALICE}/followers/${BOB}`)));
  expect("Alice suit toujours Carole",
      await exists(`users/${ALICE}/following/${CAROLE}`));
  expect("compteurs d'Alice : 0 abonné, 1 abonnement",
      (await count(ALICE, "followersCount")) === 0 &&
      (await count(ALICE, "followingCount")) === 1);
  expect("compteurs de Bob : 0 abonné, 0 abonnement",
      (await count(BOB, "followersCount")) === 0 &&
      (await count(BOB, "followingCount")) === 0);

  await fire(true, true);
  expect("une réécriture ne touche plus aux compteurs",
      (await count(ALICE, "followingCount")) === 1);

  await db.doc(`users/${ALICE}/blocked/${BOB}`).delete();
  await fire(true, false);
  expect("le déblocage retire le miroir",
      !(await exists(`users/${BOB}/blockedBy/${ALICE}`)));

  console.log(failures === 0 ? "\nTrigger conforme." :
    `\n${failures} vérification(s) en échec.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
