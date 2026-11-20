/**
 * Règles Firestore du blocage.
 *
 * Alice a bloqué Bob. Carole n'a bloqué personne. On vérifie que, dans un
 * sens comme dans l'autre, Alice et Bob ne peuvent plus échanger
 * (messages, conversation, appels, commentaires, abonnements, avis),
 * alors que Carole le peut toujours — et que personne n'écrit dans une
 * conversation dont il ne fait pas partie.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_blocking.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  writeBatch,
  increment,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const ALICE = "alice";
const BOB = "bob";
const CAROLE = "carole";
const POST = "postAlice";

/**
 * Id de conversation, comme Conversation.buildId.
 *
 * @param {string} a Premier uid.
 * @param {string} b Second uid.
 * @return {string} `uidA_uidB`, uids triés.
 */
function convId(a, b) {
  return [a, b].sort().join("_");
}

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
    projectId: "foumbotlink-rules-blocking",
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
  const carole = env.authenticatedContext(CAROLE).firestore();

  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const profile = {
      accountType: "personal",
      verified: false,
      displayName: "Compte",
      followersCount: 0,
      followingCount: 0,
    };
    for (const uid of [ALICE, BOB, CAROLE]) {
      await setDoc(doc(db, "users", uid), profile);
    }
    // Alice bloque Bob ; le serveur pose le miroir.
    await setDoc(doc(db, "users", ALICE, "blocked", BOB), {displayName: "Bob"});
    await setDoc(doc(db, "users", BOB, "blockedBy", ALICE), {});
    // Une conversation existait avant le blocage.
    await setDoc(doc(db, "conversations", convId(ALICE, BOB)), {
      participants: [ALICE, BOB],
      unreadCounts: {[ALICE]: 2},
    });
    await setDoc(doc(db, "conversations", convId(ALICE, CAROLE)), {
      participants: [ALICE, CAROLE],
    });
    await setDoc(doc(db, "posts", POST), {
      authorUid: ALICE,
      likesCount: 0,
      commentsCount: 0,
    });
    // Bob et Carole ont tous deux contacté Alice au marché.
    await setDoc(doc(db, "users", ALICE, "contactedBy", BOB), {});
    await setDoc(doc(db, "users", ALICE, "contactedBy", CAROLE), {});
  });

  const message = (sender) => ({
    senderUid: sender,
    type: "text",
    content: "Bonjour",
    createdAt: new Date(),
  });

  console.log("Règles — blocage");

  // --- Messages -------------------------------------------------------------
  await check("Bob (bloqué) ne peut plus écrire à Alice", async () => {
    await assertFails(setDoc(
        doc(bob, "conversations", convId(ALICE, BOB), "messages", "m1"),
        message(BOB)));
  });

  await check("Alice (qui bloque) ne peut plus écrire à Bob", async () => {
    await assertFails(setDoc(
        doc(alice, "conversations", convId(ALICE, BOB), "messages", "m2"),
        message(ALICE)));
  });

  await check("Carole écrit toujours à Alice", async () => {
    await assertSucceeds(setDoc(
        doc(carole, "conversations", convId(ALICE, CAROLE), "messages", "m3"),
        message(CAROLE)));
  });

  await check("un tiers n'écrit pas dans la conversation des autres",
      async () => {
        await assertFails(setDoc(
            doc(carole, "conversations", convId(ALICE, BOB), "messages", "m4"),
            message(CAROLE)));
      });

  await check("premier message avant que la conversation existe", async () => {
    await assertSucceeds(setDoc(
        doc(carole, "conversations", convId(BOB, CAROLE), "messages", "m5"),
        message(CAROLE)));
  });

  // --- Conversations --------------------------------------------------------
  await env.withSecurityRulesDisabled(async (ctx) => {
    // Repartir d'une conversation Bob–Carole absente.
    const {deleteDoc} = require("firebase/firestore");
    await deleteDoc(doc(ctx.firestore(), "conversations", convId(BOB, CAROLE)));
  });

  await check("Bob ne recrée pas de conversation avec Alice", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const {deleteDoc} = require("firebase/firestore");
      await deleteDoc(
          doc(ctx.firestore(), "conversations", convId(ALICE, BOB)));
    });
    await assertFails(setDoc(doc(bob, "conversations", convId(ALICE, BOB)), {
      participants: [BOB, ALICE],
    }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "conversations", convId(ALICE, BOB)), {
        participants: [ALICE, BOB],
        unreadCounts: {[ALICE]: 2},
      });
    });
  });

  await check("Bob et Carole ouvrent une conversation", async () => {
    await assertSucceeds(setDoc(doc(bob, "conversations", convId(BOB, CAROLE)), {
      participants: [BOB, CAROLE],
    }));
  });

  await check("une conversation dont l'id ne correspond pas est refusée",
      async () => {
        await assertFails(setDoc(doc(carole, "conversations", "faux_id"), {
          participants: [CAROLE, BOB],
        }));
      });

  await check("Bob ne réécrit pas l'aperçu chez Alice", async () => {
    await assertFails(updateDoc(
        doc(bob, "conversations", convId(ALICE, BOB)),
        {lastMessage: "…", lastMessageSenderUid: BOB}));
  });

  await check("Alice remet quand même son badge à zéro", async () => {
    await assertSucceeds(updateDoc(
        doc(alice, "conversations", convId(ALICE, BOB)),
        {[`unreadCounts.${ALICE}`]: 0}));
  });

  // --- Appels ---------------------------------------------------------------
  const call = (caller, callee) => ({
    callerUid: caller,
    calleeUid: callee,
    status: "ringing",
    type: "audio",
    conversationId: convId(caller, callee),
  });

  await check("Bob ne peut pas appeler Alice", async () => {
    await assertFails(setDoc(doc(bob, "calls", "c1"), call(BOB, ALICE)));
  });

  await check("Alice ne peut pas appeler Bob", async () => {
    await assertFails(setDoc(doc(alice, "calls", "c2"), call(ALICE, BOB)));
  });

  await check("Carole appelle Alice", async () => {
    await assertSucceeds(setDoc(doc(carole, "calls", "c3"), call(CAROLE, ALICE)));
  });

  // --- Commentaires ---------------------------------------------------------
  const comment = (author) => ({authorUid: author, text: "Super", likesCount: 0});

  await check("Bob ne commente pas les publications d'Alice", async () => {
    await assertFails(setDoc(
        doc(bob, "posts", POST, "comments", "k1"), comment(BOB)));
  });

  await check("Carole commente les publications d'Alice", async () => {
    await assertSucceeds(setDoc(
        doc(carole, "posts", POST, "comments", "k2"), comment(CAROLE)));
  });

  // --- Abonnements ----------------------------------------------------------
  /**
   * Abonne `fromUid` à `toUid`, comme follow_service.dart.
   *
   * @param {object} db Client Firestore de l'abonné.
   * @param {string} fromUid Abonné.
   * @param {string} toUid Compte suivi.
   * @return {Promise<void>} Résolue une fois le batch validé.
   */
  function follow(db, fromUid, toUid) {
    const batch = writeBatch(db);
    batch.set(doc(db, "users", fromUid, "following", toUid),
        {followedAt: new Date()});
    batch.set(doc(db, "users", toUid, "followers", fromUid),
        {followedAt: new Date()});
    batch.set(doc(db, "users", fromUid),
        {followingCount: increment(1)}, {merge: true});
    batch.set(doc(db, "users", toUid),
        {followersCount: increment(1)}, {merge: true});
    return batch.commit();
  }

  await check("Bob ne peut pas suivre Alice", async () => {
    await assertFails(follow(bob, BOB, ALICE));
  });

  await check("Alice ne peut pas suivre Bob", async () => {
    await assertFails(follow(alice, ALICE, BOB));
  });

  await check("Carole suit Alice", async () => {
    await assertSucceeds(follow(carole, CAROLE, ALICE));
  });

  // --- Avis vendeur ---------------------------------------------------------
  const review = {rating: 1, comment: "Mauvais"};

  await check("Bob ne laisse pas d'avis à Alice", async () => {
    await assertFails(setDoc(doc(bob, "users", ALICE, "reviews", BOB), review));
  });

  await check("Carole laisse un avis à Alice", async () => {
    await assertSucceeds(
        setDoc(doc(carole, "users", ALICE, "reviews", CAROLE), review));
  });

  // --- Miroir blockedBy -----------------------------------------------------
  await check("Bob lit qui l'a bloqué", async () => {
    await assertSucceeds(getDoc(doc(bob, "users", BOB, "blockedBy", ALICE)));
  });

  await check("personne d'autre ne lit ce miroir", async () => {
    await assertFails(getDoc(doc(carole, "users", BOB, "blockedBy", ALICE)));
  });

  await check("personne n'écrit dans ce miroir", async () => {
    await assertFails(setDoc(doc(bob, "users", BOB, "blockedBy", CAROLE), {}));
    await assertFails(setDoc(doc(carole, "users", BOB, "blockedBy", CAROLE), {}));
  });

  await check("la liste de blocage reste privée", async () => {
    await assertFails(getDoc(doc(bob, "users", ALICE, "blocked", BOB)));
  });

  // --- Déblocage ------------------------------------------------------------
  await check("après déblocage, Bob peut de nouveau écrire", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const {deleteDoc} = require("firebase/firestore");
      await deleteDoc(doc(ctx.firestore(), "users", ALICE, "blocked", BOB));
    });
    await assertSucceeds(setDoc(
        doc(bob, "conversations", convId(ALICE, BOB), "messages", "m6"),
        message(BOB)));
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nLe blocage est appliqué côté serveur." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
