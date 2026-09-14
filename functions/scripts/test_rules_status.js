/**
 * Règles Firestore des statuts : « j'aime » et repartages.
 *
 * Deux enjeux :
 *
 *  1. **Les compteurs.** Vues et « j'aime » sont écrits par des tiers.
 *     Ils doivent bouger d'un cran et pas d'un de plus, sinon n'importe
 *     qui fabrique la popularité d'un statut — et aucun autre champ ne
 *     doit passer dans le même mouvement. Les vues ne redescendent
 *     jamais (on ne « dé-voit » pas), les « j'aime » si.
 *
 *  2. **L'attribution d'un repartage.** Republier le contenu d'un autre
 *     sans le nommer, ce serait le lui prendre : la règle exige que le
 *     repartage dise de qui il vient.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_status.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  getDoc,
  deleteDoc,
  updateDoc,
  increment,
  serverTimestamp,
  Timestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const AUTHOR = "auteur";
const VIEWER = "spectateur";
const STRANGER = "inconnu";
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
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-status",
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
  const stranger = env.authenticatedContext(STRANGER).firestore();
  const anon = env.unauthenticatedContext().firestore();

  /** Échéance valide : dans le futur, à moins de 25 h. */
  const soon = () => Timestamp.fromMillis(Date.now() + 20 * 3600 * 1000);

  /**
   * Remet la base dans l'état « un statut publié, aucune réaction ».
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "statuses", STATUS), {
        authorUid: AUTHOR,
        authorName: "Auteur",
        text: "Bonjour Foumbot",
        backgroundColor: 0xFFEF6C00,
        createdAt: serverTimestamp(),
        expiresAt: soon(),
        viewsCount: 0,
        likesCount: 0,
      });
    });
  }

  console.log("Règles — statuts");

  // --- 1. J'aime -------------------------------------------------------
  await reset();

  await check("un statut n'est pas lisible sans compte", async () => {
    await assertFails(getDoc(doc(anon, "statuses", STATUS)));
  });

  await check("aimer le statut de quelqu'un est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(viewer, `statuses/${STATUS}/likes/${VIEWER}`), {
          likedAt: serverTimestamp(),
        }),
    );
  });

  await check("le miroir personnel est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(viewer, `users/${VIEWER}/statusLikes/${STATUS}`), {
          likedAt: serverTimestamp(),
          authorUid: AUTHOR,
        }),
    );
  });

  await check("ce que j'ai aimé ne regarde que moi", async () => {
    await assertFails(
        getDoc(doc(stranger, `users/${VIEWER}/statusLikes/${STATUS}`)),
    );
  });

  await check("aimer au nom de quelqu'un d'autre est refusé", async () => {
    await assertFails(
        setDoc(doc(stranger, `statuses/${STATUS}/likes/${VIEWER}`), {
          likedAt: serverTimestamp(),
        }),
    );
  });

  await check("l'auteur voit qui a aimé son statut", async () => {
    await assertSucceeds(
        getDoc(doc(author, `statuses/${STATUS}/likes/${VIEWER}`)),
    );
  });

  await check("un tiers ne voit pas qui a aimé", async () => {
    await assertFails(
        getDoc(doc(stranger, `statuses/${STATUS}/likes/${VIEWER}`)),
    );
  });

  await check("un « j'aime » ne se modifie pas", async () => {
    await assertFails(
        updateDoc(doc(viewer, `statuses/${STATUS}/likes/${VIEWER}`), {
          likedAt: serverTimestamp(),
          triche: true,
        }),
    );
  });

  await check("retirer son propre « j'aime » est autorisé", async () => {
    await assertSucceeds(
        deleteDoc(doc(viewer, `statuses/${STATUS}/likes/${VIEWER}`)),
    );
  });

  // --- 2. Compteurs ----------------------------------------------------
  await reset();

  await check("increment(1) sur likesCount est autorisé", async () => {
    await assertSucceeds(
        updateDoc(doc(viewer, "statuses", STATUS), {likesCount: increment(1)}),
    );
  });

  await check("likesCount peut redescendre (retrait)", async () => {
    await assertSucceeds(
        updateDoc(doc(viewer, "statuses", STATUS), {likesCount: increment(-1)}),
    );
  });

  await check("increment(1) sur viewsCount est autorisé", async () => {
    await assertSucceeds(
        updateDoc(doc(viewer, "statuses", STATUS), {viewsCount: increment(1)}),
    );
  });

  await check("viewsCount ne peut pas redescendre", async () => {
    await assertFails(
        updateDoc(doc(viewer, "statuses", STATUS), {viewsCount: increment(-1)}),
    );
  });

  await check("un bond de 100 « j'aime » est refusé", async () => {
    await assertFails(
        updateDoc(doc(viewer, "statuses", STATUS), {
          likesCount: increment(100),
        }),
    );
  });

  await check("un tiers ne peut pas réécrire le texte", async () => {
    await assertFails(
        updateDoc(doc(viewer, "statuses", STATUS), {text: "détourné"}),
    );
  });

  await check(
      "un compteur ne sert pas de cheval de Troie pour un autre champ",
      async () => {
        await assertFails(
            updateDoc(doc(viewer, "statuses", STATUS), {
              likesCount: increment(1),
              text: "détourné",
            }),
        );
      },
  );

  await check("l'auteur reste maître de son statut", async () => {
    await assertSucceeds(
        updateDoc(doc(author, "statuses", STATUS), {text: "corrigé"}),
    );
  });

  // --- 3. Publication et repartage --------------------------------------
  await check("publier avec des compteurs gonflés est refusé", async () => {
    await assertFails(
        setDoc(doc(author, "statuses", "triche"), {
          authorUid: AUTHOR,
          expiresAt: soon(),
          viewsCount: 0,
          likesCount: 500,
        }),
    );
  });

  await check("publier un statut ordinaire passe", async () => {
    await assertSucceeds(
        setDoc(doc(author, "statuses", "neuf"), {
          authorUid: AUTHOR,
          authorName: "Auteur",
          text: "Salut",
          expiresAt: soon(),
          viewsCount: 0,
          likesCount: 0,
        }),
    );
  });

  await check("un statut permanent est refusé", async () => {
    await assertFails(
        setDoc(doc(author, "statuses", "eternel"), {
          authorUid: AUTHOR,
          expiresAt: Timestamp.fromMillis(Date.now() + 40 * 24 * 3600 * 1000),
          viewsCount: 0,
          likesCount: 0,
        }),
    );
  });

  await check(
      "un repartage sans attribution est refusé",
      async () => {
        await assertFails(
            setDoc(doc(viewer, "statuses", "vol"), {
              authorUid: VIEWER,
              text: "Salut",
              expiresAt: soon(),
              viewsCount: 0,
              likesCount: 0,
              repostOfId: STATUS,
              // repostOfAuthorUid manquant : sans lui, la mention
              // « repartagé de … » ne peut pas s'afficher, et le contenu
              // passerait pour celui du repartageur.
            }),
        );
      },
  );

  await check("un repartage qui crédite son auteur passe", async () => {
    await assertSucceeds(
        setDoc(doc(viewer, "statuses", "repartage"), {
          authorUid: VIEWER,
          authorName: "Spectateur",
          text: "Bonjour Foumbot",
          expiresAt: soon(),
          viewsCount: 0,
          likesCount: 0,
          repostOfId: STATUS,
          repostOfAuthorUid: AUTHOR,
          repostOfAuthorName: "Auteur",
        }),
    );
  });

  await check("publier au nom d'un autre reste refusé", async () => {
    await assertFails(
        setDoc(doc(stranger, "statuses", "usurpation"), {
          authorUid: AUTHOR,
          expiresAt: soon(),
          viewsCount: 0,
          likesCount: 0,
        }),
    );
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nToutes les règles des statuts sont conformes." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
