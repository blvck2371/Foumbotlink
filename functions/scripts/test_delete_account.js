/**
 * Suppression de compte (`deleteAccount`), contre les émulateurs.
 *
 * Sème un compte complet (profil, sous-collections, publication,
 * commentaire, annonce, statut, empreinte, code de suivi, abonnements
 * croisés, fichiers) puis vérifie que tout disparaît — et que les
 * compteurs des autres comptes sont corrigés.
 *
 *   npm run test:delete-account
 */

// Le SDK Storage ne lit que STORAGE_EMULATOR_HOST (avec le schéma).
if (process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  process.env.STORAGE_EMULATOR_HOST =
    `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`;
}
// emulators:exec ne l'exporte pas toujours : port par défaut de l'émulateur.
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: process.env.GCLOUD_PROJECT,
  storageBucket: `${process.env.GCLOUD_PROJECT}.appspot.com`,
});

const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const {deleteAccount} = require("../index.js");

const ME = "partant";
const FRIEND = "ami";
const FAN = "fan";

let failures = 0;

/**
 * Vérifie une condition en annonçant son résultat.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {boolean} ok Résultat.
 */
function expect(name, ok) {
  if (ok) {
    console.log(`  ✓ ${name}`);
  } else {
    failures++;
    console.error(`  ✗ ${name}`);
  }
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const db = getFirestore();
  const bucket = getStorage().bucket();
  console.log("Suppression de compte");

  await getAuth().createUser({uid: ME});
  const profile = {displayName: "x", verified: false,
    accountType: "personal", followersCount: 0, followingCount: 0};
  await db.doc(`users/${ME}`).set({...profile, followersCount: 1,
    followingCount: 1});
  await db.doc(`users/${FRIEND}`).set({...profile, followersCount: 1});
  await db.doc(`users/${FAN}`).set({...profile, followingCount: 1});
  await db.doc(`users/${ME}/private/contact`).set({phoneNumber: "+237"});
  await db.doc(`users/${ME}/notifications/n1`).set({type: "x"});
  await db.doc(`users/${ME}/following/${FRIEND}`).set({});
  await db.doc(`users/${FRIEND}/followers/${ME}`).set({});
  await db.doc(`users/${FAN}/following/${ME}`).set({});
  await db.doc(`users/${ME}/followers/${FAN}`).set({});
  await db.doc("posts/p1").set({authorUid: ME});
  await db.doc("posts/p2").set({authorUid: FRIEND});
  await db.doc("posts/p2/comments/c1").set({authorUid: ME});
  await db.doc("posts/p2/comments/c2").set({authorUid: FRIEND});
  await db.doc("market/m1").set({sellerUid: ME});
  await db.doc("statuses/s1").set({authorUid: ME});
  await db.doc("phoneDirectory/h1").set({uid: ME});
  await db.doc("trackingCodes/FBT-AAA").set({uid: ME});
  await bucket.file(`profiles/${ME}/avatar.jpg`).save("x");
  await bucket.file(`profiles/${FRIEND}/avatar.jpg`).save("x");

  await deleteAccount.run({auth: {uid: ME}, data: {}});

  const gone = async (path) => !(await db.doc(path).get()).exists;
  expect("le profil disparaît", await gone(`users/${ME}`));
  expect("ses coordonnées privées aussi",
      await gone(`users/${ME}/private/contact`));
  expect("ses notifications aussi",
      await gone(`users/${ME}/notifications/n1`));
  expect("sa publication aussi", await gone("posts/p1"));
  expect("son commentaire chez autrui aussi",
      await gone("posts/p2/comments/c1"));
  expect("le commentaire d'autrui reste", !(await gone("posts/p2/comments/c2")));
  expect("son annonce aussi", await gone("market/m1"));
  expect("son statut aussi", await gone("statuses/s1"));
  expect("son empreinte de téléphone aussi", await gone("phoneDirectory/h1"));
  expect("son code de suivi aussi", await gone("trackingCodes/FBT-AAA"));
  expect("il n'est plus abonné de son ami",
      await gone(`users/${FRIEND}/followers/${ME}`));
  expect("son fan ne le suit plus", await gone(`users/${FAN}/following/${ME}`));
  const friend = (await db.doc(`users/${FRIEND}`).get()).data();
  const fan = (await db.doc(`users/${FAN}`).get()).data();
  expect("le compteur d'abonnés de l'ami est corrigé",
      friend.followersCount === 0);
  expect("le compteur d'abonnements du fan est corrigé",
      fan.followingCount === 0);
  const [mine] = await bucket.file(`profiles/${ME}/avatar.jpg`).exists();
  const [theirs] = await bucket.file(`profiles/${FRIEND}/avatar.jpg`).exists();
  expect("ses fichiers disparaissent", !mine);
  expect("ceux des autres restent", theirs);
  let authGone = false;
  try {
    await getAuth().getUser(ME);
  } catch (err) {
    authGone = err.code === "auth/user-not-found";
  }
  expect("le compte Auth est supprimé", authGone);

  let refused = false;
  try {
    await deleteAccount.run({data: {}});
  } catch (err) {
    refused = err.code === "unauthenticated";
  }
  expect("un appel anonyme est refusé", refused);

  console.log(failures === 0 ?
    "\nLa suppression de compte est complète." :
    `\n${failures} cas en échec.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
