/**
 * Vérification des règles Firestore de l'annuaire, contre l'émulateur.
 *
 *  1. **Le classement.** Il repose sur `rankScore`, recalculé par
 *     `onProReviewWritten`. Un professionnel ne doit pas pouvoir créer sa
 *     fiche avec une note gonflée, ni la retoucher ensuite.
 *  2. **Le numéro.** La fiche est publique, `contact/main` réservé aux
 *     comptes connectés.
 *  3. **Les avis.** Contact préalable obligatoire, pas d'auto-notation,
 *     un avis par personne.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_directory.js"
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
  updateDoc,
  deleteDoc,
  serverTimestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const PRO = "frigoriste";
const CLIENT = "client";

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
 * Fiche telle que l'app la crée (ProListing.toCreateMap).
 *
 * @param {object} overrides Champs à remplacer.
 * @return {object} Document de fiche.
 */
function listing(overrides = {}) {
  return {
    ownerUid: PRO,
    name: "Froid Service",
    category: "frigoriste",
    trade: "Climatisation",
    description: "",
    quartier: "Centre",
    hours: "",
    photoUrl: null,
    updatedAt: serverTimestamp(),
    ratingCount: 0,
    ratingSum: 0,
    ratingAvg: 0,
    rankScore: 3.5,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-directory",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const pro = env.authenticatedContext(PRO).firestore();
  const client = env.authenticatedContext(CLIENT).firestore();
  const anon = env.unauthenticatedContext().firestore();

  /**
   * Base vide puis fiche publiée, sans contact ni avis.
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "directory", PRO), listing());
      await setDoc(doc(db, `directory/${PRO}/contact/main`), {
        phone: "677123456",
        whatsapp: "",
      });
    });
  }

  console.log("Fiches");
  await env.clearFirestore();
  await check("le pro crée sa fiche à la note neutre", async () => {
    await assertSucceeds(setDoc(doc(pro, "directory", PRO), listing()));
  });
  await env.clearFirestore();
  await check("création avec une note gonflée refusée", async () => {
    await assertFails(setDoc(doc(pro, "directory", PRO), listing({
      ratingCount: 50, ratingSum: 250, ratingAvg: 5, rankScore: 5,
    })));
  });
  await check("créer la fiche d'un autre refusé", async () => {
    await assertFails(setDoc(doc(client, "directory", PRO), listing()));
  });

  await reset();
  await check("le pro modifie sa présentation", async () => {
    await assertSucceeds(updateDoc(doc(pro, "directory", PRO), {
      description: "Dépannage frigo et clim", updatedAt: serverTimestamp(),
    }));
  });
  await check("le pro ne peut pas toucher à son score", async () => {
    await assertFails(updateDoc(doc(pro, "directory", PRO), {rankScore: 5}));
  });
  await check("le pro ajoute 3 photos", async () => {
    await assertSucceeds(updateDoc(doc(pro, "directory", PRO), {
      photos: ["https://a/1.jpg", "https://a/2.jpg", "https://a/3.jpg"],
    }));
  });
  await check("une 4e photo est refusée", async () => {
    await assertFails(updateDoc(doc(pro, "directory", PRO), {
      photos: ["1", "2", "3", "4"],
    }));
  });
  await check("un tiers ne modifie pas la fiche", async () => {
    await assertFails(updateDoc(doc(client, "directory", PRO), {name: "X"}));
  });
  await check("fiche lisible sans compte", async () => {
    await assertSucceeds(getDoc(doc(anon, "directory", PRO)));
  });

  console.log("Numéro");
  await check("numéro caché aux visiteurs non connectés", async () => {
    await assertFails(getDoc(doc(anon, `directory/${PRO}/contact/main`)));
  });
  await check("numéro lisible une fois connecté", async () => {
    await assertSucceeds(getDoc(doc(client, `directory/${PRO}/contact/main`)));
  });
  await check("un tiers ne remplace pas le numéro", async () => {
    await assertFails(setDoc(doc(client, `directory/${PRO}/contact/main`), {
      phone: "699000000",
    }));
  });

  console.log("Avis");
  const review = {
    reviewerName: "Client",
    rating: 5,
    comment: "Rapide et efficace",
    createdAt: serverTimestamp(),
  };
  await reset();
  await check("noter sans contact préalable refusé", async () => {
    await assertFails(
        setDoc(doc(client, `directory/${PRO}/reviews/${CLIENT}`), review),
    );
  });
  await check("le client trace son contact", async () => {
    await assertSucceeds(
        setDoc(doc(client, `directory/${PRO}/contactedBy/${CLIENT}`), {
          channel: "call", at: serverTimestamp(),
        }),
    );
  });
  await check("après contact, le client note", async () => {
    await assertSucceeds(
        setDoc(doc(client, `directory/${PRO}/reviews/${CLIENT}`), review),
    );
  });
  await check("note hors 1–5 refusée", async () => {
    await assertFails(
        setDoc(doc(client, `directory/${PRO}/reviews/${CLIENT}`),
            {...review, rating: 6}),
    );
  });
  await check("avis au nom d'un autre refusé", async () => {
    await assertFails(
        setDoc(doc(client, `directory/${PRO}/reviews/autre`), review),
    );
  });
  await check("le pro ne se trace pas un contact à lui-même", async () => {
    await assertFails(
        setDoc(doc(pro, `directory/${PRO}/contactedBy/${PRO}`), {
          channel: "call",
        }),
    );
  });
  await check("le pro ne se note pas", async () => {
    await assertFails(
        setDoc(doc(pro, `directory/${PRO}/reviews/${PRO}`), review),
    );
  });
  await check("le client retire son avis", async () => {
    await assertSucceeds(
        deleteDoc(doc(client, `directory/${PRO}/reviews/${CLIENT}`)),
    );
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nToutes les règles de l'annuaire sont conformes." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
