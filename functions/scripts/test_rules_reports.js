/**
 * Règles Firestore des signalements et de la file de modération.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_reports.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const ALICE = "alice";
const BOB = "bob";
const CAROLE = "carole";
const CONV = [ALICE, BOB].sort().join("_");

let failures = 0;

/**
 * Exécute un cas de test en annonçant son résultat.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas lui-même.
 * @return {Promise<void>} Résolue une fois le cas terminé.
 */
async function check(name, body) {
  try {
    await body();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures++;
    console.error(`  ✗ ${name}\n    ${err.message}`);
  }
}

/**
 * Signalement tel que l'écrit ModerationService.report.
 *
 * @param {string} reporter Uid du signaleur.
 * @param {object} over Champs à remplacer.
 * @return {object} Document `reports/{id}`.
 */
function report(reporter, over = {}) {
  return {
    targetType: "message",
    targetId: "m1",
    targetPath: `conversations/${CONV}/messages/m1`,
    targetOwnerUid: BOB,
    reporterUid: reporter,
    reason: "harcelement",
    details: "",
    excerpt: "…",
    status: "pending",
    createdAt: new Date(),
    ...over,
  };
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-reports",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  await env.clearFirestore();

  const alice = env.authenticatedContext(ALICE).firestore();
  const carole = env.authenticatedContext(CAROLE).firestore();

  console.log("Règles — signalements");

  await check("Alice signale un message de sa conversation", async () => {
    await assertSucceeds(setDoc(doc(alice, "reports", "r1"), report(ALICE)));
  });

  await check("Carole ne signale pas un message qu'elle ne peut pas lire",
      async () => {
        await assertFails(setDoc(doc(carole, "reports", "r2"), report(CAROLE)));
      });

  await check("un chemin de message mal formé est refusé", async () => {
    await assertFails(setDoc(doc(alice, "reports", "r3"), report(ALICE, {
      targetPath: `conversations/${CONV}`,
    })));
  });

  await check("Carole signale un statut", async () => {
    await assertSucceeds(setDoc(doc(carole, "reports", "r4"), report(CAROLE, {
      targetType: "status",
      targetPath: "statuses/s1",
      targetId: "s1",
    })));
  });

  await check("Carole signale un profil", async () => {
    await assertSucceeds(setDoc(doc(carole, "reports", "r5"), report(CAROLE, {
      targetType: "user",
      targetPath: `users/${BOB}`,
      targetId: BOB,
    })));
  });

  await check("un type inconnu est refusé", async () => {
    await assertFails(setDoc(doc(carole, "reports", "r6"), report(CAROLE, {
      targetType: "conversation",
      targetPath: `conversations/${CONV}`,
    })));
  });

  await check("un motif inconnu est refusé", async () => {
    await assertFails(setDoc(doc(carole, "reports", "r7"), report(CAROLE, {
      targetType: "status",
      targetPath: "statuses/s1",
      reason: "jeNaimePas",
    })));
  });

  await check("on ne signale pas au nom d'un autre", async () => {
    await assertFails(setDoc(doc(carole, "reports", "r8"), report(ALICE)));
  });

  await check("un signalement n'est pas relisible", async () => {
    await assertFails(getDoc(doc(alice, "reports", "r1")));
  });

  await check("la file de modération est fermée à l'app", async () => {
    await assertFails(getDoc(doc(alice, "moderationQueue", "message_m1")));
    await assertFails(setDoc(doc(alice, "moderationQueue", "x"), {}));
  });

  await env.cleanup();
  console.log(failures === 0 ?
    "\nLes signalements sont bornés." :
    `\n${failures} cas en échec.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
