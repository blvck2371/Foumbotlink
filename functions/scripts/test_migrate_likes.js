/**
 * Vérifie `migrate_likes.js` contre l'émulateur Firestore : on sème des
 * posts à l'ancien modèle (`likedBy[]`), on lance la migration, puis on
 * contrôle le résultat — y compris son idempotence, puisque le script est
 * fait pour être relançable.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_migrate_likes.js"
 */

const {execFileSync} = require("child_process");
const path = require("path");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-migration";

initializeApp({projectId: process.env.GCLOUD_PROJECT});
const db = getFirestore();

let failures = 0;

/**
 * Compare une valeur à celle attendue.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {*} actual Valeur obtenue.
 * @param {*} expected Valeur attendue.
 */
function expect(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    console.log(`  ✓ ${name}`);
  } else {
    failures++;
    console.error(
        `  ✗ ${name}\n    obtenu ${JSON.stringify(actual)}, ` +
      `attendu ${JSON.stringify(expected)}`,
    );
  }
}

/**
 * Sème l'état d'avant migration.
 *
 * @return {Promise<void>} Résolue une fois la base peuplée.
 */
async function seed() {
  const batch = db.batch();

  // Cas courant : trois personnes ont aimé.
  batch.set(db.doc("posts/p1"), {
    authorUid: "auteur",
    title: "Trois likes",
    likedBy: ["a", "b", "c"],
    likesCount: 3,
    publishedAt: new Date("2026-01-01T10:00:00Z"),
  });

  // Compteur déjà faux, et un uid en double dans le tableau — exactement
  // ce que l'ancien modèle laissait passer.
  batch.set(db.doc("posts/p2"), {
    authorUid: "auteur",
    title: "Compteur faux",
    likedBy: ["a", "a", "b"],
    likesCount: 7,
    publishedAt: new Date("2026-01-02T10:00:00Z"),
  });

  // Aucun like : le tableau est vide mais présent.
  batch.set(db.doc("posts/p3"), {
    authorUid: "auteur",
    title: "Aucun like",
    likedBy: [],
    likesCount: 0,
    publishedAt: new Date("2026-01-03T10:00:00Z"),
  });

  // Post déjà au nouveau modèle : le script ne doit pas y toucher.
  batch.set(db.doc("posts/p4"), {
    authorUid: "auteur",
    title: "Déjà migré",
    likesCount: 1,
    publishedAt: new Date("2026-01-04T10:00:00Z"),
  });
  batch.set(db.doc("posts/p4/likes/z"), {uid: "z", likedAt: new Date()});
  batch.set(db.doc("users/z/likes/p4"), {postId: "p4", likedAt: new Date()});

  await batch.commit();
}

/**
 * Lance le script de migration dans un processus séparé.
 *
 * @param {string[]} extraArgs Arguments supplémentaires.
 * @return {string} Sortie standard du script.
 */
function runMigration(extraArgs = []) {
  return execFileSync(
      process.execPath,
      [path.join(__dirname, "migrate_likes.js"), ...extraArgs],
      {encoding: "utf8", env: process.env},
  );
}

/**
 * Les uids ayant aimé un post, triés.
 *
 * @param {string} postId Publication.
 * @return {Promise<string[]>} Identifiants des documents de like.
 */
async function likersOf(postId) {
  const snap = await db.collection(`posts/${postId}/likes`).get();
  return snap.docs.map((d) => d.id).sort();
}

/**
 * Les posts aimés par une personne, triés.
 *
 * @param {string} uid Personne.
 * @return {Promise<string[]>} Identifiants des posts du miroir.
 */
async function mirrorOf(uid) {
  const snap = await db.collection(`users/${uid}/likes`).get();
  return snap.docs.map((d) => d.id).sort();
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  await seed();

  console.log("Migration — essai à blanc");
  runMigration(["--dry-run"]);
  expect(
      "l'essai à blanc n'écrit rien",
      (await db.doc("posts/p1").get()).get("likedBy"),
      ["a", "b", "c"],
  );
  expect("l'essai à blanc ne crée aucun like", await likersOf("p1"), []);

  console.log("\nMigration");
  runMigration();

  expect("les likes deviennent des documents", await likersOf("p1"),
      ["a", "b", "c"]);
  expect("le miroir personnel est écrit", await mirrorOf("a"), ["p1", "p2"]);
  expect(
      "le champ likedBy disparaît",
      (await db.doc("posts/p1").get()).get("likedBy"),
      undefined,
  );
  expect(
      "likesCount reste juste",
      (await db.doc("posts/p1").get()).get("likesCount"),
      3,
  );
  expect("les doublons sont dédoublonnés", await likersOf("p2"), ["a", "b"]);
  expect(
      "un compteur faux est réaligné sur les likes réels",
      (await db.doc("posts/p2").get()).get("likesCount"),
      2,
  );
  expect("un post sans like ne crée rien", await likersOf("p3"), []);
  expect(
      "un post sans like perd quand même likedBy",
      (await db.doc("posts/p3").get()).get("likedBy"),
      undefined,
  );
  expect("un post déjà migré est laissé tel quel", await likersOf("p4"), ["z"]);
  expect(
      "la date du like reprend celle de la publication",
      (await db.doc("posts/p1/likes/a").get()).get("likedAt").toDate()
          .toISOString(),
      "2026-01-01T10:00:00.000Z",
  );

  console.log("\nMigration relancée (idempotence)");
  runMigration();
  expect("aucun like dupliqué", await likersOf("p1"), ["a", "b", "c"]);
  expect(
      "le compteur ne bouge plus",
      (await db.doc("posts/p1").get()).get("likesCount"),
      3,
  );

  console.log("\nRecomptage");
  await db.doc("posts/p1").update({likesCount: 99});
  runMigration(["--recount"]);
  expect(
      "une dérive du compteur est réparée",
      (await db.doc("posts/p1").get()).get("likesCount"),
      3,
  );

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
