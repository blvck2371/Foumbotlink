/**
 * Trigger `onReportCreated` : file de modération, preuve conservée,
 * priorités et masquage automatique.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_report_function.js"
 */

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: process.env.GCLOUD_PROJECT,
});

const {getFirestore} = require("firebase-admin/firestore");
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
const {getAuth} = require("firebase-admin/auth");
const {onReportCreated, moderate} = require("../index.js");

let failures = 0;

/**
 * Annonce le résultat d'une vérification.
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
 * Écrit un signalement et exécute le trigger dessus.
 *
 * @param {object} db Firestore admin.
 * @param {string} reporter Uid du signaleur.
 * @param {object} fields Type, chemin, motif…
 * @return {Promise<void>} Résolue après le trigger.
 */
async function fileReport(db, reporter, fields) {
  const id = `${fields.targetType}_${fields.targetPath.split("/").pop()}_${reporter}`;
  const data = {
    reporterUid: reporter,
    reason: "harcelement",
    excerpt: "aperçu",
    targetOwnerUid: "menteur",
    status: "pending",
    ...fields,
  };
  await db.doc(`reports/${id}`).set(data);
  await onReportCreated.run({
    params: {reportId: id},
    data: {id, data: () => data},
  });
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const db = getFirestore();
  const queue = async (id) => (await db.doc(`moderationQueue/${id}`).get());
  console.log("Signalements — trigger serveur");

  // --- Publication : masquée au 5e signalement --------------------------
  await db.doc("posts/p1").set({authorUid: "auteur", body: "Texte"});
  for (let i = 1; i <= 4; i++) {
    await fileReport(db, `r${i}`, {targetType: "post", targetPath: "posts/p1"});
  }
  let post = (await db.doc("posts/p1").get()).data();
  expect("4 signalements : publication visible",
      post.reportsCount === 4 && post.hidden !== true);
  await fileReport(db, "r5", {targetType: "post", targetPath: "posts/p1"});
  post = (await db.doc("posts/p1").get()).data();
  const qp = await queue("post_p1");
  expect("5e signalement : publication masquée", post.hidden === true);
  expect("dossier en priorité haute, 5 signalements",
      qp.get("priority") === "high" && qp.get("reportsCount") === 5);
  expect("auteur lu dans le contenu, pas chez le signaleur",
      qp.get("targetOwnerUid") === "auteur");
  expect("motifs comptés", qp.get("reasons.harcelement") === 5);

  // --- Message : preuve conservée, jamais masqué -------------------------
  const msgPath = "conversations/a_b/messages/m1";
  await db.doc(msgPath).set({senderUid: "b", type: "text", content: "Menace"});
  await fileReport(db, "a", {targetType: "message", targetPath: msgPath});
  await db.doc(msgPath).update({content: "", deleted: true});
  const qm = await queue("message_m1");
  expect("le message est recopié par le serveur",
      qm.get("snapshot.content") === "Menace");
  expect("la copie survit à la suppression du message",
      (await queue("message_m1")).get("snapshot.content") === "Menace");
  const msg = (await db.doc(msgPath).get()).data();
  expect("un message n'est ni compté ni masqué",
      msg.reportsCount === undefined && msg.hidden === undefined);
  expect("un message signalé pour harcèlement reste en priorité normale",
      qm.get("priority") === "normal");

  // --- Profil : priorité au 3e signalement --------------------------------
  await db.doc("users/u1").set({displayName: "Profil"});
  await fileReport(db, "x1", {targetType: "user", targetPath: "users/u1"});
  await fileReport(db, "x2", {targetType: "user", targetPath: "users/u1"});
  expect("2 signalements de profil : priorité normale",
      (await queue("user_u1")).get("priority") === "normal");
  await fileReport(db, "x3", {targetType: "user", targetPath: "users/u1"});
  const qu = await queue("user_u1");
  expect("3e signalement de profil : priorité haute",
      qu.get("priority") === "high");
  const user = (await db.doc("users/u1").get()).data();
  expect("le profil n'est pas modifié (décision humaine)",
      user.reportsCount === undefined && user.hidden === undefined);
  expect("propriétaire d'un profil = le profil lui-même",
      qu.get("targetOwnerUid") === "u1");

  // --- Statut : motif grave → priorité immédiate -------------------------
  await db.doc("statuses/s1").set({authorUid: "auteur2", text: "…"});
  await fileReport(db, "y1", {
    targetType: "status",
    targetPath: "statuses/s1",
    reason: "nuditeSexuel",
  });
  const qs = await queue("status_s1");
  expect("contenu sexuel : priorité haute dès le 1er signalement",
      qs.get("priority") === "high");
  expect("le statut compte ses signalements",
      (await db.doc("statuses/s1").get()).get("reportsCount") === 1);

  // --- Dossier tranché puis rouvert --------------------------------------
  await db.doc("moderationQueue/status_s1").update({status: "closed"});
  await fileReport(db, "y2", {targetType: "status", targetPath: "statuses/s1"});
  expect("un nouveau signalement rouvre le dossier",
      (await queue("status_s1")).get("status") === "open");

  // --- Alerte des administrateurs ----------------------------------------
  await db.doc("admins/chef").set({});
  await db.doc("users/chef").set({displayName: "Chef"});
  await db.doc("posts/p2").set({authorUid: "auteur3", body: "…"});
  await fileReport(db, "z1", {
    targetType: "post",
    targetPath: "posts/p2",
    reason: "violence",
  });
  const alerts = await db.collection("users/chef/notifications").get();
  expect("un dossier devenu prioritaire alerte l'administrateur",
      alerts.size === 1 &&
      alerts.docs[0].get("type") === "moderation" &&
      alerts.docs[0].get("data.entryId") === "post_p2");
  await fileReport(db, "z2", {
    targetType: "post",
    targetPath: "posts/p2",
    reason: "violence",
  });
  expect("pas de nouvelle alerte tant que le dossier reste ouvert",
      (await db.collection("users/chef/notifications").get()).size === 1);

  // --- Décisions (fonction moderate) --------------------------------------
  const asAdmin = (data) => moderate.run({auth: {uid: "chef"}, data});
  let refused = false;
  try {
    await moderate.run({auth: {uid: "auteur"}, data: {
      entryId: "post_p1", action: "dismiss",
    }});
  } catch (err) {
    refused = err.code === "permission-denied";
  }
  expect("un non-administrateur ne décide pas", refused);

  await asAdmin({entryId: "post_p1", action: "dismiss"});
  expect("rejeter remet la publication en ligne",
      (await db.doc("posts/p1").get()).get("hidden") === false &&
      (await queue("post_p1")).get("status") === "dismissed" &&
      (await queue("post_p1")).get("resolvedBy") === "chef");

  await db.doc(msgPath).set({senderUid: "b", type: "text", content: "Encore"});
  await asAdmin({entryId: "message_m1", action: "remove"});
  const removed = (await db.doc(msgPath).get()).data();
  expect("retirer un message le vide sans le supprimer",
      removed.deleted === true && removed.content === "" &&
      removed.removedByModeration === true);

  await db.doc("posts/p3").set({authorUid: "a", commentsCount: 1});
  await db.doc("posts/p3/comments/k9").set({authorUid: "b", text: "Insulte"});
  await fileReport(db, "w1", {
    targetType: "comment",
    targetPath: "posts/p3/comments/k9",
  });
  await asAdmin({entryId: "comment_k9", action: "remove"});
  expect("retirer un commentaire décompte la publication",
      !(await db.doc("posts/p3/comments/k9").get()).exists &&
      (await db.doc("posts/p3").get()).get("commentsCount") === 0);

  let profileRefused = false;
  try {
    await asAdmin({entryId: "user_u1", action: "remove"});
  } catch (err) {
    profileRefused = err.code === "failed-precondition";
  }
  expect("un profil ne se « retire » pas", profileRefused);

  await getAuth().createUser({uid: "u1"});
  await asAdmin({entryId: "user_u1", action: "suspend"});
  expect("suspendre désactive le compte",
      (await getAuth().getUser("u1")).disabled === true &&
      (await db.doc("users/u1").get()).get("suspended") === true &&
      (await queue("user_u1")).get("status") === "suspended");

  await db.doc("posts/p4").set({authorUid: "chef"});
  await fileReport(db, "v1", {targetType: "post", targetPath: "posts/p4"});
  let selfRefused = false;
  try {
    await asAdmin({entryId: "post_p4", action: "suspend"});
  } catch (err) {
    selfRefused = err.code === "failed-precondition";
  }
  expect("un administrateur n'est pas suspendable ici", selfRefused);

  console.log(failures === 0 ? "\nTrigger conforme." :
    `\n${failures} vérification(s) en échec.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
