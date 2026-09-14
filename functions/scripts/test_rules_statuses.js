/**
 * Vérification des règles Firestore sur les statuts éphémères, contre
 * l'émulateur.
 *
 * Trois enjeux, chacun capable de casser la fonctionnalité en silence :
 *   1. le compteur de vues est incrémenté par `FieldValue.increment` alors
 *      que la règle exige un écart d'exactement un cran ;
 *   2. la liste des spectateurs ne doit être lisible que par l'auteur ;
 *   3. l'échéance est bornée à 24 h — sans quoi un client bricolé se
 *      donnerait un statut permanent.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_statuses.js"
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
  updateDoc,
  getDoc,
  getDocs,
  collection,
  increment,
  serverTimestamp,
  Timestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const AUTHOR = "auteur";
const VIEWER = "visiteur";
const OTHER = "intrus";
const STATUS = "statut1";

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
 * Une échéance dans [hours] heures.
 *
 * @param {number} hours Nombre d'heures à ajouter à maintenant.
 * @return {Timestamp} L'échéance correspondante.
 */
function inHours(hours) {
  return Timestamp.fromMillis(Date.now() + hours * 3600 * 1000);
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-test",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const author = env.authenticatedContext(AUTHOR).firestore();
  const viewer = env.authenticatedContext(VIEWER).firestore();
  const other = env.authenticatedContext(OTHER).firestore();
  const anon = env.unauthenticatedContext().firestore();

  /**
   * Remet la base dans l'état « un statut publié, aucune vue ».
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "statuses", STATUS), {
        authorUid: AUTHOR,
        authorName: "Alice",
        text: "Bonjour Foumbot",
        backgroundColor: 0xFFEF6C00,
        createdAt: Timestamp.now(),
        expiresAt: inHours(24),
        viewsCount: 0,
      });
    });
  }

  console.log("Règles — statuts éphémères");

  await reset();

  await check("publier son propre statut est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(author, "statuses", "nouveau"), {
          authorUid: AUTHOR,
          authorName: "Alice",
          text: "Coucou",
          backgroundColor: 0xFFEF6C00,
          createdAt: serverTimestamp(),
          expiresAt: inHours(24),
          viewsCount: 0,
        }),
    );
  });

  await check("publier au nom d'un autre est refusé", async () => {
    await assertFails(
        setDoc(doc(other, "statuses", "usurpe"), {
          authorUid: AUTHOR,
          authorName: "Alice",
          text: "Faux",
          createdAt: serverTimestamp(),
          expiresAt: inHours(24),
          viewsCount: 0,
        }),
    );
  });

  await check("un statut ne peut pas naître avec des vues", async () => {
    await assertFails(
        setDoc(doc(author, "statuses", "gonfle"), {
          authorUid: AUTHOR,
          authorName: "Alice",
          text: "Mille vues",
          createdAt: serverTimestamp(),
          expiresAt: inHours(24),
          viewsCount: 1000,
        }),
    );
  });

  await check("une échéance au-delà de 24 h est refusée", async () => {
    await assertFails(
        setDoc(doc(author, "statuses", "permanent"), {
          authorUid: AUTHOR,
          authorName: "Alice",
          text: "Pour toujours",
          createdAt: serverTimestamp(),
          expiresAt: inHours(24 * 365),
          viewsCount: 0,
        }),
    );
  });

  await check("une échéance déjà passée est refusée", async () => {
    await assertFails(
        setDoc(doc(author, "statuses", "mortne"), {
          authorUid: AUTHOR,
          authorName: "Alice",
          text: "Déjà fini",
          createdAt: serverTimestamp(),
          expiresAt: inHours(-1),
          viewsCount: 0,
        }),
    );
  });

  await check("enregistrer sa propre vue est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(viewer, `statuses/${STATUS}/views/${VIEWER}`), {
          viewedAt: serverTimestamp(),
          viewerName: "Bob",
        }),
    );
  });

  await check("enregistrer une vue au nom d'un autre est refusé", async () => {
    await assertFails(
        setDoc(doc(other, `statuses/${STATUS}/views/${VIEWER}`), {
          viewedAt: serverTimestamp(),
          viewerName: "Bob",
        }),
    );
  });

  await check(
      "increment(1) sur viewsCount passe la règle du cran unique",
      async () => {
        await assertSucceeds(
            updateDoc(doc(viewer, "statuses", STATUS), {
              viewsCount: increment(1),
            }),
        );
        // La transformation doit être résolue avant l'évaluation de la
        // règle, sinon toutes les vues seraient refusées — le même piège
        // que sur les « j'aime ».
        let stored;
        await env.withSecurityRulesDisabled(async (ctx) => {
          const snap = await getDoc(doc(ctx.firestore(), "statuses", STATUS));
          stored = snap.data().viewsCount;
        });
        if (stored !== 1) {
          throw new Error(`viewsCount vaut ${stored}, attendu 1`);
        }
      },
  );

  await check("un tiers ne peut pas faire bondir le compteur", async () => {
    await assertFails(
        updateDoc(doc(viewer, "statuses", STATUS), {viewsCount: increment(50)}),
    );
  });

  await check("un tiers ne peut pas réécrire le texte du statut", async () => {
    await assertFails(
        updateDoc(doc(viewer, "statuses", STATUS), {text: "détourné"}),
    );
  });

  await check("l'auteur voit la liste de ses spectateurs", async () => {
    await assertSucceeds(
        getDocs(collection(author, `statuses/${STATUS}/views`)),
    );
  });

  await check("un tiers ne voit pas qui a regardé", async () => {
    await assertFails(getDocs(collection(other, `statuses/${STATUS}/views`)));
  });

  await check("chacun peut relire sa propre vue", async () => {
    await assertSucceeds(
        getDoc(doc(viewer, `statuses/${STATUS}/views/${VIEWER}`)),
    );
  });

  await check("une vue ne se reprend pas", async () => {
    await assertFails(
        deleteDoc(doc(viewer, `statuses/${STATUS}/views/${VIEWER}`)),
    );
  });

  await check("le miroir personnel des statuts vus est privé", async () => {
    await assertSucceeds(
        setDoc(doc(viewer, `users/${VIEWER}/statusViews/${STATUS}`), {
          viewedAt: serverTimestamp(),
        }),
    );
    await assertFails(
        getDoc(doc(other, `users/${VIEWER}/statusViews/${STATUS}`)),
    );
  });

  await check("un visiteur non connecté ne lit aucun statut", async () => {
    await assertFails(getDoc(doc(anon, "statuses", STATUS)));
  });

  await check("seul l'auteur supprime son statut", async () => {
    await assertFails(deleteDoc(doc(viewer, "statuses", STATUS)));
    await assertSucceeds(deleteDoc(doc(author, "statuses", STATUS)));
  });

  await env.cleanup();

  if (failures > 0) {
    console.error(`\n${failures} cas en échec`);
    process.exit(1);
  }
  console.log("\nTous les cas passent");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
