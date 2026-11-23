/**
 * Crée `config/certification` s'il n'existe pas encore (ne remplace
 * jamais un document déjà réglé depuis la console).
 *
 *   node scripts/seed_certification_config.js
 *
 * Les seuils se changent ensuite dans la console Firestore, sans
 * republier l'app ni les fonctions.
 */
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "foumbotlink"});
const ref = getFirestore().doc("config/certification");

ref.create({
  personal: {enabled: true, minFollowers: 500, minLikes: 1000,
    autoApprove: false},
  structure: {enabled: false, minFollowers: 0, minLikes: 0,
    autoApprove: false},
}).then(() => {
  console.log("config/certification créé.");
}).catch((err) => {
  if (err.code === 6) {
    console.log("config/certification existe déjà : inchangé.");
    return;
  }
  console.error(err);
  process.exitCode = 1;
});
