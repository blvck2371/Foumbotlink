/**
 * Changement de nom ou de photo : recopié sur les publications,
 * commentaires, statuts et annonces du compte, et seulement les siens.
 *
 *   npm run test:profile-sync
 */

const PROJECT = process.env.GCLOUD_PROJECT || "demo-profile";
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: PROJECT});

const {getFirestore} = require("firebase-admin/firestore");
const {syncProfileCopies} = require("../index.js");

let failures = 0;

/**
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas.
 */
async function check(name, body) {
  try {
    await body();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures++;
    console.error(`  ✗ ${name}\n    ${err.stack || err.message}`);
  }
}

/**
 * @param {boolean} ok Condition.
 * @param {string} what Ce qui était attendu.
 */
function expect(ok, what) {
  if (!ok) throw new Error(what);
}

/** @return {Promise<void>} */
async function main() {
  const db = getFirestore();
  const awa = {authorUid: "awa", authorName: "Awa", authorPhotoUrl: "https://old"};
  await db.doc("users/awa").set({displayName: "Awa"});
  await db.doc("posts/p1").set({...awa, text: "a"});
  await db.doc("posts/p2").set({authorUid: "bob", authorName: "Bob"});
  await db.doc("posts/p2/comments/c1").set({...awa, text: "c"});
  await db.doc("statuses/s1").set({...awa});
  await db.doc("market/m1").set({sellerUid: "awa", sellerName: "Awa"});
  await db.doc("trackingCodes/ABC").set({uid: "awa", displayName: "Awa"});

  console.log("Profil — recopie du nom et de la photo");

  await check("sans connexion : refus", async () => {
    try {
      await syncProfileCopies.run({data: {}, auth: null});
      throw new Error("refus attendu");
    } catch (err) {
      expect(err.code === "unauthenticated", err.code);
    }
  });

  await check("nouveau nom et nouvelle photo partout, pas chez Bob", async () => {
    await db.doc("users/awa").update({
      displayName: "  Awa Njoya ", photoUrl: "https://new",
    });
    const res = await syncProfileCopies.run({data: {}, auth: {uid: "awa"}});
    expect(res.updated === 5, `5 documents attendus, ${res.updated}`);
    for (const path of ["posts/p1", "posts/p2/comments/c1", "statuses/s1"]) {
      const d = (await db.doc(path).get()).data();
      expect(d.authorName === "Awa Njoya", `${path} : ${d.authorName}`);
      expect(d.authorPhotoUrl === "https://new", `${path} : photo`);
    }
    const m = (await db.doc("market/m1").get()).data();
    expect(m.sellerName === "Awa Njoya", `annonce : ${m.sellerName}`);
    const t = (await db.doc("trackingCodes/ABC").get()).data();
    expect(t.displayName === "Awa Njoya", `code de suivi : ${t.displayName}`);
    const bob = (await db.doc("posts/p2").get()).data();
    expect(bob.authorName === "Bob", "Bob inchangé");
  });

  await check("photo retirée : elle disparaît des copies", async () => {
    await db.doc("users/awa").update({photoUrl: null});
    await syncProfileCopies.run({data: {}, auth: {uid: "awa"}});
    const d = (await db.doc("posts/p1").get()).data();
    expect(!("authorPhotoUrl" in d), "photo encore présente");
  });

  if (failures) {
    console.error(`\n${failures} échec(s)`);
    process.exit(1);
  }
  console.log("\nTout est bon.");
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
