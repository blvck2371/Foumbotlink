/**
 * Règles Firestore des compteurs écrits par des tiers : abonnés d'un
 * profil, commentaires d'une publication.
 *
 * Un compteur visible (« 1 200 abonnés ») est une promesse faite au
 * lecteur. Sans borne, n'importe quel compte connecté pouvait y inscrire
 * un nombre arbitraire. On vérifie ici que :
 *
 *  1. `followersCount` ne bouge que d'un cran, et seulement dans la même
 *     écriture que l'abonnement (`followers/{moi}`) qui le justifie ;
 *  2. un profil naît à zéro abonné ;
 *  3. `commentsCount` ne bouge que d'un cran et ne passe pas sous zéro.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_counters.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  updateDoc,
  writeBatch,
  increment,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const ALICE = "alice";
const BOB = "bob";
const NEWCOMER = "nouveau";
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
    projectId: "foumbotlink-rules-counters",
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
  const newcomer = env.authenticatedContext(NEWCOMER).firestore();

  /**
   * Sème deux profils et une publication de Bob.
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const profile = {
        accountType: "personal",
        verified: false,
        displayName: "Compte",
        createdAt: new Date().toISOString(),
        followersCount: 0,
        followingCount: 0,
      };
      await setDoc(doc(db, "users", ALICE), profile);
      await setDoc(doc(db, "users", BOB), profile);
      await setDoc(doc(db, "posts", POST), {
        authorUid: BOB,
        likesCount: 0,
        commentsCount: 0,
      });
    });
  }

  /**
   * Abonne (ou désabonne) Alice à Bob, comme follow_service.dart.
   *
   * @param {number} step +1 pour suivre, −1 pour ne plus suivre.
   * @param {number=} followersStep Cran écrit sur le compteur de Bob.
   * @return {Promise<void>} Résolue une fois le batch validé.
   */
  function follow(step, followersStep = step) {
    const batch = writeBatch(alice);
    const following = doc(alice, "users", ALICE, "following", BOB);
    const follower = doc(alice, "users", BOB, "followers", ALICE);
    if (step > 0) {
      batch.set(following, {followedAt: new Date()});
      batch.set(follower, {followedAt: new Date()});
    } else {
      batch.delete(following);
      batch.delete(follower);
    }
    batch.set(doc(alice, "users", ALICE),
        {followingCount: increment(step)}, {merge: true});
    batch.set(doc(alice, "users", BOB),
        {followersCount: increment(followersStep)}, {merge: true});
    return batch.commit();
  }

  console.log("Règles — compteurs (abonnés, commentaires)");

  // --- 1. Abonnés ---------------------------------------------------------
  await reset();

  await check("suivre quelqu'un incrémente son compteur", async () => {
    await assertSucceeds(follow(1));
  });

  await check("ne plus le suivre le décrémente", async () => {
    await assertSucceeds(follow(-1));
  });

  await check("on ne gonfle pas le compteur de plusieurs crans", async () => {
    await assertFails(follow(1, 50));
  });

  await check("on ne gonfle pas le compteur sans s'abonner", async () => {
    await assertFails(
        updateDoc(doc(alice, "users", BOB), {followersCount: increment(1)}),
    );
  });

  await check("on n'écrit pas un nombre arbitraire chez autrui", async () => {
    await assertFails(
        updateDoc(doc(alice, "users", BOB), {followersCount: 100000}),
    );
  });

  await check("ni sur son propre profil", async () => {
    await assertFails(
        updateDoc(doc(bob, "users", BOB), {followersCount: 100000}),
    );
    await assertFails(
        updateDoc(doc(bob, "users", BOB), {followingCount: 100000}),
    );
  });

  await check("le propriétaire modifie toujours son profil", async () => {
    await assertSucceeds(
        updateDoc(doc(bob, "users", BOB), {photoUrl: "https://x/y.png"}),
    );
  });

  await check("un profil naît à zéro abonné", async () => {
    const base = {
      accountType: "personal",
      verified: false,
      displayName: "Nouveau",
      createdAt: new Date().toISOString(),
    };
    await assertFails(setDoc(doc(newcomer, "users", NEWCOMER),
        {...base, followersCount: 5000, followingCount: 0}));
    await assertSucceeds(setDoc(doc(newcomer, "users", NEWCOMER),
        {...base, followersCount: 0, followingCount: 0}));
  });

  // --- 2. Commentaires ----------------------------------------------------
  await reset();

  await check("un commentaire incrémente le compteur", async () => {
    await assertSucceeds(
        updateDoc(doc(alice, "posts", POST), {commentsCount: increment(1)}),
    );
  });

  await check("sa suppression le décrémente", async () => {
    await assertSucceeds(
        updateDoc(doc(alice, "posts", POST), {commentsCount: 0}),
    );
  });

  await check("on n'écrit pas un nombre arbitraire", async () => {
    await assertFails(
        updateDoc(doc(alice, "posts", POST), {commentsCount: 9999}),
    );
  });

  await check("le compteur ne passe pas sous zéro", async () => {
    await assertFails(
        updateDoc(doc(alice, "posts", POST), {commentsCount: -1}),
    );
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nTous les compteurs sont bornés." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
