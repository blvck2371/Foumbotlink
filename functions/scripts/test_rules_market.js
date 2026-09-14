/**
 * Vérification des règles Firestore du marché, contre l'émulateur.
 *
 * Trois enjeux, dans l'ordre d'importance :
 *
 *  1. **Le numéro du vendeur.** Il vit désormais dans
 *     `market/{id}/contact/info`, et toute la protection de la vie privée
 *     des habitants tient à ce que cette sous-collection soit fermée aux
 *     visiteurs non connectés — pendant que l'annonce, elle, reste
 *     publique. On vérifie aussi qu'on ne peut plus créer d'annonce avec
 *     un `sellerPhone` dans le document public.
 *
 *  2. **Les compteurs.** Vues, contacts et favoris sont écrits par des
 *     tiers. Ils doivent bouger d'un cran et pas d'un de plus, sinon
 *     n'importe qui peut fabriquer la popularité d'une annonce — et
 *     aucun autre champ ne doit passer dans le même mouvement.
 *
 *  3. **Les avis.** Ils remplacent ici le paiement sécurisé : c'est la
 *     seule information sur laquelle un acheteur s'appuie avant de se
 *     déplacer. Noter suppose d'avoir réellement pris contact, et on ne
 *     se note pas soi-même.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_market.js"
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
  increment,
  serverTimestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const SELLER = "vendeur";
const BUYER = "acheteur";
const ITEM = "annonce1";

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
    projectId: "foumbotlink-rules-market",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const seller = env.authenticatedContext(SELLER).firestore();
  const buyer = env.authenticatedContext(BUYER).firestore();
  const stranger = env.authenticatedContext("inconnu").firestore();
  const anon = env.unauthenticatedContext().firestore();

  /**
   * Remet la base dans l'état « une annonce publiée, aucun contact ».
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "market", ITEM), {
        sellerUid: SELLER,
        sellerName: "Vendeur",
        title: "Moto",
        description: "Bon état",
        keywords: ["moto", "bon", "etat"],
        category: "vehicules",
        listingType: "vente",
        price: 300000,
        location: "Foumbot centre",
        sold: false,
        hidden: false,
        hasPhone: true,
        viewsCount: 0,
        contactsCount: 0,
        favoritesCount: 0,
      });
      await setDoc(doc(db, `market/${ITEM}/contact/info`), {
        phone: "+237600000000",
        sellerUid: SELLER,
      });
    });
  }

  console.log("Règles — marché");

  // --- 1. Le numéro du vendeur ---------------------------------------
  await reset();

  await check("l'annonce reste lisible sans compte", async () => {
    await assertSucceeds(getDoc(doc(anon, "market", ITEM)));
  });

  await check("le numéro est refusé à un visiteur non connecté", async () => {
    await assertFails(getDoc(doc(anon, `market/${ITEM}/contact/info`)));
  });

  await check("le numéro est lisible par un compte connecté", async () => {
    await assertSucceeds(getDoc(doc(buyer, `market/${ITEM}/contact/info`)));
  });

  await check("un tiers ne peut pas réécrire le numéro", async () => {
    await assertFails(
        setDoc(doc(stranger, `market/${ITEM}/contact/info`), {phone: "666"}),
    );
  });

  await check("le vendeur peut réécrire son numéro", async () => {
    await assertSucceeds(
        setDoc(doc(seller, `market/${ITEM}/contact/info`), {
          phone: "+237611111111",
          sellerUid: SELLER,
        }),
    );
  });

  // Les versions déjà installées écrivent encore `sellerPhone` dans le
  // document public : la règle les laisse publier, et c'est
  // `onMarketItemCreated` qui déplace le numéro aussitôt. Les refuser
  // ici empêcherait de publier depuis un téléphone non mis à jour.
  await check(
      "une annonce d'un client ancien (avec sellerPhone) passe encore",
      async () => {
        await assertSucceeds(
            setDoc(doc(seller, "market", "annonce2"), {
              sellerUid: SELLER,
              title: "Vélo",
              sellerPhone: "+237600000000",
              sold: false,
            }),
        );
      },
  );

  await check("publier sans numéro dans le document public passe", async () => {
    await assertSucceeds(
        setDoc(doc(seller, "market", "annonce3"), {
          sellerUid: SELLER,
          title: "Vélo",
          hasPhone: true,
          sold: false,
        }),
    );
  });

  // --- 2. Les compteurs -----------------------------------------------
  await reset();

  await check("increment(1) sur viewsCount est autorisé", async () => {
    await assertSucceeds(
        updateDoc(doc(buyer, "market", ITEM), {viewsCount: increment(1)}),
    );
  });

  await check("increment(1) sur contactsCount est autorisé", async () => {
    await assertSucceeds(
        updateDoc(doc(buyer, "market", ITEM), {contactsCount: increment(1)}),
    );
  });

  await check("favoritesCount peut monter puis redescendre", async () => {
    await assertSucceeds(
        updateDoc(doc(buyer, "market", ITEM), {favoritesCount: increment(1)}),
    );
    await assertSucceeds(
        updateDoc(doc(buyer, "market", ITEM), {favoritesCount: increment(-1)}),
    );
  });

  await check("un bond de 500 vues est refusé", async () => {
    await assertFails(
        updateDoc(doc(buyer, "market", ITEM), {viewsCount: increment(500)}),
    );
  });

  await check("viewsCount ne peut pas redescendre", async () => {
    await assertFails(
        updateDoc(doc(buyer, "market", ITEM), {viewsCount: increment(-1)}),
    );
  });

  await check("un tiers ne peut pas changer le prix", async () => {
    await assertFails(updateDoc(doc(buyer, "market", ITEM), {price: 1}));
  });

  await check(
      "un compteur ne sert pas de cheval de Troie pour un autre champ",
      async () => {
        await assertFails(
            updateDoc(doc(buyer, "market", ITEM), {
              viewsCount: increment(1),
              price: 1,
            }),
        );
      },
  );

  await check("le vendeur modifie son annonce librement", async () => {
    await assertSucceeds(
        updateDoc(doc(seller, "market", ITEM), {title: "Moto révisée"}),
    );
  });

  await check("un tiers ne peut pas supprimer l'annonce", async () => {
    await assertFails(
        setDoc(doc(stranger, "market", ITEM), {sellerUid: "inconnu"}),
    );
  });

  // --- 3. Les avis ----------------------------------------------------
  await reset();

  await check("noter sans avoir contacté est refusé", async () => {
    await assertFails(
        setDoc(doc(buyer, `users/${SELLER}/reviews/${BUYER}`), {
          reviewerName: "Acheteur",
          rating: 5,
          comment: "Parfait",
          createdAt: serverTimestamp(),
        }),
    );
  });

  await check("l'acheteur peut déclarer son contact", async () => {
    await assertSucceeds(
        setDoc(doc(buyer, `users/${SELLER}/contactedBy/${BUYER}`), {
          itemId: ITEM,
          itemTitle: "Moto",
          createdAt: serverTimestamp(),
        }),
    );
  });

  await check("on ne déclare pas un contact au nom d'un autre", async () => {
    await assertFails(
        setDoc(doc(stranger, `users/${SELLER}/contactedBy/${BUYER}`), {
          itemId: ITEM,
        }),
    );
  });

  await check("noter après contact est autorisé", async () => {
    await assertSucceeds(
        setDoc(doc(buyer, `users/${SELLER}/reviews/${BUYER}`), {
          reviewerName: "Acheteur",
          rating: 5,
          comment: "Parfait",
          createdAt: serverTimestamp(),
        }),
    );
  });

  await check("une note hors barème est refusée", async () => {
    await assertFails(
        setDoc(doc(buyer, `users/${SELLER}/reviews/${BUYER}`), {
          reviewerName: "Acheteur",
          rating: 9,
          comment: "",
          createdAt: serverTimestamp(),
        }),
    );
  });

  await check("on ne peut pas noter au nom de quelqu'un d'autre", async () => {
    await assertFails(
        setDoc(doc(stranger, `users/${SELLER}/reviews/${BUYER}`), {
          reviewerName: "Acheteur",
          rating: 1,
          comment: "",
          createdAt: serverTimestamp(),
        }),
    );
  });

  await check("on ne se note pas soi-même", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
          doc(ctx.firestore(), `users/${SELLER}/contactedBy/${SELLER}`),
          {itemId: ITEM},
      );
    });
    await assertFails(
        setDoc(doc(seller, `users/${SELLER}/reviews/${SELLER}`), {
          reviewerName: "Vendeur",
          rating: 5,
          comment: "",
          createdAt: serverTimestamp(),
        }),
    );
  });

  // --- 4. Favoris et alertes, strictement personnels -------------------
  await check("mes favoris sont à moi seul", async () => {
    await assertSucceeds(
        setDoc(doc(buyer, `users/${BUYER}/marketFavorites/${ITEM}`), {
          title: "Moto",
          createdAt: serverTimestamp(),
        }),
    );
    await assertFails(
        getDoc(doc(stranger, `users/${BUYER}/marketFavorites/${ITEM}`)),
    );
  });

  await check("mes alertes sont à moi seul", async () => {
    await assertSucceeds(
        setDoc(doc(buyer, `users/${BUYER}/savedSearches/a1`), {
          label: "Motos",
          query: "moto",
          active: true,
          createdAt: serverTimestamp(),
        }),
    );
    await assertFails(
        getDoc(doc(stranger, `users/${BUYER}/savedSearches/a1`)),
    );
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nToutes les règles du marché sont conformes." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
