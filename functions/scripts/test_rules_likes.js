/**
 * Vérification des règles Firestore sur les « j'aime », contre l'émulateur.
 *
 * L'enjeu principal : `setLike` incrémente `likesCount` avec
 * `FieldValue.increment`, tandis que la règle exige un écart d'exactement
 * un cran. Si les règles ne résolvaient pas la transformation avant de
 * l'évaluer, *tous* les likes seraient refusés — d'où ce test.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_likes.js"
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
  increment,
  serverTimestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const AUTHOR = "auteur";
const LIKER = "visiteur";
const POST = "post1";

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

  const liker = env.authenticatedContext(LIKER).firestore();
  const other = env.authenticatedContext("intrus").firestore();
  const anon = env.unauthenticatedContext().firestore();

  /**
   * Remet la base dans l'état « un post publié, aucun like ».
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "posts", POST), {
        authorUid: AUTHOR,
        title: "Titre",
        body: "Corps",
        likesCount: 0,
        commentsCount: 0,
        commentsDisabled: false,
        hidden: false,
      });
    });
  }

  console.log("Règles — « j'aime » sur une publication");

  await reset();
  await check("poser son propre like est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(liker, `posts/${POST}/likes/${LIKER}`), {
          uid: LIKER,
          likedAt: serverTimestamp(),
        }),
    );
  });

  await check("le miroir personnel est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(liker, `users/${LIKER}/likes/${POST}`), {
          postId: POST,
          likedAt: serverTimestamp(),
        }),
    );
  });

  await check(
      "increment(1) sur likesCount passe la règle du cran unique",
      async () => {
        await assertSucceeds(
            updateDoc(doc(liker, "posts", POST), {likesCount: increment(1)}),
        );
        // La règle exige un écart d'exactement un cran : on relit pour
        // confirmer que la transformation a bien été résolue à 1, et non
        // laissée intacte ou appliquée deux fois.
        let stored;
        await env.withSecurityRulesDisabled(async (ctx) => {
          const snap = await getDoc(doc(ctx.firestore(), "posts", POST));
          stored = snap.data().likesCount;
        });
        if (stored !== 1) {
          throw new Error(`likesCount vaut ${stored}, attendu 1`);
        }
      },
  );

  await check("increment(-1) au retrait du like passe aussi", async () => {
    await assertSucceeds(
        updateDoc(doc(liker, "posts", POST), {likesCount: increment(-1)}),
    );
  });

  await check("retirer son propre like est autorisé", async () => {
    await assertSucceeds(
        deleteDoc(doc(liker, `posts/${POST}/likes/${LIKER}`)),
    );
  });

  await reset();
  await check("poser le like de quelqu'un d'autre est refusé", async () => {
    await assertFails(
        setDoc(doc(other, `posts/${POST}/likes/${LIKER}`), {
          uid: LIKER,
          likedAt: serverTimestamp(),
        }),
    );
  });

  await check("écrire dans le miroir d'autrui est refusé", async () => {
    await assertFails(
        setDoc(doc(other, `users/${LIKER}/likes/${POST}`), {postId: POST}),
    );
  });

  await check("lire le miroir d'autrui est refusé", async () => {
    await assertFails(getDoc(doc(other, `users/${LIKER}/likes/${POST}`)));
  });

  await check("un like anonyme est refusé", async () => {
    await assertFails(
        setDoc(doc(anon, `posts/${POST}/likes/${LIKER}`), {uid: LIKER}),
    );
  });

  await check("gonfler likesCount de plus d'un cran est refusé", async () => {
    await assertFails(
        updateDoc(doc(other, "posts", POST), {likesCount: increment(50)}),
    );
  });

  await check("écrire un likesCount arbitraire est refusé", async () => {
    await assertFails(
        updateDoc(doc(other, "posts", POST), {likesCount: 9999}),
    );
  });

  await check(
      "modifier le corps du post sous couvert d'un like est refusé",
      async () => {
        await assertFails(
            updateDoc(doc(other, "posts", POST), {
              likesCount: increment(1),
              body: "détourné",
            }),
        );
      },
  );

  await check("un like ne peut pas être modifié, seulement posé ou retiré",
      async () => {
        await env.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), `posts/${POST}/likes/${LIKER}`), {
            uid: LIKER,
          });
        });
        await assertFails(
            updateDoc(doc(liker, `posts/${POST}/likes/${LIKER}`), {uid: "x"}),
        );
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
