/**
 * Vérifie le rattrapage des annonces contre l'émulateur Firestore.
 *
 * L'enjeu tient en une phrase : une annonce sans `bumpedAt` ne remonte
 * dans **aucune** requête triée. Si le rattrapage se trompe, les
 * annonces déjà publiées disparaissent du marché sans le moindre message
 * d'erreur — personne ne s'en apercevrait avant que les vendeurs ne se
 * plaignent. D'où ce test, qui sème des annonces à l'ancien modèle, les
 * répare, puis vérifie qu'elles ressortent bien de la requête que
 * l'application utilise réellement.
 *
 * On contrôle aussi que le numéro quitte le document public, et que
 * relancer la réparation ne réécrit rien (idempotence).
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_backfill_market.js"
 */

const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  marketKeywords,
  planFor,
  backfillListing,
} = require("../market_backfill");

initializeApp({projectId: "foumbotlink-backfill-test"});
const db = getFirestore();

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
 * Échoue si la condition est fausse.
 *
 * @param {boolean} condition Ce qui doit être vrai.
 * @param {string} message Ce qu'on attendait.
 */
function assert(condition, message) {
  if (!condition) throw new Error(message);
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  console.log("Rattrapage du marché");

  const publishedAt = Timestamp.fromDate(new Date("2026-07-01T10:00:00Z"));

  // Une annonce telle que l'ancienne version de l'app l'écrivait :
  // numéro en clair dans le document public, pas de `bumpedAt`, pas de
  // jetons de recherche, pas de compteurs.
  await db.doc("market/ancienne").set({
    sellerUid: "vendeur",
    sellerName: "Vendeur",
    title: "Moto Véhicule",
    description: "Très bon état",
    category: "vehicules",
    listingType: "vente",
    price: 300000,
    location: "Foumbot centre",
    sellerPhone: "  +237600000000  ",
    createdAt: publishedAt,
    sold: false,
    imageUrls: [],
  });

  // Une annonce déjà au nouveau modèle : elle ne doit pas bouger.
  await db.doc("market/moderne").set({
    sellerUid: "vendeur",
    title: "Vélo",
    description: "",
    keywords: ["velo"],
    createdAt: publishedAt,
    bumpedAt: publishedAt,
    expiresAt: Timestamp.fromDate(new Date("2026-12-31T00:00:00Z")),
    sold: false,
    hidden: false,
    hasPhone: false,
    viewsCount: 7,
    favoritesCount: 2,
    contactsCount: 1,
  });

  await check("une annonce à l'ancien modèle est complétée", async () => {
    const changed = await backfillListing(
        db.doc("market/ancienne"),
        (await db.doc("market/ancienne").get()).data(),
    );
    assert(changed === true, "le rattrapage aurait dû écrire");
  });

  await check("le numéro quitte le document public", async () => {
    const data = (await db.doc("market/ancienne").get()).data();
    assert(data.sellerPhone === undefined,
        "sellerPhone est encore dans le document public");
    assert(data.hasPhone === true, "hasPhone devrait être vrai");

    const contact = await db.doc("market/ancienne/contact/info").get();
    assert(contact.exists, "le document de contact est absent");
    assert(contact.data().phone === "+237600000000",
        `numéro inattendu : ${contact.data().phone}`);
    assert(contact.data().sellerUid === "vendeur",
        "le contact doit porter le vendeur, pour les règles Storage");
  });

  await check("bumpedAt reprend la date de publication", async () => {
    const data = (await db.doc("market/ancienne").get()).data();
    assert(data.bumpedAt.isEqual(publishedAt),
        "bumpedAt devrait valoir createdAt");
  });

  await check("expiresAt tombe 60 jours après la publication", async () => {
    const data = (await db.doc("market/ancienne").get()).data();
    const days = Math.round(
        (data.expiresAt.toMillis() - publishedAt.toMillis()) / 86400000,
    );
    assert(days === 60, `${days} jours au lieu de 60`);
  });

  await check("les jetons de recherche sont posés", async () => {
    const data = (await db.doc("market/ancienne").get()).data();
    assert(
        JSON.stringify(data.keywords) ===
          JSON.stringify(marketKeywords("Moto Véhicule", "Très bon état")),
        `jetons inattendus : ${JSON.stringify(data.keywords)}`,
    );
    assert(data.keywords.includes("vehicule"),
        "l'accent devrait avoir été retiré");
  });

  await check("les compteurs sont initialisés", async () => {
    const data = (await db.doc("market/ancienne").get()).data();
    assert(data.viewsCount === 0 && data.favoritesCount === 0 &&
      data.contactsCount === 0, "compteurs manquants");
    assert(data.hidden === false, "hidden manquant");
  });

  await check(
      "l'annonce réparée ressort de la requête de la grille",
      async () => {
      // C'est *la* requête que fait l'app (MarketService.fetchWindow) :
      // si elle ne remonte pas l'annonce, celle-ci est invisible.
        const snap = await db.collection("market")
            .where("sold", "==", false)
            .orderBy("bumpedAt", "desc")
            .limit(150)
            .get();
        const ids = snap.docs.map((d) => d.id);
        assert(ids.includes("ancienne"),
            `l'annonce réparée est absente de la grille : ${ids}`);
      },
  );

  await check("la recherche par jeton la retrouve", async () => {
    const snap = await db.collection("market")
        .where("keywords", "array-contains", "vehicule")
        .orderBy("bumpedAt", "desc")
        .get();
    assert(snap.docs.some((d) => d.id === "ancienne"),
        "la recherche ne retrouve pas l'annonce réparée");
  });

  await check("relancer le rattrapage ne réécrit rien", async () => {
    const before = (await db.doc("market/ancienne").get()).data();
    const changed = await backfillListing(db.doc("market/ancienne"), before);
    assert(changed === false, "le rattrapage a réécrit une annonce à jour");
  });

  await check("une annonce déjà à jour n'est pas touchée", async () => {
    const data = (await db.doc("market/moderne").get()).data();
    const {update, phone} = planFor(data);
    assert(Object.keys(update).length === 0,
        `champs réécrits à tort : ${Object.keys(update)}`);
    assert(phone === null, "un numéro a été inventé");

    const changed = await backfillListing(db.doc("market/moderne"), data);
    assert(changed === false, "le rattrapage a touché une annonce à jour");

    const after = (await db.doc("market/moderne").get()).data();
    assert(after.viewsCount === 7, "les compteurs ont été écrasés");
  });

  await check("une annonce sans numéro reste sans numéro", async () => {
    await db.doc("market/sansnumero").set({
      sellerUid: "vendeur",
      title: "Chaise",
      description: "",
      createdAt: publishedAt,
    });
    await backfillListing(
        db.doc("market/sansnumero"),
        (await db.doc("market/sansnumero").get()).data(),
    );
    const data = (await db.doc("market/sansnumero").get()).data();
    assert(data.hasPhone === false, "hasPhone devrait être faux");
    const contact = await db.doc("market/sansnumero/contact/info").get();
    assert(!contact.exists, "un document de contact vide a été créé");
  });

  console.log(
      failures === 0 ?
        "\nLe rattrapage se comporte comme attendu." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
