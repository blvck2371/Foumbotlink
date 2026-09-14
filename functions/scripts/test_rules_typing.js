/**
 * Vérification des règles Firestore sur l'indicateur « en train d'écrire /
 * d'enregistrer » — `conversations/{id}/typing/{uid}`.
 *
 * L'enjeu : ce document est écrit par un participant et affiché tel quel
 * par l'app de l'autre, à la fois dans l'en-tête de la discussion et dans
 * la liste des conversations. Il faut donc garantir qu'un participant ne
 * peut écrire que le sien, qu'un tiers ne peut rien en lire, et que la
 * forme du document reste verrouillée (`state` parmi trois valeurs, aucun
 * champ libre).
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_typing.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  deleteDoc,
  getDoc,
  serverTimestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const ALICE = "alice";
const BOB = "bob";
const INTRUS = "intrus";
const CONV = `${ALICE}_${BOB}`;

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
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-typing",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const alice = env.authenticatedContext(ALICE).firestore();
  const bob = env.authenticatedContext(BOB).firestore();
  const intrus = env.authenticatedContext(INTRUS).firestore();
  const anon = env.unauthenticatedContext().firestore();

  const typingPath = (uid) => `conversations/${CONV}/typing/${uid}`;

  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "conversations", CONV), {
      participants: [ALICE, BOB],
      createdAt: serverTimestamp(),
    });
  });

  console.log("Règles — indicateur « en train d'écrire / d'enregistrer »");

  for (const state of ["typing", "recording", "idle"]) {
    await check(`« ${state} » sur son propre document est autorisé`,
        async () => {
          await assertSucceeds(
              setDoc(doc(alice, typingPath(ALICE)), {
                state,
                updatedAt: serverTimestamp(),
              }),
          );
        });
  }

  await check("l'autre participant peut lire l'indicateur", async () => {
    await assertSucceeds(getDoc(doc(bob, typingPath(ALICE))));
  });

  await check("chacun peut effacer son propre indicateur", async () => {
    await assertSucceeds(deleteDoc(doc(alice, typingPath(ALICE))));
  });

  await check("écrire l'indicateur d'autrui est refusé", async () => {
    await assertFails(
        setDoc(doc(bob, typingPath(ALICE)), {
          state: "typing",
          updatedAt: serverTimestamp(),
        }),
    );
  });

  await check("un tiers ne peut pas lire l'indicateur", async () => {
    await assertFails(getDoc(doc(intrus, typingPath(ALICE))));
  });

  await check("un tiers ne peut pas écrire dans la conversation",
      async () => {
        await assertFails(
            setDoc(doc(intrus, typingPath(INTRUS)), {
              state: "typing",
              updatedAt: serverTimestamp(),
            }),
        );
      });

  await check("un état inconnu est refusé", async () => {
    await assertFails(
        setDoc(doc(alice, typingPath(ALICE)), {
          state: "en_train_de_nimporte_quoi",
          updatedAt: serverTimestamp(),
        }),
    );
  });

  await check("un champ libre en plus de `state` est refusé", async () => {
    await assertFails(
        setDoc(doc(alice, typingPath(ALICE)), {
          state: "typing",
          updatedAt: serverTimestamp(),
          charge: "x".repeat(5000),
        }),
    );
  });

  await check("un indicateur anonyme est refusé", async () => {
    await assertFails(
        setDoc(doc(anon, typingPath(ALICE)), {state: "typing"}),
    );
  });

  await check(
      "l'indicateur d'une conversation dont on n'est pas participant " +
      "est refusé",
      async () => {
        await env.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), "conversations", "autre_conv"), {
            participants: ["x", "y"],
            createdAt: serverTimestamp(),
          });
        });
        await assertFails(
            setDoc(doc(alice, `conversations/autre_conv/typing/${ALICE}`), {
              state: "typing",
              updatedAt: serverTimestamp(),
            }),
        );
      });

  await env.cleanup();

  if (failures > 0) {
    console.error(`\n${failures} cas en échec`);
    process.exit(1);
  }
  console.log("\nTous les cas passent.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
